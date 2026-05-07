-- BigNoteBox Features/AlarmManager.lua
-- Alarm system: tick engine, fire logic, snooze, recurrence calculation,
-- glow dispatch (LibCustomGlow-1.0), sound, combat queue.
--
-- Public API surface:
--   BNB.Alarm.SetAlarm(noteID, alarmData)   -- write alarm to note; nil alarmData = clear
--   BNB.Alarm.ClearAlarm(noteID)            -- remove alarm entirely
--   BNB.Alarm.FireNow(noteID)               -- force-fire for testing
--   BNB.Alarm.Dismiss(noteID)               -- dismiss fired popup, mark fired
--   BNB.Alarm.Snooze(noteID, minutes)       -- snooze by N minutes
--   BNB.Alarm.ResetFired(noteID)            -- re-arm a fired alarm
--   BNB.Alarm.GetNextFireTime(noteID)       -- returns Unix timestamp or nil
--   BNB.Alarm.GlowStart(noteID)             -- start glow on all targets for note
--   BNB.Alarm.GlowStop(noteID)              -- stop glow on all targets for note
--   BNB.Alarm.RegisterGlowTarget(noteID, frame)   -- called by NoteList / StickyNote
--   BNB.Alarm.UnregisterGlowTarget(noteID, frame) -- called on widget hide/destroy

local BNB = BigNoteBox
if not BNB then return end

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
local PULSE_ON        = 10      -- glow-on duration for "pulse" mode (seconds)
local PULSE_OFF       = 10      -- glow-off duration for "pulse" mode (seconds)
local ONCE_DURATION   = 10      -- glow duration for "once" mode (seconds)
local GLOW_KEY        = "bnb_alarm"
local DEFAULT_SOUND   = "Interface/AddOns/BigNoteBox/Assets/Sounds/default.ogg"
local SOUND_CHANNEL   = "Master"

-- Weekday names for recurring UI (1=Mon ... 7=Sun, matches Lua date %w with adjustment)
-- WoW Tuesday reset: server resets on Tuesday 07:00 UTC (region-dependent; we use day-of-week)
local WOW_RESET_DOW = 3   -- Tuesday in Lua's date %w: 0=Sun,1=Mon,2=Tue...

-- ---------------------------------------------------------------------------
-- STATE
-- ---------------------------------------------------------------------------
-- { [noteID] = { frame1, frame2, ... } }  -- active glow target frames
local _glowTargets   = {}
-- { [noteID] = { pulseTimer, mode, glowActive } } -- per-note glow state
local _glowState     = {}
-- Alarms that fired during combat, queued for post-combat delivery
-- { { noteID, firedAt } }
local _combatQueue   = {}
-- Active popup note IDs (at most one visible popup per note; table for extensibility)
local _activePopups  = {}
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

local function SaveAlarm(noteID, alarmData)
    -- alarmData == nil means clear the alarm field entirely
    if alarmData == nil then
        BNB.UpdateNote(noteID, { _clear = { "alarm" } })
    else
        BNB.UpdateNote(noteID, { alarm = alarmData })
    end
end

-- Returns alarmDefaults table from DB, with fallback so we never crash
local function Defaults()
    return (BigNoteBoxDB and BigNoteBoxDB.alarmDefaults) or {
        snoozeDefault = 5,
        glowType      = 2,
        glowColor     = { 0.400, 0.733, 0.416, 1.0 },
        glowMode      = "pulse",
    }
end

-- Safe wrapper around LibSharedMedia sound lookup
local function ResolveSoundPath(soundKey)
    if not soundKey or soundKey == "default" then
        return DEFAULT_SOUND
    end
    if soundKey == "silent" then
        return nil
    end
    -- Try LSM
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        local path = LSM:Fetch("sound", soundKey)
        if path then return path end
    end
    return DEFAULT_SOUND
end

local function PlayAlarmSound(alarm)
    local path = ResolveSoundPath(alarm and alarm.sound)
    if path then
        PlaySoundFile(path, SOUND_CHANNEL)
    end
end

-- ---------------------------------------------------------------------------
-- RECURRENCE: compute next fire time from a fired alarm
-- Returns a new Unix timestamp, or nil if alarm should not recur.
-- ---------------------------------------------------------------------------
local function NextRecurTime(alarm)
    local r = alarm.recur
    if not r then return nil end

    local now = time()

    if r == "weekly" then
        -- WoW weekly reset: next Tuesday 07:00 server time.
        -- We approximate with local time; server offset not accessible in addon.
        local t = date("*t", now)
        -- days until next Tuesday (WOW_RESET_DOW=2 in 0-indexed Sun=0)
        local dow = t.wday - 1  -- 0=Sun, 1=Mon, 2=Tue ...
        local target = 2        -- Tuesday
        local daysAhead = (target - dow + 7) % 7
        if daysAhead == 0 then daysAhead = 7 end  -- next week if today is Tuesday
        t.day  = t.day + daysAhead
        t.hour = 7; t.min = 0; t.sec = 0
        return time(t)

    elseif r == "weekdays" then
        -- recurDays = {1,2,3,...} 1=Mon...7=Sun (mapped from Lua wday)
        local days = alarm.recurDays
        if not days or #days == 0 then return nil end
        -- Find the next weekday at the same HH:MM as original alarm
        local orig = date("*t", alarm.time or now)
        local t    = date("*t", now)
        for offset = 1, 8 do
            t.day = (date("*t", now)).day + offset
            local candidate = time({
                year=t.year, month=t.month, day=t.day,
                hour=orig.hour, min=orig.min, sec=0
            })
            local ct = date("*t", candidate)
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
    return (alarm and alarm.glowType) or def.glowType or 2
end

-- Internal: start LCG glow on a single frame using alarm's glow settings + advanced params
function AM._LCGStart(frame, alarm)
    if not LCG or not frame then return end
    local def    = Defaults()
    local gType  = AM.GetGlowType(alarm)
    local gColor = (alarm and alarm.glowColor) or def.glowColor or { 0.400, 0.733, 0.416, 1.0 }

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
    local mode     = alarm.glowMode or def.glowMode or "pulse"
    local targets  = _glowTargets[noteID] or {}

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
-- POPUP
-- ---------------------------------------------------------------------------
local function ShowAlarmPopup(noteID, missedList)
    -- missedList: optional table of {noteID} for multiple missed alarms
    -- For now show popup for single noteID; overview window handles missed list
    local note  = GetNote(noteID)
    if not note then return end
    local alarm = note.alarm
    if not alarm then return end

    if _activePopups[noteID] then return end  -- already showing
    _activePopups[noteID] = true

    -- Build a simple StaticPopup-style frame
    -- We use a custom frame (not StaticPopup_Show) because we need a snooze dropdown
    if BNB.AlarmPopup and BNB.AlarmPopup.Show then
        BNB.AlarmPopup.Show(noteID, alarm, missedList)
    end
end

-- ---------------------------------------------------------------------------
-- FIRE ALARM
-- ---------------------------------------------------------------------------
local function FireAlarm(noteID, offline)
    local note  = GetNote(noteID)
    if not note then return end
    local alarm = note.alarm
    if not alarm then return end

    -- Sound (skip if silent, skip in combat if combatMode="queue")
    local inCombat   = InCombatLockdown()
    local combatWait = inCombat and alarm.combatMode == "queue"

    if not combatWait then
        PlayAlarmSound(alarm)
    end

    -- Mark alarm as active for all fire modes (used by sticky close to know when to dismiss)
    -- popup mode: _activePopups is set by ShowAlarmPopup itself
    -- sticky/minimized modes: use _activeStickyAlarms so the popup guard isn't tripped

    -- Resolve fire mode (default = "popup")
    local fireMode = alarm.fireMode or "popup"

    -- Handle sticky modes — open/minimize the sticky note, then start glow on its icon.
    -- Glow must start AFTER the sticky frame exists, so we defer via C_Timer.After.
    if fireMode == "sticky" then
        _activeStickyAlarms[noteID] = true
        if BNB.Sticky and BNB.Sticky.Open then
            BNB.Sticky.Open(noteID)
        end
        C_Timer.After(0.1, function()
            AM.GlowStart(noteID)
        end)
    elseif fireMode == "minimized" then
        _activeStickyAlarms[noteID] = true
        if BNB.Sticky and BNB.Sticky.EnsureMinimizedForAlarm then
            BNB.Sticky.EnsureMinimizedForAlarm(noteID)
        end
        -- Icon frame registered by EnsureMinimizedForAlarm after 0.05s; use 0.1s to be safe
        C_Timer.After(0.1, function()
            AM.GlowStart(noteID)
        end)
    else
        -- "popup" (default): glow fires immediately on popup frame
        AM.GlowStart(noteID)
    end

    if combatWait then
        table.insert(_combatQueue, { noteID = noteID, firedAt = time() })
        return
    end

    if offline then
        table.insert(_missedOnLogin, noteID)
        return
    end

    -- Show popup for "popup" mode; sticky modes handle their own display above
    if fireMode == "popup" then
        ShowAlarmPopup(noteID)
    end
end

-- ---------------------------------------------------------------------------
-- DISMISS / SNOOZE / RESET
-- ---------------------------------------------------------------------------
function AM.Dismiss(noteID)
    _activePopups[noteID] = nil
    _activeStickyAlarms[noteID] = nil
    AM.GlowStop(noteID)

    local note  = GetNote(noteID)
    local alarm = note and note.alarm
    if not alarm then return end

    -- Check for recurrence
    local next = NextRecurTime(alarm)
    if next then
        alarm.time        = next
        alarm.fired       = false
        alarm.snoozedUntil = nil
        SaveAlarm(noteID, alarm)
    else
        alarm.fired        = true
        alarm.snoozedUntil = nil
        SaveAlarm(noteID, alarm)
    end

    -- Refresh note list row and overview
    if BNB.RefreshNoteList then BNB.RefreshNoteList() end
    if BNB.AlarmOverview and BNB.AlarmOverview.Refresh then BNB.AlarmOverview.Refresh() end
end

function AM.Snooze(noteID, minutes)
    _activePopups[noteID] = nil
    _activeStickyAlarms[noteID] = nil
    AM.GlowStop(noteID)

    local note  = GetNote(noteID)
    local alarm = note and note.alarm
    if not alarm then return end
    -- Respect snoozeEnabled flag (default true for backwards compat)
    if alarm.snoozeEnabled == false then
        AM.Dismiss(noteID)
        return
    end

    minutes = minutes or alarm.snoozeDefault or Defaults().snoozeDefault or 5
    alarm.snoozedUntil = time() + minutes * 60
    alarm.fired        = false
    SaveAlarm(noteID, alarm)

    if BNB.RefreshNoteList then BNB.RefreshNoteList() end
    if BNB.AlarmOverview and BNB.AlarmOverview.Refresh then BNB.AlarmOverview.Refresh() end
end

function AM.ResetFired(noteID)
    local note  = GetNote(noteID)
    local alarm = note and note.alarm
    if not alarm then return end
    alarm.fired        = false
    alarm.snoozedUntil = nil
    SaveAlarm(noteID, alarm)
    if BNB.RefreshNoteList then BNB.RefreshNoteList() end
    if BNB.AlarmOverview and BNB.AlarmOverview.Refresh then BNB.AlarmOverview.Refresh() end
end

function AM.SetAlarm(noteID, alarmData)
    SaveAlarm(noteID, alarmData)
    if BNB.RefreshNoteList then BNB.RefreshNoteList() end
    if BNB.AlarmOverview and BNB.AlarmOverview.Refresh then BNB.AlarmOverview.Refresh() end
end

function AM.ClearAlarm(noteID)
    AM.GlowStop(noteID)
    _activePopups[noteID] = nil
    _activeStickyAlarms[noteID] = nil
    SaveAlarm(noteID, nil)
    if BNB.RefreshNoteList then BNB.RefreshNoteList() end
    if BNB.AlarmOverview and BNB.AlarmOverview.Refresh then BNB.AlarmOverview.Refresh() end
end

function AM.FireNow(noteID)
    FireAlarm(noteID, false)
end

-- ---------------------------------------------------------------------------
-- NEXT FIRE TIME UTILITY
-- ---------------------------------------------------------------------------
function AM.IsGlowing(noteID)
    local gs = _glowState[noteID]
    return gs ~= nil
end

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
    if alarm.timeType == "ingame" then
        -- In-game time: convert today's HH:MM to a Unix timestamp
        -- If the time has already passed today, return tomorrow's timestamp
        if not alarm.igTime then return nil end
        local h, m = alarm.igTime:match("^(%d+):(%d+)$")
        if not h then return nil end
        local t = date("*t")
        t.hour = tonumber(h); t.min = tonumber(m); t.sec = 0
        local candidate = time(t)
        if candidate <= time() then candidate = candidate + 86400 end
        return candidate
    end
    return alarm.time
end

-- ---------------------------------------------------------------------------
-- TICK — checks all notes for due alarms
-- ---------------------------------------------------------------------------
local _lastTick = 0

local function Tick()
    local now = time()
    if now - _lastTick < TICK_INTERVAL then return end
    _lastTick = now

    local ndb = BigNoteBoxNotesDB
    if not ndb or not ndb.notes then return end

    for noteID, note in pairs(ndb.notes) do
        local alarm = note.alarm
        if alarm and not alarm.fired then
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
    if #_combatQueue == 0 then return end

    -- Collect unique notes that fired during combat
    local seen = {}
    local batch = {}
    for _, entry in ipairs(_combatQueue) do
        if not seen[entry.noteID] then
            seen[entry.noteID] = true
            table.insert(batch, entry.noteID)
        end
    end
    _combatQueue = {}

    -- Determine post-combat delivery mode
    -- Use the first queued alarm's combatPost setting as representative
    local note  = GetNote(batch[1])
    local alarm = note and note.alarm
    local mode  = alarm and alarm.combatPost or "immediate"

    if mode == "summary" then
        BNB:Print(string.format("[BNB] %d alarm(s) fired during combat.", #batch))
        for _, id in ipairs(batch) do ShowAlarmPopup(id) end
    elseif mode == "chat" then
        -- Chat messages were shown during combat; now show popups
        for _, id in ipairs(batch) do
            PlayAlarmSound(GetNote(id) and GetNote(id).alarm)
            ShowAlarmPopup(id)
        end
    else  -- "immediate"
        for _, id in ipairs(batch) do
            PlayAlarmSound(GetNote(id) and GetNote(id).alarm)
            ShowAlarmPopup(id)
        end
    end
end

-- Chat message during combat (combatPost="chat" path — called at fire time)
local function CombatChatNotify(noteID)
    local note = GetNote(noteID)
    local alarm = note and note.alarm
    local label = (alarm and alarm.label ~= "") and alarm.label or (note and note.title) or "Alarm"
    BNB:Print(string.format("[BNB Alarm] \"%s\" fired during combat.", label))
end

-- ---------------------------------------------------------------------------
-- LOGIN SCAN — fire missed alarms
-- ---------------------------------------------------------------------------
local function LoginScan()
    local ndb = BigNoteBoxNotesDB
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
        -- Show all missed alarms in overview window; also open individual popups
        if BNB.AlarmOverview and BNB.AlarmOverview.ShowMissed then
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

    -- OnUpdate ticker frame
    local tickFrame = CreateFrame("Frame", "BNBAlarmTicker", UIParent)
    local _elapsed  = 0
    tickFrame:SetScript("OnUpdate", function(_, dt)
        _elapsed = _elapsed + dt
        if _elapsed >= TICK_INTERVAL then
            _elapsed = 0
            Tick()
        end
    end)

    -- Combat events
    local combatFrame = CreateFrame("Frame", "BNBAlarmCombat")
    combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    combatFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            OnCombatEnd()
        end
    end)

    -- Login scan for missed alarms
    LoginScan()
end

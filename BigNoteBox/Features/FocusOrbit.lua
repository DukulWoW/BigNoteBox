-- BigNoteBox Features/FocusOrbit.lua
-- Slow camera orbit while focus mode is active.
-- Uses only legitimate WoW APIs: MoveViewRightStart / MoveViewRightStop.
-- Stops automatically on combat, movement, and focus mode close.
-- Resumes after movement stops (with configurable delay; 0 = never resume).

local BNB = BigNoteBox

BNB.FocusOrbit = {}
local FO = BNB.FocusOrbit

local _running     = false
local _resumeTimer = nil   -- C_Timer handle

--------------------------------------------------------------------------------
-- INTERNAL
--------------------------------------------------------------------------------
local function _start()
    if _running then return end
    if InCombatLockdown() then return end
    -- Guard: focus frame must be visible
    if not BNB.IsFocusModeOpen or not BNB.IsFocusModeOpen() then return end
    local db = BigNoteBoxDB
    if not db or db.focusOrbitEnabled == false then return end
    local speed = db.focusOrbitSpeed or BNB.DEFAULTS.focusOrbitSpeed
    MoveViewRightStart(speed)
    _running = true
end

local function _stop()
    if not _running then return end
    MoveViewRightStop()
    _running = false
    if _resumeTimer then
        _resumeTimer:Cancel()
        _resumeTimer = nil
    end
end

local function _cancelResume()
    if _resumeTimer then
        _resumeTimer:Cancel()
        _resumeTimer = nil
    end
end

local function _scheduleResume()
    _cancelResume()
    local db = BigNoteBoxDB
    local delay = (db and db.focusOrbitResumeDelay) or BNB.DEFAULTS.focusOrbitResumeDelay
    if delay <= 0 then return end   -- 0 = never resume after movement
    -- Fade overlay back in over a duration tied to the resume delay (capped 1.5–3s)
    local fadeDur = math.max(1.5, math.min(delay, 3.0))
    _resumeTimer = C_Timer.NewTimer(delay, function()
        _resumeTimer = nil
        _start()
        if BNB.FadeInFocusOverlay then BNB.FadeInFocusOverlay(fadeDur) end
    end)
end

--------------------------------------------------------------------------------
-- EVENT FRAME
--------------------------------------------------------------------------------
local ef = CreateFrame("Frame")
ef:RegisterEvent("PLAYER_REGEN_DISABLED")

-- The movement events only matter while Focus mode is open or the setup
-- orbit runs, so they are registered only then (PERF-08: they came in for the
-- whole session, on every step the player took).
local _focusOpen, _setupOrbit = false, false
local function UpdateMoveEvents()
    if _focusOpen or _setupOrbit then
        ef:RegisterEvent("PLAYER_STARTED_MOVING")
        ef:RegisterEvent("PLAYER_STOPPED_MOVING")
    else
        ef:UnregisterEvent("PLAYER_STARTED_MOVING")
        ef:UnregisterEvent("PLAYER_STOPPED_MOVING")
    end
end
ef:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        -- Combat: stop and never auto-resume for this combat
        _stop()
        _cancelResume()
    elseif event == "PLAYER_STARTED_MOVING" then
        _stop()
        _cancelResume()
        if BNB.FadeOutFocusOverlay then BNB.FadeOutFocusOverlay(1.0) end
    elseif event == "PLAYER_STOPPED_MOVING" then
        -- Only schedule resume if focus mode is still open
        if BNB.IsFocusModeOpen and BNB.IsFocusModeOpen() then
            _scheduleResume()
        end
    end
end)

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------
function FO.Start()
    _start()
end

function FO.Stop()
    _stop()
end

-- Focus mode opened or closed (UI/FocusEditor.lua): movement events on or off
function FO.SetFocusOpen(open)
    _focusOpen = open and true or false
    UpdateMoveEvents()
end

-- Setup wizard variants — bypass the IsFocusModeOpen guard.
function FO.StartForSetup()
    _setupOrbit = true
    UpdateMoveEvents()
    if _running then return end
    if InCombatLockdown() then return end
    local db = BigNoteBoxDB
    local speed = (db and db.focusOrbitSpeed) or BNB.DEFAULTS.focusOrbitSpeed
    MoveViewRightStart(speed)
    _running = true
end

function FO.StopForSetup()
    _stop()
    _setupOrbit = false
    UpdateMoveEvents()
end

function FO.Toggle()
    local db = BigNoteBoxDB
    if not db then return end
    local nowEnabled = db.focusOrbitEnabled ~= false
    db.focusOrbitEnabled = not nowEnabled
    if db.focusOrbitEnabled then
        _start()
    else
        _stop()
    end
    -- Refresh spin button texture
    if BNB.UpdateFocusSpinBtn then
        BNB.UpdateFocusSpinBtn(db.focusOrbitEnabled)
    end
    -- Refresh config UI orbit sub-controls if open
    if BNB._focusOrbitRefreshUI then BNB._focusOrbitRefreshUI() end
end

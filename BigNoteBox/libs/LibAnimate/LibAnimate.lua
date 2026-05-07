-------------------------------------------------------------------------------
-- LibAnimate
-- Keyframe-driven animation library for World of Warcraft frames
-- Inspired by animate.css (https://animate.style)
--
-- Supported versions: Retail, TBC Anniversary, MoP Classic
-------------------------------------------------------------------------------

local MAJOR, MINOR = "LibAnimate", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

-------------------------------------------------------------------------------
-- Type Definitions
-------------------------------------------------------------------------------

---@class LibAnimate
---@field animations table<string, AnimationDefinition> Registered animation definitions
---@field activeAnimations table<Frame, AnimationState> Currently running animations
---@field easings table<string, fun(t: number): number> Named easing presets
---@field CubicBezier fun(p1x: number, p1y: number, p2x: number, p2y: number): fun(t: number): number
---@field ApplyEasing fun(easing: EasingSpec, t: number): number

---@class AnimationDefinition
---@field type "entrance"|"exit"|"attention" Animation category
---@field defaultDuration number? Default duration in seconds
---@field defaultDistance number? Default translation distance in pixels
---@field keyframes Keyframe[] Ordered list of keyframes (progress 0.0 to 1.0)

---@class Keyframe
---@field progress number Normalized time position (0.0 to 1.0)
---@field translateX number? Horizontal offset as fraction of distance (default 0)
---@field translateY number? Vertical offset as fraction of distance (default 0)
---@field scale number? Uniform scale factor (default 1.0)
---@field alpha number? Opacity (default 1.0)
---@field easing EasingSpec? Easing for the segment STARTING at this keyframe

--- A named preset (e.g. "easeOutCubic") or cubic-bezier control points {p1x, p1y, p2x, p2y}.
---@alias EasingSpec string|number[]

---@class AnimateOpts
---@field duration number? Override animation duration in seconds
---@field distance number? Override translation distance in pixels
---@field delay number? Delay in seconds before animation starts (default 0)
---@field repeatCount number? Number of times to play (0 = infinite, nil/1 = once)
---@field onFinished fun(frame: Frame)? Callback fired when the animation completes naturally

--- Configuration for a single step in an animation queue.
---@class QueueEntry
---@field name string Animation name
---@field duration number? Duration override in seconds
---@field distance number? Distance override in pixels
---@field delay number? Delay before this step starts in seconds
---@field repeatCount number? Repeat count for this step (0 = infinite)
---@field onFinished fun(frame: Frame)? Callback when this step completes

--- Options for the animation queue.
---@class QueueOpts
---@field onFinished fun(frame: Frame)? Called when the entire sequence completes
---@field loop boolean? If true, restart from entry 1 after the last entry. onFinished is not called while looping.

---@class AnimationState
---@field definition AnimationDefinition
---@field keyframes Keyframe[]
---@field startTime number GetTime() at animation start
---@field duration number Active duration in seconds
---@field distance number Translation distance in pixels
---@field delay number Delay in seconds before animation starts
---@field repeatCount number Number of total repeats (0 = infinite, 1 = once)
---@field currentRepeat number Current repeat iteration (starts at 1)
---@field onFinished fun(frame: Frame)?
---@field anchorPoint string Captured anchor point
---@field anchorRelativeTo Frame? Captured relative-to frame
---@field anchorRelativePoint string Captured relative point
---@field anchorX number Captured anchor X offset
---@field anchorY number Captured anchor Y offset
---@field originalScale number Pre-animation scale
---@field originalAlpha number Pre-animation alpha
---@field hasScale boolean Whether the animation defines scale keyframes
---@field hasTranslate boolean Whether the animation defines translate keyframes
---@field resolvedEasings table<integer, fun(t: number): number>

-------------------------------------------------------------------------------
-- Cached Globals
-------------------------------------------------------------------------------

local GetTime = GetTime
local CreateFrame = CreateFrame
local geterrorhandler = geterrorhandler
local pcall = pcall
local pairs = pairs
local next = next
local ipairs = ipairs
local type = type
local math_min = math.min
local math_abs = math.abs
local math_floor = math.floor
local table_sort = table.sort
local table_insert = table.insert
local table_remove = table.remove

-------------------------------------------------------------------------------
-- State Initialization
-------------------------------------------------------------------------------

lib.animations = lib.animations or {}
lib.activeAnimations = lib.activeAnimations or {}
lib.animationQueues = lib.animationQueues or {}

if not lib.driverFrame then
    lib.driverFrame = CreateFrame("Frame")
    lib.driverFrame:Hide()
end
local driverFrame = lib.driverFrame

-------------------------------------------------------------------------------
-- Easing Functions
-------------------------------------------------------------------------------

--- Named easing presets mapping string names to easing functions.
--- Each function takes a normalized time `t` in [0, 1] and returns the eased value.
---
--- Available presets:
--- - `"linear"` — No easing
--- - `"easeInQuad"`, `"easeOutQuad"`, `"easeInOutQuad"` — Quadratic
--- - `"easeInCubic"`, `"easeOutCubic"`, `"easeInOutCubic"` — Cubic
--- - `"easeInBack"`, `"easeOutBack"`, `"easeInOutBack"` — Back (overshoot)
---@type table<string, fun(t: number): number>
lib.easings = {
    linear = function(t)
        return t
    end,

    easeInQuad = function(t)
        return t * t
    end,

    easeOutQuad = function(t)
        return 1 - (1 - t) * (1 - t)
    end,

    easeInOutQuad = function(t)
        if t < 0.5 then
            return 2 * t * t
        end
        return 1 - (-2 * t + 2) * (-2 * t + 2) / 2
    end,

    easeInCubic = function(t)
        return t * t * t
    end,

    easeOutCubic = function(t)
        local inv = 1 - t
        return 1 - inv * inv * inv
    end,

    easeInOutCubic = function(t)
        if t < 0.5 then
            return 4 * t * t * t
        end
        local inv = -2 * t + 2
        return 1 - inv * inv * inv / 2
    end,

    easeInBack = function(t)
        local c1 = 1.70158
        local c3 = c1 + 1
        return c3 * t * t * t - c1 * t * t
    end,

    easeOutBack = function(t)
        local c1 = 1.70158
        local c3 = c1 + 1
        local inv = t - 1
        return 1 + c3 * inv * inv * inv + c1 * inv * inv
    end,

    easeInOutBack = function(t)
        local c1 = 1.70158
        local c2 = c1 * 1.525
        if t < 0.5 then
            return ((2 * t) * (2 * t) * ((c2 + 1) * (2 * t) - c2)) / 2
        end
        local inv = 2 * t - 2
        return (inv * inv * ((c2 + 1) * inv + c2) + 2) / 2
    end,
}

-------------------------------------------------------------------------------
-- Cubic-Bezier Solver
-------------------------------------------------------------------------------

--- Creates a cubic-bezier easing function from four control points.
--- Uses Newton-Raphson iteration with binary-search fallback.
---@param p1x number X of first control point (0-1)
---@param p1y number Y of first control point
---@param p2x number X of second control point (0-1)
---@param p2y number Y of second control point
---@return fun(t: number): number easingFn Easing function mapping [0,1] to [0,1]
local function CubicBezier(p1x, p1y, p2x, p2y)
    --- Evaluates the X component of the cubic bezier at parameter t.
    ---@param t number Bezier parameter (0-1)
    ---@return number x X coordinate on the bezier curve
    local function sampleCurveX(t)
        return (((1 - 3 * p2x + 3 * p1x) * t + (3 * p2x - 6 * p1x)) * t + 3 * p1x) * t
    end

    --- Evaluates the Y component (output value) of the cubic bezier at parameter t.
    ---@param t number Bezier parameter (0-1)
    ---@return number y Y coordinate on the bezier curve
    local function sampleCurveY(t)
        return (((1 - 3 * p2y + 3 * p1y) * t + (3 * p2y - 6 * p1y)) * t + 3 * p1y) * t
    end

    --- Evaluates the derivative of the X component at parameter t (for Newton-Raphson).
    ---@param t number Bezier parameter (0-1)
    ---@return number dx Derivative of X with respect to t
    local function sampleCurveDerivativeX(t)
        return (3 * (1 - 3 * p2x + 3 * p1x) * t + 2 * (3 * p2x - 6 * p1x)) * t + 3 * p1x
    end

    --- Finds the bezier parameter t that produces a given X value.
    --- Uses Newton-Raphson iteration (8 steps) with binary-search fallback (20 steps).
    ---@param x number Target X value (0-1)
    ---@return number t Bezier parameter that maps to x
    local function solveCurveX(x)
        -- Newton-Raphson
        local t = x
        for _ = 1, 8 do
            local currentX = sampleCurveX(t) - x
            if math_abs(currentX) < 1e-6 then
                return t
            end
            local dx = sampleCurveDerivativeX(t)
            if math_abs(dx) < 1e-6 then
                break
            end
            t = t - currentX / dx
        end

        -- Binary search fallback
        local lo, hi = 0.0, 1.0
        t = x
        for _ = 1, 20 do
            local currentX = sampleCurveX(t)
            if math_abs(currentX - x) < 1e-6 then
                return t
            end
            if currentX > x then
                hi = t
            else
                lo = t
            end
            t = (lo + hi) * 0.5
        end
        return t
    end

    --- Returned easing function: maps a normalized progress value through the bezier curve.
    ---@param x number Normalized progress (0-1), clamped at boundaries
    ---@return number y Eased progress value
    return function(x)
        if x <= 0 then return 0 end
        if x >= 1 then return 1 end
        return sampleCurveY(solveCurveX(x))
    end
end

lib.CubicBezier = CubicBezier

-------------------------------------------------------------------------------
-- ApplyEasing Helper
-------------------------------------------------------------------------------

--- Applies an easing function to a progress value.
--- Accepts a named preset string or a cubic-bezier control point table.
--- This is a utility function; the hot-path uses pre-resolved easing functions instead.
---@param easing EasingSpec Easing preset name or {p1x, p1y, p2x, p2y}
---@param t number Normalized progress (0-1)
---@return number easedT Eased progress value
local function ApplyEasing(easing, t)
    if type(easing) == "string" then
        local fn = lib.easings[easing]
        if fn then return fn(t) end
        return t
    elseif type(easing) == "table" then
        local fn = CubicBezier(easing[1], easing[2], easing[3], easing[4])
        return fn(t)
    end
    return t
end

lib.ApplyEasing = ApplyEasing

-------------------------------------------------------------------------------
-- Keyframe Interpolation
-------------------------------------------------------------------------------

--- Default values for keyframe properties when not explicitly set.
--- Used by `GetProperty` to fill in missing values during interpolation.
---@type table<string, number>
local PROPERTY_DEFAULTS = {
    translateX = 0,
    translateY = 0,
    scale = 1.0,
    alpha = 1.0,
}

--- Finds the two bracketing keyframes for a given progress value.
--- Returns the start and end keyframes of the active segment, the interpolation
--- progress within that segment, and the index of the start keyframe.
---@param keyframes Keyframe[] Ordered keyframe list (progress 0.0 to 1.0)
---@param progress number Normalized animation progress (0-1)
---@return Keyframe kf1 Start keyframe of the active segment
---@return Keyframe kf2 End keyframe of the active segment
---@return number segmentProgress Interpolation progress within the segment (0-1)
---@return integer kf1Index Index of kf1 in the keyframes array
local function FindKeyframes(keyframes, progress)
    -- Handle boundary cases explicitly
    if progress <= 0 then
        local segmentLength = keyframes[2].progress - keyframes[1].progress
        local segmentProgress = 0
        if segmentLength > 0 then
            segmentProgress = (progress - keyframes[1].progress) / segmentLength
        end
        return keyframes[1], keyframes[2], segmentProgress, 1
    end

    local n = #keyframes
    if progress >= 1.0 then
        return keyframes[n - 1], keyframes[n], 1, n - 1
    end

    -- Search for bracketing keyframes
    for i = 1, n - 1 do
        if progress >= keyframes[i].progress and progress <= keyframes[i + 1].progress then
            local segmentLength = keyframes[i + 1].progress - keyframes[i].progress
            local segmentProgress = 0
            if segmentLength > 0 then
                segmentProgress = (progress - keyframes[i].progress) / segmentLength
            end
            return keyframes[i], keyframes[i + 1], segmentProgress, i
        end
    end

    -- Fallback: should never reach here with valid keyframes (0.0 to 1.0 boundary)
    return keyframes[n - 1], keyframes[n], 1, n - 1
end

--- Returns a keyframe property value, falling back to PROPERTY_DEFAULTS if not set.
---@param kf Keyframe The keyframe to read from
---@param name string Property name ("translateX", "translateY", "scale", or "alpha")
---@return number value The property value
local function GetProperty(kf, name)
    if kf[name] ~= nil then
        return kf[name]
    end
    return PROPERTY_DEFAULTS[name]
end

--- Linearly interpolates between two values.
---@param a number Start value
---@param b number End value
---@param t number Interpolation factor (0 = a, 1 = b)
---@return number result Interpolated value
local function Lerp(a, b, t)
    return a + (b - a) * t
end

-------------------------------------------------------------------------------
-- ApplyToFrame
-------------------------------------------------------------------------------

--- Applies interpolated animation properties to a frame.
--- Only modifies properties that the animation actually defines:
--- - Alpha is always applied (backward compatible with slide animations)
--- - Translate is only applied when `state.hasTranslate` is true
--- - Scale is only applied when `state.hasScale` is true, and is relative
---   to `state.originalScale` so user-configured scale is preserved
---@param frame Frame The frame being animated
---@param state AnimationState The active animation state
---@param tx number Interpolated translateX (fraction of distance)
---@param ty number Interpolated translateY (fraction of distance)
---@param sc number Interpolated scale factor (relative to originalScale)
---@param al number Interpolated alpha (opacity)
local function ApplyToFrame(frame, state, tx, ty, sc, al)
    if state.hasTranslate then
        local distance = state.distance or 0
        local offsetX = tx * distance
        local offsetY = ty * distance
        frame:ClearAllPoints()
        frame:SetPoint(state.anchorPoint, state.anchorRelativeTo, state.anchorRelativePoint,
            state.anchorX + offsetX, state.anchorY + offsetY)
    end

    if state.hasScale then
        local finalScale = sc * (state.originalScale or 1)
        if finalScale < 0.001 then finalScale = 0.001 end
        frame:SetScale(finalScale)
    end

    frame:SetAlpha(al)
end

-------------------------------------------------------------------------------
-- Driver Frame OnUpdate
-------------------------------------------------------------------------------

--- Main animation driver. Runs every frame while any animation is active.
--- For each active animation: advances progress, finds bracketing keyframes,
--- applies per-segment easing, interpolates properties, and applies to the frame.
--- Completed animations are snapped to final state and their callbacks are fired
--- in a deferred pass (after all state cleanup) to prevent re-entrancy issues.
driverFrame:SetScript("OnUpdate", function()
    local now = GetTime()
    local toRemove = nil

    for frame, state in pairs(lib.activeAnimations) do
        -- Skip paused animations entirely
        if state.isPaused then -- luacheck: ignore 542
            -- Do nothing: animation is frozen
        else
            local elapsed = now - state.startTime

            -- Handle delay: skip interpolation while in delay period
            if elapsed < state.delay then -- luacheck: ignore 542
                -- Do nothing, frame stays in its pre-animation state
            else
                local rawProgress = math_min(
                    (elapsed - state.delay) / state.duration, 1.0
                )

                -- Find bracketing keyframes
                local kf1, kf2, segmentProgress, kf1Index =
                    FindKeyframes(state.keyframes, rawProgress)

                -- Apply per-segment easing
                if state.resolvedEasings[kf1Index] then
                    segmentProgress =
                        state.resolvedEasings[kf1Index](segmentProgress)
                end

                -- Interpolate properties
                local easedT = segmentProgress
                local tx = Lerp(
                    GetProperty(kf1, "translateX"),
                    GetProperty(kf2, "translateX"), easedT
                )
                local ty = Lerp(
                    GetProperty(kf1, "translateY"),
                    GetProperty(kf2, "translateY"), easedT
                )
                local sc = Lerp(
                    GetProperty(kf1, "scale"),
                    GetProperty(kf2, "scale"), easedT
                )
                local al = Lerp(
                    GetProperty(kf1, "alpha"),
                    GetProperty(kf2, "alpha"), easedT
                )

                -- SlideAnchor interpolation: smoothly move base anchor
                if state.slideStartTime then
                    local slideElapsed = now - state.slideStartTime
                    local slideProgress = math_min(
                        slideElapsed / state.slideDuration, 1.0
                    )
                    state.anchorX = Lerp(
                        state.slideFromX, state.slideToX, slideProgress
                    )
                    state.anchorY = Lerp(
                        state.slideFromY, state.slideToY, slideProgress
                    )
                    -- Clear slide state when complete
                    if slideProgress >= 1.0 then
                        state.anchorX = state.slideToX
                        state.anchorY = state.slideToY
                        state.slideStartTime = nil
                        state.slideDuration = nil
                        state.slideFromX = nil
                        state.slideFromY = nil
                        state.slideToX = nil
                        state.slideToY = nil
                    end
                end

                -- Apply to frame
                ApplyToFrame(frame, state, tx, ty, sc, al)

                -- Check completion with repeat support
                if rawProgress >= 1.0 then
                    if state.repeatCount == 0
                        or state.currentRepeat < state.repeatCount
                    then
                        -- Reset for next repeat (no delay between repeats)
                        state.startTime = now
                        state.delay = 0
                        state.currentRepeat = state.currentRepeat + 1
                    else
                        if not toRemove then toRemove = {} end
                        toRemove[#toRemove + 1] = frame
                    end
                end
            end
        end
    end

    -- Process completions
    if toRemove then
        -- First pass: snap to final values and collect callbacks.
        -- State is intentionally kept alive for frames that have an onFinished
        -- callback so that Animate() -> Stop() inside the callback can restore
        -- the frame to its base anchor before capturing the new anchor.
        local callbacks = nil
        for _, frame in ipairs(toRemove) do
            local state = lib.activeAnimations[frame]
            if state then
                -- Snap to final state
                local lastKf = state.keyframes[#state.keyframes]
                local ftx = GetProperty(lastKf, "translateX")
                local fty = GetProperty(lastKf, "translateY")
                local fsc = GetProperty(lastKf, "scale")
                local fal = GetProperty(lastKf, "alpha")
                ApplyToFrame(frame, state, ftx, fty, fsc, fal)

                if state.onFinished then
                    if not callbacks then callbacks = {} end
                    callbacks[#callbacks + 1] = {
                        fn = state.onFinished, frame = frame, state = state,
                    }
                else
                    lib.activeAnimations[frame] = nil
                end
            end
        end

        -- Second pass: fire callbacks.
        -- After each callback, clear the state only if the callback did not
        -- start a new animation (i.e. the slot still holds the completed state).
        if callbacks then
            for _, cb in ipairs(callbacks) do
                local ok, err = pcall(cb.fn, cb.frame)
                if not ok then
                    geterrorhandler()(err)
                end
                if lib.activeAnimations[cb.frame] == cb.state then
                    lib.activeAnimations[cb.frame] = nil
                end
            end
        end
    end

    -- Hide driver if no active animations
    if not next(lib.activeAnimations) then
        driverFrame:Hide()
    end
end)

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------

--- Plays a registered animation on a frame.
---
--- The frame must have exactly one anchor point set via `SetPoint()`.
--- Frames with multiple anchor points (two-point sizing) are not supported
--- and will lose their secondary anchors during animation.
---
--- If the frame is already animating, the current animation is stopped
--- (restoring the frame to its pre-animation state) before the new one starts.
---
--- Supports `delay` to wait before starting and `repeatCount` to repeat
--- (0 = infinite). If the frame has an active queue, the queue is cleared.
---
--- For exit animations, the frame is left at its final keyframe state when
--- the animation completes. The consumer must handle cleanup (e.g. `frame:Hide()`)
--- in the `onFinished` callback.
---
--- For attention-seeker animations, the frame returns to its original state
--- when the animation completes (keyframes start and end at identity values).
---
--- Usage:
--- ```lua
--- local LibAnimate = LibStub("LibAnimate")
--- LibAnimate:Animate(myFrame, "fadeIn", {
---     duration = 0.5,
---     delay = 0.2,
---     repeatCount = 3,
---     onFinished = function(frame) print("done!") end,
--- })
--- ```
---@param frame Frame The frame to animate (must have one anchor point)
---@param name string Registered animation name
---@param opts AnimateOpts? Animation options
---@return boolean success Always returns true on success; errors on invalid input
function lib:Animate(frame, name, opts)
    if opts ~= nil and type(opts) ~= "table" then
        error("LibAnimate: opts must be a table or nil", 2)
    end
    opts = opts or {}

    -- Stop existing animation on this frame
    if lib.activeAnimations[frame] then
        self:Stop(frame)
    end

    -- Clear any active queue on this frame
    lib.animationQueues[frame] = nil

    local def = lib.animations[name]
    if not def then
        error("LibAnimate: Unknown animation '" .. tostring(name) .. "'", 2)
    end

    local duration = opts.duration or def.defaultDuration
    if not duration or duration <= 0 then
        error("LibAnimate: Animation duration must be greater than 0", 2)
    end

    -- Capture current anchor
    local pt, rel, relPt, x, y = frame:GetPoint()
    if not pt then
        error("LibAnimate: Frame has no anchor point set", 2)
    end

    local originalScale = frame:GetScale()
    local originalAlpha = frame:GetAlpha()

    -- Pre-resolve easing functions to avoid per-tick allocation.
    -- Convention: kf.easing applies to the segment STARTING at that keyframe
    -- (i.e., the easing from kf[i] to kf[i+1] is defined on kf[i]).
    local resolvedEasings = {}
    for i, kf in ipairs(def.keyframes) do
        if kf.easing then
            if type(kf.easing) == "string" then
                resolvedEasings[i] = lib.easings[kf.easing] or lib.easings.linear
            elseif type(kf.easing) == "table" then
                resolvedEasings[i] = CubicBezier(kf.easing[1], kf.easing[2], kf.easing[3], kf.easing[4])
            end
        end
    end

    -- Determine which properties the animation actually defines.
    -- Alpha is always animated (backward compatible: slide animations rely
    -- on the default alpha=1.0 being applied every tick).
    -- Scale and translate are conditional to avoid overriding user-configured values.
    local hasScale, hasTranslate = false, false
    for _, kf in ipairs(def.keyframes) do
        if kf.scale ~= nil then hasScale = true end
        if kf.translateX ~= nil or kf.translateY ~= nil then hasTranslate = true end
    end

    local delay = opts.delay or 0
    if type(delay) ~= "number" or delay < 0 then
        error("LibAnimate: delay must be a non-negative number", 2)
    end

    local repeatCount = opts.repeatCount or 1
    if type(repeatCount) ~= "number" or repeatCount < 0 or repeatCount ~= math_floor(repeatCount) then
        error("LibAnimate: repeatCount must be 0 (infinite) or a positive integer", 2)
    end

    local state = {
        definition = def,
        keyframes = def.keyframes,
        startTime = GetTime(),
        duration = duration,
        distance = opts.distance or def.defaultDistance or 0,
        delay = delay,
        repeatCount = repeatCount,
        currentRepeat = 1,
        onFinished = opts.onFinished,
        anchorPoint = pt,
        anchorRelativeTo = rel,
        anchorRelativePoint = relPt,
        anchorX = x or 0,
        anchorY = y or 0,
        originalScale = originalScale,
        originalAlpha = originalAlpha,
        hasScale = hasScale,
        hasTranslate = hasTranslate,
        resolvedEasings = resolvedEasings,
    }

    lib.activeAnimations[frame] = state
    driverFrame:Show()

    -- Apply first keyframe immediately so frames are placed at their
    -- animation start positions right away. Without this, entrance
    -- animations leave the frame visible at its original anchor until
    -- the next OnUpdate tick, which causes overlapping frames when
    -- multiple animations are started in quick succession.
    local kf1 = def.keyframes[1]
    ApplyToFrame(frame, state,
        GetProperty(kf1, "translateX"),
        GetProperty(kf1, "translateY"),
        GetProperty(kf1, "scale"),
        GetProperty(kf1, "alpha"))

    return true
end

--- Stops the animation on a frame and restores it to its pre-animation state.
--- Only restores properties that the animation actually modified:
--- translate and scale are conditional, alpha is always restored.
--- If the frame has an active animation queue, the queue is also cleared.
--- Does nothing if the frame is not currently animating and has no queue.
--- The `onFinished` callback is NOT fired when an animation is stopped.
---@param frame Frame The frame to stop animating
function lib:Stop(frame)
    -- Clear any active queue on this frame
    lib.animationQueues[frame] = nil

    local state = lib.activeAnimations[frame]
    if not state then return end

    -- Restore only properties that were animated
    if state.hasTranslate then
        frame:ClearAllPoints()
        frame:SetPoint(state.anchorPoint, state.anchorRelativeTo, state.anchorRelativePoint,
            state.anchorX, state.anchorY)
    end
    if state.hasScale then
        frame:SetScale(state.originalScale)
    end
    frame:SetAlpha(state.originalAlpha)

    lib.activeAnimations[frame] = nil

    if not next(lib.activeAnimations) then
        driverFrame:Hide()
    end
end

--- Updates the base anchor offsets of an in-progress animation.
--- Use this when the frame's logical position changes during animation
--- (e.g. repositioning a notification while it slides in).
--- Does nothing if the frame is not currently animating.
---@param frame Frame The animated frame
---@param x number New base anchor X offset
---@param y number New base anchor Y offset
function lib:UpdateAnchor(frame, x, y)
    local state = lib.activeAnimations[frame]
    if state then
        state.anchorX = x
        state.anchorY = y
    end
end

--- Returns whether a frame currently has an active animation.
---@param frame Frame The frame to check
---@return boolean isAnimating True if the frame is currently animating
function lib:IsAnimating(frame)
    return lib.activeAnimations[frame] ~= nil
end

-------------------------------------------------------------------------------
-- Animation Queue
-------------------------------------------------------------------------------

--- Internal helper to start the next entry in an animation queue.
--- Retrieves the current queue entry, builds options, and calls Animate
--- with an internal onFinished that advances the queue.
--- Exposed as lib._startQueueEntry for internal use by SkipToEntry/RemoveQueueEntry.
---@param self LibAnimate
---@param frame Frame The frame being animated
local function StartQueueEntry(self, frame)
    local queue = self.animationQueues[frame]
    if not queue then return end

    local entry = queue.entries[queue.index]
    if not entry then
        if queue.loop then
            if #queue.entries == 0 then
                self.animationQueues[frame] = nil
                if queue.onFinished then queue.onFinished(frame) end
                return
            end
            queue.index = 1
            StartQueueEntry(self, frame)
            return
        end
        -- Queue exhausted
        local onFinished = queue.onFinished
        self.animationQueues[frame] = nil
        if onFinished then
            local ok, err = pcall(onFinished, frame)
            if not ok then
                geterrorhandler()(err)
            end
        end
        return
    end

    local opts = {
        duration = entry.duration,
        distance = entry.distance,
        delay = entry.delay,
        repeatCount = entry.repeatCount,
        onFinished = function(f)
            -- Fire per-step callback (pcall so queue always advances)
            if entry.onFinished then
                local ok, err = pcall(entry.onFinished, f)
                if not ok then
                    geterrorhandler()(err)
                end
            end
            -- Advance queue
            if self.animationQueues[f] then
                self.animationQueues[f].index =
                    self.animationQueues[f].index + 1
                StartQueueEntry(self, f)
            end
        end,
    }

    -- Preserve slide state from current animation before Animate() destroys it.
    -- When a queue transitions between entries, Animate() calls Stop() which
    -- restores the frame to its pre-animation anchor and wipes all state.
    -- Without this, a SlideAnchor call that started during a previous entry
    -- would be lost, snapping the frame to a stale position.
    local prevState = lib.activeAnimations[frame]
    local savedSlide
    if prevState and prevState.slideStartTime then
        savedSlide = {
            anchorX = prevState.anchorX,
            anchorY = prevState.anchorY,
            slideFromX = prevState.slideFromX,
            slideFromY = prevState.slideFromY,
            slideToX = prevState.slideToX,
            slideToY = prevState.slideToY,
            slideDuration = prevState.slideDuration,
            slideStartTime = prevState.slideStartTime,
            slideElapsedAtPause = prevState.slideElapsedAtPause,
        }
    end

    -- Save/restore queue around Animate() since it clears queues
    local savedQueue = self.animationQueues[frame]
    self:Animate(frame, entry.name, opts)
    self.animationQueues[frame] = savedQueue

    -- Restore in-progress slide state onto the new animation state.
    -- This includes anchorX/Y so the frame continues from its current
    -- mid-slide position rather than snapping to the anchor that
    -- Stop() restored during the Animate() call.
    if savedSlide then
        local newState = lib.activeAnimations[frame]
        if newState then
            newState.anchorX = savedSlide.anchorX
            newState.anchorY = savedSlide.anchorY
            newState.slideFromX = savedSlide.slideFromX
            newState.slideFromY = savedSlide.slideFromY
            newState.slideToX = savedSlide.slideToX
            newState.slideToY = savedSlide.slideToY
            newState.slideDuration = savedSlide.slideDuration
            newState.slideStartTime = savedSlide.slideStartTime
            newState.slideElapsedAtPause = savedSlide.slideElapsedAtPause
        end
    end
end

lib._startQueueEntry = StartQueueEntry

--- Queues a sequence of animations to play one after another on a frame.
--- Each entry can have its own duration, distance, delay, repeatCount,
--- and onFinished callback.
--- The sequence-level `onFinished` fires after the entire queue completes.
---
--- If any animation is already running on the frame, it is stopped and the
--- frame is restored before the queue begins.
---
--- All animation names are validated upfront; an error is thrown if any
--- entry references an unregistered animation.
---
--- The `opts.loop` flag causes the queue to restart from entry 1 after the
--- last entry finishes. While looping, `opts.onFinished` is NOT called.
--- A looping queue can be stopped with `ClearQueue()` or `Stop()`.
--- If all entries are removed from a looping queue (via `RemoveQueueEntry`),
--- the loop ends and `onFinished` is called.
---@param frame Frame The frame to animate
---@param entries QueueEntry[] Array of animation steps
---@param opts QueueOpts? Sequence-level options (onFinished, loop)
function lib:Queue(frame, entries, opts)
    if not frame then
        error("LibAnimate:Queue — frame must not be nil", 2)
    end
    if type(entries) ~= "table" or #entries == 0 then
        error("LibAnimate:Queue — entries must be a non-empty table", 2)
    end

    if opts ~= nil and type(opts) ~= "table" then
        error("LibAnimate:Queue — opts must be a table or nil", 2)
    end
    opts = opts or {}

    if opts.loop ~= nil and type(opts.loop) ~= "boolean" then
        error("LibAnimate:Queue — opts.loop must be a boolean", 2)
    end

    -- Validate all animation names upfront
    for i, entry in ipairs(entries) do
        if type(entry.name) ~= "string"
            or not lib.animations[entry.name]
        then
            error(
                "LibAnimate:Queue — invalid animation name '"
                    .. tostring(entry.name)
                    .. "' at entry " .. i,
                2
            )
        end
    end

    -- Stop any current animation and clear existing queue
    self:Stop(frame)

    -- Initialize the queue
    lib.animationQueues[frame] = {
        entries = entries,
        index = 1,
        onFinished = opts.onFinished,
        loop = opts.loop or false,
    }

    StartQueueEntry(self, frame)
end

--- Cancels the animation queue on a frame and stops the current animation.
--- The frame is restored to its pre-animation state. No callbacks are fired.
---@param frame Frame The frame to cancel the queue on
function lib:ClearQueue(frame)
    lib.animationQueues[frame] = nil
    self:Stop(frame)
end

--- Returns whether a frame has an active animation queue.
---@param frame Frame The frame to check
---@return boolean isQueued True if the frame has a pending queue
function lib:IsQueued(frame)
    return lib.animationQueues[frame] ~= nil
end

-------------------------------------------------------------------------------
-- Pause / Resume / IsPaused
-------------------------------------------------------------------------------

--- Freezes the current animation mid-progress.
--- The OnUpdate loop skips paused frames entirely. Does nothing if the
--- frame has no active animation or is already paused.
---@param frame Frame The frame to pause
function lib:PauseQueue(frame)
    local state = lib.activeAnimations[frame]
    if not state or state.isPaused then return end

    local now = GetTime()
    state.elapsedAtPause = now - state.startTime
    state.isPaused = true

    -- Also freeze any active slide
    if state.slideStartTime then
        state.slideElapsedAtPause = now - state.slideStartTime
    end
end

--- Resumes a paused animation from exactly where it left off.
--- Does nothing if the frame is not paused.
---@param frame Frame The frame to resume
function lib:ResumeQueue(frame)
    local state = lib.activeAnimations[frame]
    if not state or not state.isPaused then return end

    local now = GetTime()
    state.startTime = now - state.elapsedAtPause
    state.isPaused = nil
    state.elapsedAtPause = nil

    -- Also resume any active slide
    if state.slideStartTime and state.slideElapsedAtPause then
        state.slideStartTime = now - state.slideElapsedAtPause
        state.slideElapsedAtPause = nil
    end
end

--- Returns whether a frame has an active animation that is paused.
---@param frame Frame The frame to check
---@return boolean isPaused True if the frame's animation is paused
function lib:IsPaused(frame)
    local state = lib.activeAnimations[frame]
    return state ~= nil and state.isPaused == true
end

-------------------------------------------------------------------------------
-- SlideAnchor
-------------------------------------------------------------------------------

--- Smoothly interpolates the internal anchor position over the given
--- duration without interrupting the current animation or queue. The
--- running animation continues calculating offsets relative to the
--- smoothly-moving base position.
---
--- Requires an active animation on the frame; errors otherwise.
--- If a slide is already in progress, snaps the current
--- slide to completion before starting the new one.
---
--- The slide respects pause state: while paused, slide progress does not
--- advance. On resume, the slide picks up where it left off.
---@param frame Frame The frame whose anchor to slide
---@param newX number Target anchor X offset
---@param newY number Target anchor Y offset
---@param duration number Duration of the slide in seconds
function lib:SlideAnchor(frame, newX, newY, duration)
    local state = lib.activeAnimations[frame]
    if not state then
        error("LibAnimate: SlideAnchor requires an active animation on the frame", 2)
    end

    if type(duration) ~= "number" or duration <= 0 then
        error("LibAnimate: SlideAnchor duration must be a positive number", 2)
    end

    -- If already sliding, snap current slide to completion first
    if state.slideStartTime then
        state.anchorX = state.slideToX
        state.anchorY = state.slideToY
        state.slideStartTime = nil
        state.slideDuration = nil
        state.slideFromX = nil
        state.slideFromY = nil
        state.slideToX = nil
        state.slideToY = nil
        state.slideElapsedAtPause = nil
    end

    -- Start new slide from current anchor position
    state.slideFromX = state.anchorX
    state.slideFromY = state.anchorY
    state.slideToX = newX
    state.slideToY = newY
    state.slideDuration = duration
    state.slideStartTime = GetTime()

    -- If currently paused, record slide elapsed at pause as 0
    if state.isPaused then
        state.slideElapsedAtPause = 0
    end
end

-------------------------------------------------------------------------------
-- SkipToEntry
-------------------------------------------------------------------------------

--- Jumps directly to a specific queue entry, skipping all intermediate
--- steps. No callbacks fire for skipped entries. The current animation
--- is stopped and the target entry begins immediately.
---@param frame Frame The frame with an active queue
---@param index number The 1-based index of the queue entry to jump to
function lib:SkipToEntry(frame, index)
    local queue = lib.animationQueues[frame]
    if not queue then return end

    if type(index) ~= "number"
        or index < 1
        or index > #queue.entries
        or index ~= math_floor(index)
    then
        return
    end

    -- Remove current animation without full restore (don't call Stop)
    lib.activeAnimations[frame] = nil

    -- Set queue to target index and start it
    queue.index = index
    StartQueueEntry(self, frame)
end

-------------------------------------------------------------------------------
-- RemoveQueueEntry
-------------------------------------------------------------------------------

--- Removes a specific entry from the pending queue by index.
--- Behaviour depends on the entry's position relative to the current step:
--- - Before current: entry is removed and `queue.index` is decremented
--- - At current: entry is removed, current animation stops, next entry starts
--- - After current: entry is simply removed with no disruption
---@param frame Frame The frame with an active queue
---@param index number The 1-based index of the entry to remove
function lib:RemoveQueueEntry(frame, index)
    local queue = lib.animationQueues[frame]
    if not queue then return end

    if type(index) ~= "number"
        or index < 1
        or index > #queue.entries
        or index ~= math_floor(index)
    then
        return
    end

    if index < queue.index then
        -- Entry is before the current step
        table_remove(queue.entries, index)
        queue.index = queue.index - 1
    elseif index == queue.index then
        -- Entry is the currently playing step
        table_remove(queue.entries, index)
        -- Stop current animation without full restore
        lib.activeAnimations[frame] = nil
        -- Start whatever is now at queue.index (may be exhausted)
        StartQueueEntry(self, frame)
    else
        -- Entry is after the current step
        table_remove(queue.entries, index)
    end
end

-------------------------------------------------------------------------------
-- InsertQueueEntry
-------------------------------------------------------------------------------

--- Inserts a new entry into the current animation queue for the given frame.
--- If `index` is omitted, the entry is appended to the end of the queue.
--- If `index` is provided, the entry is inserted at that 1-based position,
--- shifting subsequent entries forward.
---
--- Behaviour details:
--- - The entry is validated before insertion: `entry.name` must reference
---   a registered animation, otherwise an error is thrown
--- - Out-of-range indices are clamped to the append position (end + 1)
--- - When inserting before or at the currently-playing entry, `queue.index`
---   is incremented so the currently-playing animation stays aligned
--- - An entry inserted before the current index will NOT be played, because
---   it has already been "passed" in the queue sequence
--- - Works on both RUNNING and PAUSED queues
---@param frame Frame The frame that has an active animation queue
---@param entry QueueEntry The animation entry to insert
---@param index number? 1-based position to insert at (clamped if out of range). Omit to append.
function lib:InsertQueueEntry(frame, entry, index)
    if not frame then
        error("LibAnimate: InsertQueueEntry: frame must not be nil", 2)
    end

    local queue = lib.animationQueues[frame]
    if not queue then
        error("LibAnimate: InsertQueueEntry: no active queue for this frame", 2)
    end

    if type(entry) ~= "table" then
        error("LibAnimate: InsertQueueEntry: entry must be a table", 2)
    end
    if type(entry.name) ~= "string" then
        error("LibAnimate: InsertQueueEntry: entry.name must be a string", 2)
    end
    if not lib.animations[entry.name] then
        error("LibAnimate: InsertQueueEntry: unknown animation '" .. tostring(entry.name) .. "'", 2)
    end

    local count = #queue.entries

    if index == nil then
        queue.entries[count + 1] = entry
        return
    end

    if type(index) ~= "number" or index < 1 or index ~= math_floor(index) then
        error("LibAnimate: InsertQueueEntry: index must be a positive integer", 2)
    end

    if index > count + 1 then
        index = count + 1
    end

    table_insert(queue.entries, index, entry)

    if index <= queue.index then
        queue.index = queue.index + 1
    end
end

-------------------------------------------------------------------------------
-- GetQueueInfo
-------------------------------------------------------------------------------

--- Returns the current queue state for a frame: the 1-based index of the
--- currently-playing entry and the total number of entries in the queue.
--- Returns nil, nil if no queue is active on the frame.
---
--- Useful for computing insert positions and for tracking how indices shift
--- after calls to `InsertQueueEntry` or `RemoveQueueEntry`.
---@param frame Frame The frame to query
---@return number|nil currentIndex 1-based index of the currently-playing entry, or nil if no queue
---@return number|nil totalEntries Total number of entries in the queue, or nil if no queue
function lib:GetQueueInfo(frame)
    local queue = lib.animationQueues[frame]
    if not queue then
        return nil, nil
    end
    return queue.index, #queue.entries
end

--- Returns the definition table for a registered animation.
---@param name string The animation name
---@return AnimationDefinition? definition The animation definition, or nil if not registered
function lib:GetAnimationInfo(name)
    return lib.animations[name]
end

--- Returns a sorted list of all registered animation names.
---@return string[] names Alphabetically sorted animation names
function lib:GetAnimationNames()
    local names = {}
    for animName in pairs(lib.animations) do
        names[#names + 1] = animName
    end
    table_sort(names)
    return names
end

--- Returns a sorted list of all registered entrance animation names.
---@return string[] names Alphabetically sorted entrance animation names
function lib:GetEntranceAnimations()
    local names = {}
    for animName, def in pairs(lib.animations) do
        if def.type == "entrance" then
            names[#names + 1] = animName
        end
    end
    table_sort(names)
    return names
end

--- Returns a sorted list of all registered exit animation names.
---@return string[] names Alphabetically sorted exit animation names
function lib:GetExitAnimations()
    local names = {}
    for animName, def in pairs(lib.animations) do
        if def.type == "exit" then
            names[#names + 1] = animName
        end
    end
    table_sort(names)
    return names
end

--- Returns a sorted list of all registered attention-seeker animation names.
---@return string[] names Alphabetically sorted attention animation names
function lib:GetAttentionAnimations()
    local names = {}
    for name, def in pairs(lib.animations) do
        if def.type == "attention" then
            names[#names + 1] = name
        end
    end
    table_sort(names)
    return names
end

--- Registers a custom animation definition.
---
--- Keyframe requirements:
--- - At least 2 keyframes
--- - Sorted ascending by `progress`
--- - First keyframe must have `progress = 0.0`
--- - Last keyframe must have `progress = 1.0`
---
--- Easing on a keyframe applies to the segment STARTING at that keyframe
--- (i.e., the transition from `kf[i]` to `kf[i+1]` uses `kf[i].easing`).
---
--- Usage:
--- ```lua
--- LibAnimate:RegisterAnimation("customSlide", {
---     type = "entrance",
---     defaultDuration = 0.4,
---     defaultDistance = 200,
---     keyframes = {
---         { progress = 0.0, translateX = -1.0, alpha = 0 },
---         { progress = 1.0, translateX = 0, alpha = 1.0 },
---     },
--- })
--- ```
---@param name string Unique animation name
---@param definition AnimationDefinition Animation definition table
function lib:RegisterAnimation(name, definition)
    if type(name) ~= "string" then
        error("LibAnimate: Animation name must be a string", 2)
    end
    if type(definition) ~= "table" then
        error("LibAnimate: Animation definition must be a table", 2)
    end
    if not definition.type then
        error("LibAnimate: Animation definition must have a 'type' field ('entrance', 'exit', or 'attention')", 2)
    end
    if not definition.keyframes or #definition.keyframes < 2 then
        error("LibAnimate: Animation must have at least 2 keyframes", 2)
    end

    -- Validate keyframe ordering
    local keyframes = definition.keyframes
    for i = 2, #keyframes do
        if keyframes[i].progress < keyframes[i - 1].progress then
            error("LibAnimate: Keyframes must be sorted by progress (ascending)", 2)
        end
    end

    -- Validate per-keyframe easing
    for i = 1, #keyframes do
        local kf = keyframes[i]
        if kf.easing ~= nil then
            if type(kf.easing) == "table" then
                if #kf.easing ~= 4 then
                    error("LibAnimate: cubic-bezier easing must have exactly 4 values", 2)
                end
                for j = 1, 4 do
                    if type(kf.easing[j]) ~= "number" then
                        error("LibAnimate: cubic-bezier easing values must be numbers", 2)
                    end
                end
            elseif type(kf.easing) ~= "string" then
                error("LibAnimate: keyframe easing must be a string or a cubic-bezier table", 2)
            end
        end
    end

    -- Validate boundaries
    if keyframes[1].progress ~= 0.0 then
        error("LibAnimate: First keyframe must have progress = 0.0", 2)
    end
    if keyframes[#keyframes].progress ~= 1.0 then
        error("LibAnimate: Last keyframe must have progress = 1.0", 2)
    end

    -- Validate defaultDuration if provided
    if definition.defaultDuration and definition.defaultDuration <= 0 then
        error("LibAnimate: defaultDuration must be greater than 0", 2)
    end

    lib.animations[name] = definition
end

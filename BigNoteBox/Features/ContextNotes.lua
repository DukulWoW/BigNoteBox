-- BigNoteBox Features/ContextNotes.lua — Contextual note surfacing
--
-- Matches note.context against the player's current environment and surfaces
-- matching notes via:
--   1. Minimap badge (a count overlay on the minimap button)
--   2. Toast notification (a small slide-in frame, auto-dismissed after 6s)
--
-- note.context schema (stored in BigNoteBoxNotesDB.notes[id].context):
--   nil / ""         → note is "global" (matches everywhere)
--   "zone:Elwynn Forest"
--   "instance:Molten Core"
--   "player:Thrall"
--   "subzone:The Canals"
--
-- Public API (called from Events.lua):
--   BNB.CheckContextualNotes()   — call on zone change / login
--
-- Internal:
--   BNB._contextMatches          — list of noteIDs matching current context

local BNB = BigNoteBox
local L   = BNB.L

BNB._contextMatches = BNB._contextMatches or {}
BNB._autoWaypoints  = BNB._autoWaypoints  or {}  -- noteID → TomTom uid (or true for retail)

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

local function GetCurrentPlayer()
    return UnitName("target")   -- nil if no target
end

-- ── Match a single note against current context ────────────────────────────────
-- Returns true if the note should surface.
local function NoteMatches(note)
    -- Scope guard: character-scoped notes only surface for their owner.
    local sc = note.scope
    if sc and sc ~= "global" then
        local charKey = sc:match("^char:(.+)$")
        if charKey and charKey ~= BNB.currentChar then return false end
    end

    local ctx = note.context
    if not ctx or ctx == "" then return false end

    local kind, value = ctx:match("^(%w+):(.+)$")
    if not kind or not value then return false end

    value = value:lower()

    if kind == "zone" or kind == "instance" then
        local curKind, curVal = GetCurrentZone()
        return curKind == kind and curVal:lower() == value
    elseif kind == "subzone" then
        local curSub = GetSubZoneText and GetSubZoneText() or ""
        return curSub:lower() == value
    elseif kind == "player" then
        local tgt = GetCurrentPlayer()
        if tgt then
            tgt = tgt:lower()
            -- Match against full value or just the name portion (before realm hyphen)
            local valName = value:match("^([^-]+)") or value
            if tgt == value or tgt == valName then return true end
        end
        for i = 1, GetNumGroupMembers and GetNumGroupMembers() or 0 do
            local member = GetRaidRosterInfo and select(1, GetRaidRosterInfo(i))
            if member then
                member = member:lower()
                local valName = value:match("^([^-]+)") or value
                if member == value or member == valName then return true end
            end
        end
        return false
    end
    return false
end

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
    return (db and db.popupHoldTime) or 5
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
    UIFrameFadeOut(f, TOAST_FADE, f:GetAlpha(), 0)
    C_Timer.After(TOAST_FADE + 0.05, function() f:Hide() end)
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

local function ShowToast(matchIDs, locationName)
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
        f._sub:SetText(locationName or "")

        f:SetScript("OnMouseDown", function(_, btn)
            if btn == "RightButton" then
                _countdown.running = false; f:SetScript("OnUpdate", nil); f:Hide()
                return
            end
            if BNB.mainFrame then
                BNB.mainFrame:Show()
                if BNB.SelectNote then BNB.SelectNote(matchIDs[1]) end
            end
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
            if BNB.mainFrame then
                BNB.mainFrame:Show()
                if BNB.RefreshNoteList then BNB.RefreshNoteList() end
            end
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
                row._lbl:SetText("|cffffd100•|r  " .. title)
                row._lbl:SetTextColor(tc.r, tc.g, tc.b, 1)
            else
                row._lbl:SetText("|cffffd100•|r  " .. title)
                row._lbl:SetTextColor(0.85, 0.85, 0.85)
            end

            -- Show sub-zone tag if this note is bound to a sub-zone
            local ctx = note and note.context or ""
            local ctxKind, ctxVal = ctx:match("^(%w+):(.+)$")
            if ctxKind == "subzone" and ctxVal and ctxVal ~= "" then
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
                if BNB.mainFrame then
                    BNB.mainFrame:Show()
                    if BNB.SelectNote then BNB.SelectNote(noteID) end
                end
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
    f:SetAlpha(0)
    UIFrameFadeIn(f, TOAST_FADE, 0, 1)

    -- Start countdown after fade-in completes
    C_Timer.After(TOAST_FADE, function()
        if f:IsVisible() then StartCountdown(f) end
    end)
end

-- ── Main check ────────────────────────────────────────────────────────────────
function BNB.CheckContextualNotes()
    if not BigNoteBoxDB or BigNoteBoxDB.contextSurface == false then
        UpdateMinimapBadge(0)
        return
    end
    if not BigNoteBoxNotesDB or not BigNoteBoxNotesDB.notes then return end

    local matches   = {}
    local matchSet  = {}
    local stickyIDs = {}
    local popupIDs  = {}
    for _, note in pairs(BigNoteBoxNotesDB.notes) do
        if note and note.context and note.context ~= "" then
            if NoteMatches(note) then
                matches[#matches + 1]  = note.id
                matchSet[note.id]      = true
                if note.contextDisplay == "sticky" then
                    stickyIDs[#stickyIDs + 1] = note.id
                elseif note.contextDisplay == "both" then
                    stickyIDs[#stickyIDs + 1] = note.id
                    popupIDs[#popupIDs + 1]  = note.id
                else
                    popupIDs[#popupIDs + 1]  = note.id
                end
            end
        end
    end

    local prev    = BNB._contextMatches or {}
    local prevSet = {}
    for _, id in ipairs(prev) do prevSet[id] = true end

    BNB._contextMatches = matches

    -- ── Zone-leave: notes that were matching but no longer are ─────────────────
    local hasKeepWP = false  -- track if any departing note wants to keep its WP
    for _, id in ipairs(prev) do
        if not matchSet[id] then
            local note = BNB.GetNote(id)
            local action = note and note.contextLeave  -- nil/"keep", "minimize", "hide"
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

    -- Determine which notes are newly entering context (weren't matching before)
    local newPopupIDs  = {}
    local newStickyIDs = {}
    for _, id in ipairs(popupIDs) do
        if not prevSet[id] then newPopupIDs[#newPopupIDs + 1] = id end
    end
    for _, id in ipairs(stickyIDs) do
        if not prevSet[id] then newStickyIDs[#newStickyIDs + 1] = id end
    end

    -- Only fire enter-alerts for notes that are genuinely new to this context
    if #newPopupIDs > 0 or #newStickyIDs > 0 then
        local _, locName = GetCurrentZone()
        C_Timer.After(0.5, function()
            if BNB.Sticky and BNB.Sticky.Open then
                for _, noteID in ipairs(newStickyIDs) do
                    pcall(function() BNB.Sticky.Open(noteID) end)
                end
            end
            if #newPopupIDs > 0 then
                ShowToast(newPopupIDs, locName)
            end
        end)
    end

    -- ── Waypoint dispatch on zone entry ───────────────────────────────────────
    -- Fire for every currently-matching note that has a waypoint, each time the
    -- zone changes. Not limited to "new" matches — the note may have been matched
    -- already (e.g. you were already in the zone when you saved the waypoint).
    -- Uses TomTom:AddWaypoint (WaypointUI shims this) or the retail map pin API.
    C_Timer.After(1.0, function()
        for _, id in ipairs(matches) do
            local note = BNB.GetNote(id)
            local wp   = note and note.waypoint
            if wp and wp.x and wp.y and wp.mapID then
                local wpTitle = (wp.title and wp.title ~= "") and wp.title
                           or  (note.title and note.title ~= "") and note.title
                           or  "BigNoteBox"
                if TomTom and TomTom.AddWaypoint then
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

    -- Notify TaskManager so per-task situations are evaluated in the same pass.
    if BNB.Task and BNB.Task.OnContextChanged then
        BNB.Task.OnContextChanged()
    end
end

-- Expose the context matching function so TaskManager can evaluate per-task
-- situations using the same logic as note contexts.
-- ctx is a context string e.g. "zone:stormwind city", "player:Arthas".
BNB._taskContextMatch = function(ctx)
    if not ctx or ctx == "" then return false end
    local kind, value = ctx:match("^(%w+):(.+)$")
    if not kind or not value then return false end
    value = value:lower()
    if kind == "zone" or kind == "instance" then
        local curKind, curVal = GetCurrentZone()
        return curKind == kind and curVal:lower() == value
    elseif kind == "subzone" then
        local curSub = GetSubZoneText and GetSubZoneText() or ""
        return curSub:lower() == value
    elseif kind == "player" then
        local tgt = GetCurrentPlayer()
        if tgt then
            tgt = tgt:lower()
            local valName = value:match("^([^-]+)") or value
            if tgt == value or tgt == valName then return true end
        end
        return false
    end
    return false
end

-- ── Context string builder (used by NoteConfig Situation tab) ──────────────────
-- Returns a context string for the player's current location.
function BNB.BuildContextString(kind)
    if kind == "zone" or kind == "instance" then
        local curKind, curVal = GetCurrentZone()
        local useKind = (kind == "instance" or curKind == "instance") and "instance" or "zone"
        return useKind .. ":" .. (curVal ~= "" and curVal or "Unknown")
    elseif kind == "subzone" then
        local sub = GetSubZoneText and GetSubZoneText() or ""
        if sub ~= "" then return "subzone:" .. sub end
        return nil
    elseif kind == "player" then
        local tgt = UnitName("target")
        if tgt then return "player:" .. tgt end
        return nil
    end
    return nil
end

-- ── Decode context string for display ─────────────────────────────────────────
-- Returns kind (string), value (string) or nil, nil
function BNB.DecodeContext(ctx)
    if not ctx or ctx == "" then return nil, nil end
    local kind, value = ctx:match("^(%w+):(.+)$")
    return kind, value
end

-- BigNoteBox Init.lua — Bootstrap namespace
-- This file loads FIRST. Creates the addon namespace and version constants.

local ADDON_NAME = ...

BigNoteBox = BigNoteBox or {}
local BNB = BigNoteBox

BNB.ADDON_NAME = ADDON_NAME
BNB.ADDON_VERSION = "1.18.0"

-- Version shorthand
BNB.version = BNB.ADDON_VERSION

-- Chat line prefixed with the addon name in colour. Lives here, in the first
-- file, so every later file can print (moved from SlashCommands.lua, ARCH-06).
function BNB:Print(msg)
    print("|cff66bb6aBigNoteBox|r: " .. tostring(msg))
end

-- Full recursive copy of a value; non-tables come back as they are. The one
-- copy helper (CMP-05): Database, NoteManager and NoteHistory each had their
-- own, and NoteHistory's stopped at two levels (BUG-22).
function BNB.DeepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = BNB.DeepCopy(x) end
    return out
end

-- WoW: Forever reports a 1.x interface number (16001, client 1.60.x). It used to be
-- told apart by WOW_PROJECT_ID == WOW_PROJECT_MAINLINE as well, but build 70170
-- (2026-10-01) gave Forever its own project id (18; MAINLINE is 1), and every
-- Forever check went false (FOR-27).
-- The interface range alone is enough: Classic Era is 11xxx, the other Classic
-- clients 2xxxx-5xxxx, Retail 1xxxxx, so 16xxx-19xxx is Forever's alone. Checked at
-- runtime rather than by which TOC loaded, so it also holds when a player loads
-- the retail TOC as "out of date" on Forever.
local _, _, _, _tocVersion = GetBuildInfo()
_tocVersion = _tocVersion or 0
BNB.IsForever = _tocVersion >= 16000 and _tocVersion < 20000

-- Wowhead URL for this client (ALL-151): kind = "item" / "spell" / "quest".
-- Retail www.wowhead.com/item=1, Forever /forever/, Classic Era /classic/,
-- TBC /tbc/, MoP /mop-classic/. Forever is told by interface range, never by
-- project id (FOR-27).
local function WowheadPath()
    if BNB.IsForever then return "forever/" end
    local p = WOW_PROJECT_ID
    if p == nil or p == WOW_PROJECT_MAINLINE then return "" end
    if p == WOW_PROJECT_CLASSIC then return "classic/" end
    if WOW_PROJECT_BURNING_CRUSADE_CLASSIC and p == WOW_PROJECT_BURNING_CRUSADE_CLASSIC then return "tbc/" end
    if WOW_PROJECT_WRATH_CLASSIC and p == WOW_PROJECT_WRATH_CLASSIC then return "wotlk/" end
    if WOW_PROJECT_CATACLYSM_CLASSIC and p == WOW_PROJECT_CATACLYSM_CLASSIC then return "cata/" end
    if WOW_PROJECT_MISTS_CLASSIC and p == WOW_PROJECT_MISTS_CLASSIC then return "mop-classic/" end
    return ""
end
function BNB.WowheadURL(kind, id)
    if not kind or not id then return nil end
    return "https://www.wowhead.com/" .. WowheadPath() .. kind .. "=" .. id
end

-- Action bar icon path relative to Assets\ ("Actionbar\\ab-lock"). On Forever, icons
-- that have an ab-forever-<name> variant use it; the rest keep the shared art.
local FOREVER_AB = { copy = true, delete = true, lock = true, refbox = true,
                     send = true, tasks = true, unlock = true, duplicate = true,
                     stickynote = true }
function BNB.AbIcon(name)
    if BNB.IsForever and FOREVER_AB[name] then return "Actionbar\\ab-forever-" .. name end
    return "Actionbar\\ab-" .. name
end

-- A unit's name and realm, for note titles and player keys (FOR-23). Forever
-- characters have a surname, and UnitName hands it back in the realm slot for
-- other players ("Mango", "Thellama") but joined for yourself ("Dakdak Lo", nil).
-- Forever is one realm with shards, so the second value there is never a realm.
-- Joined here rather than through GetUnitName so the key does not depend on the
-- surname display setting (C_PlayerInfo.ShouldDisplaySurname).
-- Returns nil when the unit does not exist; realm is never nil otherwise.
function BNB.UnitNameRealm(unit)
    local name, second = UnitName(unit)
    if not name then return nil end
    local ownRealm = GetNormalizedRealmName and GetNormalizedRealmName() or ""
    if BNB.IsForever then
        if second and second ~= "" then name = name .. " " .. second end
        return name, ownRealm
    end
    return name, (second and second ~= "") and second or ownRealm
end

-- Server time display (ALL-103). Timestamps are always saved as time(); with
-- BigNoteBoxDB.useServerTime on, shown times are shifted by the gap between the
-- server clock (GetGameTime, hour and minute only) and the local clock. The gap
-- is wrapped to -12h..+12h and rounded to 15 minutes, so clock drift and the
-- minute GetGameTime lags behind do not show up as an offset.
-- ServerClockOffset is the gap itself, whatever the setting (In-game alarms,
-- ALL-104); ServerTimeOffset is 0 unless the player chose server time.
function BNB.ServerClockOffset()
    if not GetGameTime then return 0 end
    local h, m = GetGameTime()
    if not h then return 0 end
    local lt  = date("*t")
    local off = ((h * 60 + m) - (lt.hour * 60 + lt.min)) * 60
    if off > 43200 then off = off - 86400 elseif off <= -43200 then off = off + 86400 end
    return math.floor(off / 900 + 0.5) * 900
end
function BNB.ServerTimeOffset()
    local db = BigNoteBoxDB
    if not (db and db.useServerTime) then return 0 end
    return BNB.ServerClockOffset()
end

-- date() for anything shown to the player: same arguments, server time when set.
-- BNB.Time is its inverse for a date table the player entered (alarm picker):
-- the table is read as server time when set, and the result is a real time().
function BNB.Date(fmt, ts)
    return date(fmt, (ts or time()) + BNB.ServerTimeOffset())
end
function BNB.Time(t)
    return time(t) - BNB.ServerTimeOffset()
end

-- One pending call per key (SUG-03, PERF-04): a later Debounce for the same key
-- moves the deadline instead of cancelling and making a new C_Timer, so a call
-- per keystroke allocates nothing. Pass a function built once, not a new closure
-- per call. Driven by a frame with no parent, so it keeps running while
-- UIParent is hidden (Focus mode, Alt+Z). Errors go to the error handler.
local _debounce, _due = {}, {}
local _debounceDriver = CreateFrame("Frame")
_debounceDriver:Hide()
_debounceDriver:SetScript("OnUpdate", function(self)
    -- Collect first, run after: a call may Debounce a new key, and adding a
    -- key to a table during pairs() is not allowed
    local now, n = GetTime(), 0
    for _, d in pairs(_debounce) do
        if d.at and now >= d.at then
            n = n + 1
            _due[n] = d.fn
            d.at, d.fn = nil, nil
        end
    end
    for i = 1, n do
        local fn = _due[i]
        _due[i] = nil
        xpcall(fn, geterrorhandler())
    end
    for _, d in pairs(_debounce) do if d.at then return end end
    self:Hide()
end)
function BNB.Debounce(key, delay, fn)
    local d = _debounce[key]
    if not d then d = {}; _debounce[key] = d end
    d.at, d.fn = GetTime() + (delay or 0), fn
    _debounceDriver:Show()
end
function BNB.CancelDebounce(key)
    local d = _debounce[key]
    if d then d.at, d.fn = nil, nil end
end
function BNB.DebouncePending(key)
    local d = _debounce[key]
    return d ~= nil and d.at ~= nil
end

-- Forced display language (ALL-14). BigNoteBoxLocale is its own SavedVariable so it is
-- already loaded here, before the Locales/ files run. nil/"" /"client" = follow the WoW
-- client locale; any other value is a forced locale code (e.g. "zhCN").
BNB._forcedLocale = (BigNoteBoxLocale and BigNoteBoxLocale ~= "" and BigNoteBoxLocale ~= "client")
    and BigNoteBoxLocale or nil
function BNB.GetActiveLanguage()
    return BNB._forcedLocale or GetLocale()
end

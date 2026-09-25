-- BigNoteBox Init.lua — Bootstrap namespace
-- This file loads FIRST. Creates the addon namespace and version constants.

local ADDON_NAME = ...

BigNoteBox = BigNoteBox or {}
local BNB = BigNoteBox

BNB.ADDON_NAME = ADDON_NAME
BNB.ADDON_VERSION = "1.11.1"

-- Version shorthand
BNB.version = BNB.ADDON_VERSION

-- WoW: Forever runs the Mainline client (WOW_PROJECT_MAINLINE) but reports a 1.x
-- interface number (16001), so both checks are needed to tell it apart from Retail
-- and from Classic Era. Checked at runtime rather than by which TOC loaded, so it
-- also holds when a player loads the retail TOC as "out of date" on Forever.
local _, _, _, _tocVersion = GetBuildInfo()
BNB.IsForever = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE) and (_tocVersion or 0) < 100000

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

-- Forced display language (ALL-14). BigNoteBoxLocale is its own SavedVariable so it is
-- already loaded here, before the Locales/ files run. nil/"" /"client" = follow the WoW
-- client locale; any other value is a forced locale code (e.g. "zhCN").
BNB._forcedLocale = (BigNoteBoxLocale and BigNoteBoxLocale ~= "" and BigNoteBoxLocale ~= "client")
    and BigNoteBoxLocale or nil
function BNB.GetActiveLanguage()
    return BNB._forcedLocale or GetLocale()
end

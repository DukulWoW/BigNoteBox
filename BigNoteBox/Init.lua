-- BigNoteBox Init.lua — Bootstrap namespace
-- This file loads FIRST. Creates the addon namespace and version constants.

local ADDON_NAME, BNB_NS = ...

BigNoteBox = BigNoteBox or {}
local BNB = BigNoteBox

BNB.ADDON_NAME = ADDON_NAME
BNB.ADDON_VERSION = "1.8.1"
BNB.NS = BNB_NS  -- private namespace for internal module communication

-- Version shorthand
BNB.version = BNB.ADDON_VERSION

-- WoW: Forever runs the Mainline client (WOW_PROJECT_MAINLINE) but reports a 1.x
-- interface number (16001), so both checks are needed to tell it apart from Retail
-- and from Classic Era. Checked at runtime rather than by which TOC loaded, so it
-- also holds when a player loads the retail TOC as "out of date" on Forever.
local _, _, _, _tocVersion = GetBuildInfo()
BNB.IsForever = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE) and (_tocVersion or 0) < 100000

-- Forced display language (ALL-14). BigNoteBoxLocale is its own SavedVariable so it is
-- already loaded here, before the Locales/ files run. nil/"" /"client" = follow the WoW
-- client locale; any other value is a forced locale code (e.g. "zhCN").
BNB._forcedLocale = (BigNoteBoxLocale and BigNoteBoxLocale ~= "" and BigNoteBoxLocale ~= "client")
    and BigNoteBoxLocale or nil
function BNB.GetActiveLanguage()
    return BNB._forcedLocale or GetLocale()
end

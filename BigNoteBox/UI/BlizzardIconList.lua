-- BigNoteBox UI/BlizzardIconList.lua
--
-- Loader for the Blizzard icon name list (~32k names) used by the icon
-- picker (UI/IconPicker.lua, "All game icons"). The list itself lives in the load-on-demand
-- addon BigNoteBox_Icons (ALL-62), so WoW never reads its 1.2 MB at login:
-- it is loaded once, at PLAYER_LOGIN or when the setting is switched on, and
-- only while db.blizzardIconComplete is true.
--
-- BNB.BlizzardIconList is the list, or nil. Every reader already treats nil as
-- "feature off", so a missing, disabled or broken BigNoteBox_Icons folder only
-- turns the full game list off: no Lua error, no popup, nothing at login. A chat
-- line explains it only when the player switches the setting on.
-- The saved setting is never rewritten, so fixing the folder later just works.

local BNB = BigNoteBox
local L   = BNB.L

local ICON_ADDON = "BigNoteBox_Icons"

local _list      = nil     -- the names, once BigNoteBox_Icons has handed them over
local _tried     = false   -- LoadAddOn is attempted once per session
local _failure   = nil     -- why it could not load ("MISSING", "DISABLED", ...)

-- Called by BigNoteBox_Icons/IconList.lua when it runs. Kept for the whole
-- session, so switching the setting off and on again needs no reload.
function BNB.ReceiveIconList(list)
    if type(list) == "table" then _list = list end
end

-- Loads BigNoteBox_Icons once. Returns true when the list is available.
local function EnsureLoaded()
    if _list then return true end
    if _tried then return false end
    _tried = true
    local ok, loaded, reason = pcall(C_AddOns.LoadAddOn, ICON_ADDON)
    if not ok then
        _failure = "ERROR"          -- the addon raised an error while loading
    elseif not loaded then
        _failure = reason or "MISSING"
    elseif not _list then
        _failure = "ERROR"          -- loaded, but never handed the list over
    end
    return _list ~= nil
end

-- Publishes (or clears) BNB.BlizzardIconList from the setting. announce = true
-- when the player just switched the setting on: say why it cannot work.
-- Returns true when the autocomplete has its list.
function BNB.InitBlizzardIconList(announce)
    local db = BigNoteBoxDB
    if not (db and db.blizzardIconComplete) then
        BNB.BlizzardIconList = nil
        return false
    end
    if EnsureLoaded() then
        BNB.BlizzardIconList = _list
        return true
    end
    BNB.BlizzardIconList = nil
    if announce then
        if _failure == "MISSING" then
            BNB:Print(L["ICONLIST_MISSING"])
        elseif _failure == "DISABLED" then
            BNB:Print(L["ICONLIST_DISABLED"])
        else
            BNB:Print(string.format(L["ICONLIST_FAILED_FMT"], tostring(_failure)))
        end
    end
    return false
end

-- Shown when the setting is switched off, from Settings > Modules or the icon
-- picker's "All game icons" box. Defined here at load, not with the Settings
-- window's popups: the picker can switch it off before Settings was ever built
StaticPopupDialogs["BNB_BLZICON_AC_DISABLE"] = {
    text = L["CFG_BLZICON_DISABLED_MSG"],
    button1 = L["CFG_RELOAD_NOW_BTN"],
    button2 = L["CFG_LATER_BTN"],
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    OnAccept = function() C_UI.Reload() end,
}

-- Login: load quietly if the setting is on (still behind the loading screen)
BNB.RegisterEvent("PLAYER_LOGIN", function()
    BNB.InitBlizzardIconList(false)
end)

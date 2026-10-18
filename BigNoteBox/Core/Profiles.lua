-- BigNoteBox Core/Profiles.lua - settings profiles (ALL-496)
--
-- A profile is the addon's settings and window layout. Notes, templates,
-- tokens and tag colours (the notes DB) are shared by every profile, as are
-- the keys in SHARED below.
--
-- The profile in use lives in BigNoteBoxDB itself, flat as before, so no
-- settings read changed. The others are stored copies:
--   BigNoteBoxDB.profiles       { [name] = { <profile keys>, dbVersion } }:
--                               every profile but the one in use
--   BigNoteBoxDB.profileActive  the name of the one in use (nil = Default)
--   BigNoteBoxDB.profileChars   { [charKey] = name } (nil = Default)
--   BigNoteBoxDB.profileDrop    the one in use was deleted: dropped at the next load
--   BigNoteBoxDB.profileReset   the one in use goes back to defaults at the next load
--
-- A switch only ever happens at load (P.OnLoad, from BNB.InitializeDB): the
-- choice is saved, the UI reloads, and the load stores the live values under
-- their name and moves this character's profile in. So whatever is written
-- at logout (window positions) lands in the profile it belongs to. Cloning
-- needs no reload: the live values stay, only their name changes.
--
-- Every key not in SHARED is a profile key, so a new setting needs nothing here.

local BNB = BigNoteBox
local L   = BNB.L

local P = {}
BNB.Profiles = P

P.DEFAULT = "Default"   -- stored name; shown as L["PROFILE_DEFAULT"]
P.MAX_NAME = 32

local CODE_PREFIX = "BNBP1:"   -- profile codes (Export / Import)

-- Outside every profile: data about the account, characters and notes, the
-- profile bookkeeping, and transient flags (Dukul, 2026-10-18: characters,
-- What's New seen, schema version, minimap button and sticky positions are
-- shared). Keys starting with "debug" are shared too (dev tools).
local SHARED = {
    dbVersion = true, profiles = true, profileActive = true, profileChars = true,
    profileDrop = true, profileReset = true,
    knownChars = true, lastSeenWhatsNewVersion = true, minimapIcon = true,
    postits = true, stickiesHidden = true, taskSplitRatio = true, mpePins = true,
    selectedNoteID = true, welcomeToastPending = true, migrationDone = true,
    tagColors = true, foreverNoticeHidden = true, historyAddonNotice = true,
    setupPage = true, setupUsage = true,
    devBgLab = true, devIconLab = true, devSearch = true,
}

local function IsProfileKey(k)
    return type(k) == "string" and not SHARED[k] and not k:find("^debug")
end
P.IsProfileKey = IsProfileKey

local function DB() return BigNoteBoxDB end
local function Kit() return BNB._SettingsKit end

function P.Active()
    local db = DB()
    return db and db.profileActive or P.DEFAULT
end

function P.DisplayName(name)
    if name == P.DEFAULT then return L["PROFILE_DEFAULT"] end
    return name
end

-- Default first, then by name
function P.List()
    local db, seen, list = DB(), {}, {}
    local function Add(n) if n and not seen[n] then seen[n] = true; list[#list + 1] = n end end
    Add(P.Active())
    for n in pairs(db and db.profiles or {}) do Add(n) end
    Add(P.DEFAULT)
    table.sort(list, function(a, b)
        if a == P.DEFAULT then return b ~= P.DEFAULT end
        if b == P.DEFAULT then return false end
        return a:lower() < b:lower()
    end)
    return list
end

function P.Exists(name)
    local db = DB()
    if not (db and name) then return false end
    if name == P.Active() and not db.profileDrop then return true end
    return type(db.profiles) == "table" and db.profiles[name] ~= nil
end

-- name cut to at most max bytes, never in the middle of a UTF-8 character
-- (a broken byte blanks a WoW edit box)
local function CutName(name, max)
    if #name <= max then return name end
    name = name:sub(1, max)
    local lead = name:find("[\192-\255][\128-\191]*$")
    if lead then
        local b = name:byte(lead)
        local need = (b >= 240 and 4) or (b >= 224 and 3) or 2
        if #name - lead + 1 < need then name = name:sub(1, lead - 1) end
    end
    return name
end

-- A name the player typed: trimmed, or nil + the reason. Case does not make
-- a name new, and neither does the shown name of Default.
function P.CheckName(name, except)
    name = (name or ""):match("^%s*(.-)%s*$")
    if name == "" then return nil, L["PROFILE_ERR_EMPTY"] end
    name = CutName(name, P.MAX_NAME)
    local low = name:lower()
    if low == P.DEFAULT:lower() or low == L["PROFILE_DEFAULT"]:lower() then
        return nil, string.format(L["PROFILE_ERR_TAKEN"], name)
    end
    for _, n in ipairs(P.List()) do
        if n ~= except and n:lower() == low then
            return nil, string.format(L["PROFILE_ERR_TAKEN"], n)
        end
    end
    return name
end

-- A free name based on name: "Bank", "Bank (1)", "Bank (2)", ... Default
-- becomes "Default (1)" in the player's language (Dukul, 2026-10-18). used =
-- lower-case names already handed out but not added yet (the import picker).
function P.FreeName(name, used)
    name = (name or ""):match("^%s*(.-)%s*$")
    if name == "" then name = L["PROFILE_IMPORTED_NAME"] end
    if name == P.DEFAULT then name = L["PROFILE_DEFAULT"] end
    local function Free(n)
        return P.CheckName(n) ~= nil and not (used and used[n:lower()])
    end
    local whole = CutName(name, P.MAX_NAME)
    if Free(whole) then return whole end
    name = CutName(name, P.MAX_NAME - 5)
    for i = 1, 99 do
        local n = name .. " (" .. i .. ")"
        if Free(n) then return n end
    end
    return whole
end

-- This character's key, as BNB.currentChar builds it (Core/Initialize.lua).
-- At ADDON_LOADED the realm can still be nil: GetRealmName without spaces
-- and dashes is the same normalised name.
local _charKey
local function CharKey()
    if _charKey then return _charKey end
    if BNB.currentChar then return BNB.currentChar end
    local name, realm = BNB.UnitNameRealm("player")
    if not name or name == "" then return nil end
    if not realm or realm == "" then
        local r = GetRealmName and GetRealmName()
        realm = r and r:gsub("[%s%-]", "") or ""
    end
    if realm == "" then return nil end
    return name .. "-" .. realm
end
P.CharKey = CharKey

-- The profile keys of the live table: moved out (refs), or copied
local function Snapshot(copy)
    local db, t = DB(), {}
    for k, v in pairs(db) do
        if IsProfileKey(k) then t[k] = copy and BNB.DeepCopy(v) or v end
    end
    t.dbVersion = db.dbVersion
    return t
end

local function ClearLive()
    local db, keys = DB(), {}
    for k in pairs(db) do
        if IsProfileKey(k) then keys[#keys + 1] = k end
    end
    for _, k in ipairs(keys) do db[k] = nil end
end

-- Store the live profile under its name (unless discard) and move name in
local function Swap(name, discard)
    local db = DB()
    if not discard then db.profiles[P.Active()] = Snapshot(false) end
    local incoming = db.profiles[name]
    db.profiles[name] = nil
    ClearLive()
    if type(incoming) == "table" then
        for k, v in pairs(incoming) do
            if IsProfileKey(k) then db[k] = v end
        end
    end
    db.profileActive = (name ~= P.DEFAULT) and name or nil
end

-- Moves this character's profile in. True when the live values changed.
local function ApplyForChar()
    local db = DB()
    local want = db.profileChars[_charKey] or P.DEFAULT
    if db.profileDrop then
        db.profileDrop = nil
        Swap(want, true)
        return true
    end
    if want ~= P.Active() then
        Swap(want)
        return true
    end
    return false
end

local _pending = false

function P.OnLoad()
    local db = DB()
    if type(db.profiles) ~= "table" then db.profiles = {} end
    if type(db.profileChars) ~= "table" then db.profileChars = {} end
    -- The one in use is never stored as well: the live values win
    if not db.profileDrop then db.profiles[P.Active()] = nil end
    local bad = {}
    for n, t in pairs(db.profiles) do
        if type(n) ~= "string" or type(t) ~= "table" then bad[#bad + 1] = n end
    end
    for _, n in ipairs(bad) do db.profiles[n] = nil end
    -- Every stored profile runs the settings migrations (its own dbVersion)
    for _, t in pairs(db.profiles) do Kit().Migrate(t) end
    -- Default always exists
    if P.Active() ~= P.DEFAULT and not db.profiles[P.DEFAULT] then
        db.profiles[P.DEFAULT] = { dbVersion = db.dbVersion }
    end
    -- A character's choice names a profile that exists, and never Default
    local drop = {}
    for key, n in pairs(db.profileChars) do
        if n == P.DEFAULT or not P.Exists(n) then drop[#drop + 1] = key end
    end
    for _, key in ipairs(drop) do db.profileChars[key] = nil end

    local changed = false
    if db.profileReset then
        db.profileReset = nil
        ClearLive()
        changed = true
    end
    _charKey = CharKey()
    if _charKey then
        changed = ApplyForChar() or changed
    else
        _pending = true
    end
    if changed then Kit().Fill(db) end
end

-- PLAYER_LOGIN (Core/Events.lua): the character's name was not known at load
function P.OnLogin()
    if not _pending then return end
    _pending = false
    _charKey = CharKey()
    if _charKey and ApplyForChar() then Kit().Fill(DB()) end
end

--------------------------------------------------------------------------------
-- ACTIONS (Settings > Advanced, UI/Config/Profiles.lua)
--------------------------------------------------------------------------------

-- The character names that use a profile ("Name" or "Name-Realm" off this realm)
function P.CharsUsing(name)
    local db, out = DB(), {}
    local myRealm = (CharKey() or ""):match("%-([^%-]+)$")
    for key, rec in pairs(db.knownChars or {}) do
        if (db.profileChars[key] or P.DEFAULT) == name then
            local n = type(rec) == "table" and rec.name or key:match("^(.-)%-") or key
            local realm = key:match("%-([^%-]+)$")
            out[#out + 1] = (realm and realm ~= myRealm) and (n .. "-" .. realm) or n
        end
    end
    table.sort(out)
    return out
end

-- This character uses name from the next load (the caller reloads)
function P.UseOnThisChar(name)
    local db, key = DB(), CharKey()
    if not key then return end
    db.profileChars[key] = (name ~= P.DEFAULT) and name or nil
end

-- A copy of the profile in use, in use from now on: no reload, the values
-- are the same. Other characters on the old profile keep it.
function P.Clone(name)
    local db = DB()
    db.profiles[P.Active()] = Snapshot(true)
    db.profileActive = name
    local key = CharKey()
    if key then db.profileChars[key] = name end
end

-- All defaults, and the setup wizard when it is first used (setupComplete nil)
function P.CreateBlank(name)
    local db = DB()
    db.profiles[name] = { dbVersion = db.dbVersion }
end

function P.Rename(old, new)
    local db = DB()
    if old == P.DEFAULT or old == new then return end
    if old == P.Active() then
        db.profileActive = new
    else
        db.profiles[new] = db.profiles[old]
        db.profiles[old] = nil
    end
    for key, n in pairs(db.profileChars) do
        if n == old then db.profileChars[key] = new end
    end
end

-- True when the caller must reload: the one in use was deleted, this
-- character goes back to Default at the load.
function P.Delete(name)
    local db = DB()
    if name == P.DEFAULT then return false end
    for key, n in pairs(db.profileChars) do
        if n == name then db.profileChars[key] = nil end
    end
    if name == P.Active() then
        db.profileDrop = true
        return true
    end
    db.profiles[name] = nil
    return false
end

-- Danger Zone: the profile in use goes back to defaults at the next load
function P.ResetActive()
    DB().profileReset = true
end

--------------------------------------------------------------------------------
-- PROFILE CODES: LibSerialize -> Deflate -> EncodeForPrint, as share strings
--------------------------------------------------------------------------------
local function GetLibSerialize() return LibStub and LibStub("LibSerialize", true) end

-- name: a stored profile (the full backup), or nil = the one in use
function P.Export(name)
    local ls, ld = GetLibSerialize(), BNB.GetDeflate()
    if not (ls and ld) then return nil end
    local db = DB()
    local settings, ver
    if name == nil or name == P.Active() then
        name, settings, ver = P.Active(), Snapshot(true), db.dbVersion
    else
        local t = type(db.profiles) == "table" and db.profiles[name]
        if type(t) ~= "table" then return nil end
        settings, ver = BNB.DeepCopy(t), t.dbVersion or db.dbVersion
    end
    settings.dbVersion = nil
    local payload = { kind = "bnbprofile", v = 1, name = name,
                      dbVersion = ver, settings = settings }
    local ok, ser = pcall(ls.Serialize, ls, payload)
    if not ok or not ser then return nil end
    return CODE_PREFIX .. ld:EncodeForPrint(ld:CompressDeflate(ser))
end

-- payload or nil. Only profile keys come in, and a key with a default must
-- have its type (someone else's code is never trusted further than that).
function P.Decode(str)
    str = (str or ""):match("^%s*(.-)%s*$")
    if str:sub(1, #CODE_PREFIX) ~= CODE_PREFIX then return nil end
    local ls, ld = GetLibSerialize(), BNB.GetDeflate()
    if not (ls and ld) then return nil end
    local comp = ld:DecodeForPrint(str:sub(#CODE_PREFIX + 1))
    local ser = comp and ld:DecompressDeflate(comp)
    if not ser then return nil end
    local ok, payload = ls:Deserialize(ser)
    if not ok or type(payload) ~= "table" or payload.kind ~= "bnbprofile"
       or type(payload.settings) ~= "table" then return nil end
    local clean = {}
    for k, v in pairs(payload.settings) do
        local def = BNB.DEFAULTS[k]
        if IsProfileKey(k) and (def == nil or type(def) == type(v)) then clean[k] = v end
    end
    clean.dbVersion = tonumber(payload.dbVersion) or DB().dbVersion
    return { name = type(payload.name) == "string" and payload.name or nil, settings = clean }
end

function P.AddImported(name, payload)
    local t = payload.settings
    Kit().Migrate(t)
    DB().profiles[name] = t
end

--------------------------------------------------------------------------------
-- FULL JSON BACKUP (Features/NoteExport.lua, ALL-496 S2): every profile as a
-- profile code, so the JSON round trip never changes a setting
--------------------------------------------------------------------------------

-- The codes of every profile, the one in use included (not one deleted and
-- waiting for the reload)
function P.BackupList()
    local out = {}
    for _, n in ipairs(P.List()) do
        if P.Exists(n) then
            local code = P.Export(n)
            if code then out[#out + 1] = code end
        end
    end
    return out
end

-- Adds the backup's profiles. A name already used here (Default always is) is
-- never overwritten: that profile comes in under a free name, "Default (1)"
-- (Dukul, 2026-10-18; it was skipped before). names = the names the import
-- picker showed, by position in list. Returns how many were added.
function P.ImportBackup(list, names)
    if type(list) ~= "table" or not DB() then return 0 end
    local n = 0
    for i, code in ipairs(list) do
        local payload = type(code) == "string" and P.Decode(code)
        local name = payload and payload.name
            and ((type(names) == "table" and names[i] and P.CheckName(names[i]))
                 or P.FreeName(payload.name))
        name = name and P.CheckName(name)   -- never over a profile already here
        if name then
            P.AddImported(name, payload)
            n = n + 1
        end
    end
    return n
end

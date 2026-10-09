-- FakeData.lua
-- ALL-312 (Dukul, test AT2): fill the addon with fake test data, so features
-- that depend on time or on many characters can be tested without waiting
-- 90 days. Dev only, never packaged.
--
--   /bnbfake        adds the set (again: the old set is removed first)
--   /bnbfake remove removes it
--
-- Adds characters to BigNoteBoxDB.knownChars, last seen from today to 400 days
-- ago, each with a few notes of its own (scope "char:<key>") made on the day it
-- was last seen. Characters carry `_fake = true`, notes the tag FAKE_TAG, which
-- is how "remove" finds them. Runs only in dev mode: notes go into the dev
-- notes set (BigNoteBoxDevDB), never the player's real notes; knownChars is in
-- the shared settings DB, hence the marker.

local FAKE_TAG = "fake-data"
local DAY = 86400

-- name, realm, class, level, faction, guild, days since last seen
local CHARS = {
    { "Fakemage",    "Draenor",        "MAGE",        80, "Horde",    "Fake Guild",       0 },
    { "Fakepally",   "Silvermoon",     "PALADIN",     80, "Alliance", nil,                3 },
    { "Fakehunter",  "Draenor",        "HUNTER",      72, "Horde",    "Fake Guild",       12 },
    { "Fakedruid",   "Argent Dawn",    "DRUID",       60, "Alliance", "Moonglade Society", 45 },
    { "Fakewarlock", "Tarren Mill",    "WARLOCK",     80, "Horde",    nil,                89 },
    { "Fakemonk",    "Draenor",        "MONK",        35, "Horde",    "Fake Guild",       91 },
    { "Fakeshaman",  "Kazzak",         "SHAMAN",      80, "Horde",    "Totem Collectors", 100 },
    { "Fakerogue",   "Silvermoon",     "ROGUE",       10, "Alliance", nil,                180 },
    { "Fakedk",      "Ravencrest",     "DEATHKNIGHT", 80, "Alliance", "Frozen Throne",    365 },
    { "Fakeevoker",  "Draenor",        "EVOKER",      70, "Horde",    nil,                400 },
}

local NOTE_TITLES = {
    "Weekly to-do", "Gold farm route", "Transmog wishlist", "Raid notes", "Profession cooldowns",
    "Alt bank list", "Mount farm", "Rep grind", "Delve loadout", "Old quest chain",
}
local NOTE_BODIES = {
    "Check the vault, then the world boss.\nSell the greens.",
    "Route: north mine, then the herbs by the lake, then back to the auction house.",
    "Still missing: the shoulders from the second boss.",
    "Tank swaps at three stacks. Spread for the beam.",
    "Alchemy transmute is up every day. Do not forget.",
    "Bank: cloth, ore, old reagents. Clear it out one day.",
    "Kill the rare every reset, 1 percent drop.",
    "Exalted soon, buy the tabard.",
    "Bring potions and the brann setup with the healer spec.",
    "Started years ago, never finished. Third step is in the cave.",
}
local ICONS = {
    "Interface\\Icons\\INV_Misc_Note_01", "Interface\\Icons\\INV_Misc_Book_09",
    "Interface\\Icons\\INV_Misc_Coin_01", "Interface\\Icons\\Achievement_Boss_Ragnaros",
    "Interface\\Icons\\INV_Misc_Bag_10",  "Interface\\Icons\\Ability_Mount_Drake_Proto",
}

local function B() return BigNoteBox end

local function Remove(quiet)
    local BNB = B()
    local db = BigNoteBoxDB
    local chars = 0
    if db and db.knownChars then
        for key, rec in pairs(db.knownChars) do
            if type(rec) == "table" and rec._fake then db.knownChars[key] = nil; chars = chars + 1 end
        end
    end
    local ids = {}
    for id, n in pairs(BNB.NotesDB().notes or {}) do
        for _, t in ipairs(n.tags or {}) do
            if t == FAKE_TAG then ids[#ids + 1] = id; break end
        end
    end
    if #ids > 0 then BNB.DeleteNotes(ids, true) end
    if BNB.Sidebar and BNB.Sidebar.Refresh then pcall(BNB.Sidebar.Refresh) end
    if not quiet then
        BNB:Print(string.format("|cff88bbffFake data removed:|r %d characters, %d notes.", chars, #ids))
    end
end

local function Add()
    local BNB = B()
    local db = BigNoteBoxDB
    if not (db and db.knownChars) then return end
    Remove(true)
    local now, made = time(), 0
    for i, c in ipairs(CHARS) do
        local name, realm, cls, level, faction, guild, days = unpack(c, 1, 7)
        local key = name .. "-" .. realm
        local seen = now - days * DAY
        db.knownChars[key] = {
            name = name, realm = realm, class = cls, level = level,
            faction = faction, guild = guild, lastSeen = seen,
            slotHidden = false, slotPinned = false, _fake = true,
        }
        -- One to three notes each, made on the day it was last seen
        for j = 1, (i % 3) + 1 do
            local k = (i + j * 3) % #NOTE_TITLES + 1
            local id = BNB.CreateNote(NOTE_TITLES[k] .. " (" .. name .. ")", NOTE_BODIES[k])
            if id then
                local tags = { FAKE_TAG, string.lower(cls) }
                if days >= 90 then tags[#tags + 1] = "old" end
                BNB.UpdateNote(id, {
                    scope = "char:" .. key, tags = tags,
                    icon = ICONS[(i + j) % #ICONS + 1], iconSource = "curated",
                    pinned = (j == 1 and i % 4 == 0) or nil,
                    favorited = (i % 3 == 0) or nil,
                })
                local n = BNB.GetNote(id)
                if n then n.created = seen - j * 3600; n.updated = seen - j * 600 end
                made = made + 1
            end
        end
    end
    if BNB.Sidebar and BNB.Sidebar.Refresh then pcall(BNB.Sidebar.Refresh) end
    BNB:Print(string.format("|cff88bbffFake data added:|r %d characters (last seen 0 to 400 days ago), %d notes, tag \"%s\". /bnbfake remove takes it out.",
        #CHARS, made, FAKE_TAG))
end

SLASH_BNBFAKEDATA1 = "/bnbfake"
SlashCmdList.BNBFAKEDATA = function(msg)
    local BNB = B()
    if not (BNB and BNB.CreateNote) then return end
    if not (BNB.IsDevMode and BNB.IsDevMode()) then
        BNB:Print("|cffff9900Fake data works in dev mode only (it writes notes).|r")
        return
    end
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "remove" then Remove() else Add() end
end

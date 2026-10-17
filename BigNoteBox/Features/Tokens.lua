-- BigNoteBox Features/Tokens.lua
-- Note tokens (ALL-481): {{name}} in a note's text, filled from the game.
--
-- Two kinds:
--   Snapshot = filled once, when typed (the closing }} expands it, one undo
--              step brings the token back) or when a note is made from a
--              template (ALL-68). After that it is plain text:
--              {{date}} {{time}} {{zone}} {{subzone}} {{instance}} {{target}} {{coords}}
--   Live     = stay in the text and are filled each time the note is drawn,
--              from the READER's game (a shared "Hey, {{me}}!" greets whoever
--              reads it): {{me}} {{name}} {{realm}} {{class}} {{race}} {{level}}
--              {{faction}} {{spec}} {{ilvl}} {{guild}} {{guildrank}} {{here}}
--   Id       = live tokens that take a game id (S2): {{item:6948}} {{quest:id}}
--              {{achievement:id}} {{currency:id}} {{rep:factionID}} {{spell:id}}
--              {{mount:id}} (journal id, or the mount's spell / item id)
--              {{pet:speciesID}}. Icon + game link + the reader's state (done
--              tick / red cross, amount, standing), Dukul 2026-10-17. A wrong id
--              or data this client lacks shows as typed; an item / quest / spell
--              still loading shows as typed until it arrives, then the open
--              views redraw (message TokensChanged).
--   Custom   = the player's own (S4): a name and a line of text that may use
--              built-in tokens and other custom ones (3 deep at most, so a
--              loop stops). Live: filled on every draw from the READER's own
--              definitions; a reader without it sees it as typed. Kept with
--              the notes (BigNoteBoxNotesDB.tokens), in the JSON backup.
--   Time, money, lockouts (S3): {{gold}} (coins), {{reset:weekly}} /
--              {{reset:daily}} (countdown, 2d 4h), {{lockout:name}} (the
--              reader's progress per difficulty; any part of the name, any
--              case, or the instance id) and {{lockouts}} (every lockout).
--
-- Redraw (S3): a live value that changes while a note stays open (level,
-- {{here}}, gold, a quest turned in, a countdown) sends TokensChanged on its
-- game event, debounced, and only when that token was drawn since the last
-- redraw (the views fill again, which marks it again). Countdowns are checked
-- every few seconds and redraw when their text changes.
--
-- Rules (Dukul, 2026-10-17):
--   * An unknown token, or a snapshot token left in the text, shows as typed.
--   * \{{me}} shows {{me}} as text (the backslash is dropped on display).
--   * A live token with no value right now (no guild) shows nothing.
--   * The plain editor shows tokens raw: the text being edited is what was typed.
--   * Tokens are data only. Never Lua from a note, share string or definition:
--     a shared note would run someone else's code.
--   * Names are case-insensitive. An id is digits only ({{item: 6948 }} is
--     fine, {{item:abc}} stays as typed).
--
-- Every place that shows note text to the player fills it with T.Fill: the
-- rich converter (AM.ToHTML), plain sticky read view, tl;dr (BNB.NoteTldr),
-- situation toast summary, note link preview, Send to Chat. Text that goes
-- into an edit box or to chat is filled "plain": no pictures (|T is never put
-- in edit box text, chat drops it), ticks as words, no home-made links (the
-- server drops a chat line with a link it did not make).
--
-- Public API:
--   BNB.Tokens.Fill(text, mode)         -- live tokens filled, for display;
--                                          mode "plain" = edit boxes, chat
--   BNB.Tokens.Snapshot(text, blank)    -- snapshot tokens filled (templates)
--   BNB.Tokens.HasSnapshot(text)        -- a snapshot token still in the text
--   BNB.Tokens.WireExpand(eb, undoID)   -- expand snapshot tokens as typed
--   BNB.Tokens.MENU / Preview(name, kind) -- the toolbar's token list (S2)
--   BNB.Tokens.Custom()                  -- the player's tokens, by name (S4):
--                                           { { key, name, text }, ... }
--   BNB.Tokens.GetCustom(name)           -- one record or nil
--   BNB.Tokens.SetCustom(name, text, oldName) -> true, or nil + error text
--   BNB.Tokens.DeleteCustom(name)
--   BNB.Tokens.CustomPreview(text)       -- what a definition gives right now
--   BNB.Tokens.BackupList() / ImportRecords(list) -- the JSON full backup
--   BNB.Tokens.WireAutocomplete(eb, undoID) -- the {{ list as typed (S4)
--   BNB.Tokens.TrackCaret(eb)            -- again after a SetScript of
--                                           OnCursorChanged (sticky edit)

local BNB = BigNoteBox
if not BNB then return end
local L = BNB.L

local T = {}
BNB.Tokens = T

-- A value as plain text: one line, no "|" (escape codes, and chat drops them),
-- no braces (so it can never make markup or another token)
local function Clean(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return "?" end   -- Midnight, in combat
    -- Only text and numbers: Forever's pet journal handed a function back
    -- where the name goes ("function: 0000...", 2026-10-17)
    local k = type(v)
    if k ~= "string" and k ~= "number" then return nil end
    return (tostring(v):gsub("[\r\n]+", " "):gsub("[|{}]", ""))
end

local function PlayerName()
    return (BNB.UnitNameRealm("player"))
end

-- ---------------------------------------------------------------------------
-- SNAPSHOT TOKENS: filled once
-- ---------------------------------------------------------------------------
local SNAPSHOT = {
    date = function() return BNB.FmtDate(time()) end,
    time = function() return BNB.FmtClock(time()) end,
    zone = function() return GetRealZoneText() end,
    subzone = function() return GetSubZoneText() end,
    -- nil outside an instance: the token stays as typed
    instance = function()
        local name, kind = GetInstanceInfo()
        if kind and kind ~= "none" then return name end
    end,
    -- The name only (Forever: with the surname), no realm: a title reads
    -- "Queen Ansurek", not "Queen Ansurek-Realm"
    target = function()
        if UnitExists("target") then return (BNB.UnitNameRealm("target")) end
    end,
    -- The waypoint link the toolbar's Waypoint link makes, "Zone (42.3 61.0)"
    -- (Features/NoteLinks.lua; Dukul, 2026-10-17). A table = our own link,
    -- kept as it is (Clean would take its "|" out). No position (an
    -- instance): the "/way Zone" line as before
    coords = function()
        local mapID, x, y
        pcall(function()
            mapID = C_Map.GetBestMapForUnit("player")
            local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
            if pos then x, y = pos:GetXY() end
        end)
        if BNB.NoteLinks and mapID and x and y and not (x == 0 and y == 0) then
            return { raw = BNB.NoteLinks.WayLink({ mapID = mapID,
                x = math.floor(x * 1000 + 0.5) / 10, y = math.floor(y * 1000 + 0.5) / 10 }) }
        end
        return BNB.PlayerWayString and BNB.PlayerWayString()
    end,
}

-- ---------------------------------------------------------------------------
-- LIVE TOKENS: filled on every draw, from the reader's game
-- ---------------------------------------------------------------------------
local LIVE = {
    me    = PlayerName,
    -- With the realm, as in a /who or whisper (Forever is one realm: name only)
    name  = function()
        local n, r = BNB.UnitNameRealm("player")
        if BNB.IsForever or not r or r == "" then return n end
        return n .. "-" .. r
    end,
    realm = function() return GetRealmName() end,
    class = function() return (UnitClass("player")) end,
    race  = function() return (UnitRace("player")) end,
    level = function() return UnitLevel("player") end,
    faction = function() return select(2, UnitFactionGroup("player")) end,
    -- Classic Era has no specs: nil = nothing shown
    spec  = function()
        local i = GetSpecialization and GetSpecialization()
        if not i or i == 0 then return nil end
        return select(2, GetSpecializationInfo(i))
    end,
    ilvl  = function()
        local _, equipped = GetAverageItemLevel()
        if equipped and equipped > 0 then return math.floor(equipped) end
    end,
    guild     = function() return (GetGuildInfo("player")) end,
    guildrank = function() return select(2, GetGuildInfo("player")) end,
    -- Where the reader is now ({{zone}} is where the note was written)
    here  = function() return GetRealZoneText() end,
    -- gold, lockouts: S3, further down (they need the id tokens' helpers)
}

-- ---------------------------------------------------------------------------
-- ID TOKENS: {{kind:id}}, live, built from game data (S2)
-- ---------------------------------------------------------------------------
-- Each returns the finished text, or nil = show the token as typed. Names go
-- through Clean; links come from the game as they are (braces taken out).
-- plain = no pictures, ticks as words, game-made links only (see the header).

-- Data the client loads on request: an item / quest / spell not cached yet
-- shows as typed, and the open views redraw once it arrives. An id the
-- server says does not exist is never asked for again (no redraw loop).
local LOADERS = {
    item  = function(id) C_Item.RequestLoadItemDataByID(id) end,
    quest = function(id) C_QuestLog.RequestLoadQuestByID(id) end,
    spell = function(id) C_Spell.RequestLoadSpellData(id) end,
}
local pending = { item = {}, quest = {}, spell = {} }
local failed  = {}

local function Request(kind, id)
    if failed[kind .. id] or pending[kind][id] then return nil end
    if pcall(LOADERS[kind], id) then pending[kind][id] = true end
    return nil
end

local function SendChanged() BNB.SendMessage("TokensChanged") end
local function Arrived(kind, id, ok)
    if not (id and pending[kind][id]) then return end
    pending[kind][id] = nil
    if ok == false then failed[kind .. id] = true; return end
    BNB.Debounce("tokensChanged", 0.1, SendChanged)
end
BNB.RegisterEvent("GET_ITEM_INFO_RECEIVED", function(_, id, ok) Arrived("item", id, ok) end)
BNB.RegisterEvent("SPELL_DATA_LOAD_RESULT", function(_, id, ok) Arrived("spell", id, ok) end)
-- Retail and Forever only (Classic has no quest data loading)
if C_QuestLog.RequestLoadQuestByID then
    BNB.RegisterEvent("QUEST_DATA_LOAD_RESULT", function(_, id, ok) Arrived("quest", id, ok) end)
end

local TICK  = "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t"
local CROSS = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:0|t"

-- Done tick / red cross after the link (Dukul, 2026-10-17); plain = words
local function Mark(done, plain, collect)
    if plain then
        local key = collect and (done and "TOKEN_COLLECTED" or "TOKEN_NOT_COLLECTED")
            or (done and "TOKEN_DONE" or "TOKEN_NOT_DONE")
        return " (" .. L[key] .. ")"
    end
    return " " .. (done and TICK or CROSS)
end

-- The icon in front, at the text's own height
local function Icon(tex, plain)
    local k = type(tex)
    if plain or (k ~= "number" and k ~= "string") or tex == 0 or tex == "" then return "" end
    return "|T" .. tostring(tex) .. ":0|t "
end

-- A game link as the game made it, braces out (never markup, never a token)
local function GameLink(link)
    if type(link) ~= "string" or link == "" then return nil end
    return (link:gsub("[{}\r\n]", ""))
end

-- A name in [brackets] where the game gives no link: coloured for display,
-- bare in plain text (chat drops a colour code that is not a link's)
local function Named(name, color, plain)
    name = "[" .. (Clean(name) or "?") .. "]"
    if plain or not color then return name end
    return "|c" .. color .. name .. "|r"
end

local function Amount(n) return BreakUpLargeNumbers(math.floor(n or 0)) end

-- "Revered", the reader's gender form where the language has one
local function Standing(reaction)
    if not reaction then return nil end
    return GetText("FACTION_STANDING_LABEL" .. reaction, UnitSex("player"))
end

local IDTOK = {
    item = function(id, plain)
        local _, link, _, _, _, _, _, _, _, icon = C_Item.GetItemInfo(id)
        link = GameLink(link)
        if not link then return Request("item", id) end
        return Icon(icon or C_Item.GetItemIconByID(id), plain) .. link
    end,

    -- Retail / Forever load the title on request; Classic reads it from its cache
    quest = function(id, plain)
        local title
        if C_QuestLog.GetTitleForQuestID then
            title = C_QuestLog.GetTitleForQuestID(id)
            if not title or title == "" then return Request("quest", id) end
        elseif C_QuestLog.GetQuestInfo then
            title = C_QuestLog.GetQuestInfo(id)
        end
        if not title or title == "" then return nil end
        -- GetQuestLink takes a quest id on Retail / Forever, a log index on Classic
        local link = not BNB.IsClassic and GetQuestLink and GameLink(GetQuestLink(id))
        if not link then
            link = plain and Named(title) or string.format("|cffffff00|Hquest:%d:-1|h%s|h|r", id, Named(title))
        end
        return link .. Mark(C_QuestLog.IsQuestFlaggedCompleted(id), plain)
    end,

    achievement = function(id, plain)
        local _, name, _, completed, _, _, _, _, _, icon = GetAchievementInfo(id)
        if not name or name == "" then return nil end
        local link = GameLink(GetAchievementLink(id)) or Named(name, "ffffff00", plain)
        return Icon(icon, plain) .. link .. Mark(completed, plain)
    end,

    -- How much the reader has, "/ max" when the currency has a cap
    currency = function(id, plain)
        local info = C_CurrencyInfo.GetCurrencyInfo(id)
        if not (info and info.name and info.name ~= "") then return nil end
        local CL = C_CurrencyInfo.GetCurrencyLink   -- Retail / Forever only
        local link = CL and GameLink(CL(id, info.quantity or 0)) or Named(info.name, "ffffffff", plain)
        local amt = Amount(info.quantity)
        if (info.maxQuantity or 0) > 0 then amt = amt .. " / " .. Amount(info.maxQuantity) end
        return Icon(info.iconFileID, plain) .. link .. " " .. amt
    end,

    -- "Name: Revered 1,234 / 21,000", "Name: Renown 18"; the numbers are left
    -- out at the top of the bar (Exalted, a maxed friendship)
    rep = function(id)
        local name, label, cur, max
        if C_Reputation and C_Reputation.GetFactionDataByID then   -- Retail / Forever
            local d = C_Reputation.GetFactionDataByID(id)
            if not (d and d.name and d.name ~= "") then return nil end
            name = d.name
            if C_Reputation.IsMajorFaction and C_Reputation.IsMajorFaction(id) and C_MajorFactions then
                local m = C_MajorFactions.GetMajorFactionData(id)
                if m and m.renownLevel then
                    return Clean(name) .. ": " .. string.format(L["TOKEN_RENOWN"], m.renownLevel)
                end
            end
            local fr = C_GossipInfo and C_GossipInfo.GetFriendshipReputation
                and C_GossipInfo.GetFriendshipReputation(id)
            if fr and (fr.friendshipFactionID or 0) > 0 then
                label = fr.reaction
                if fr.nextThreshold and fr.reactionThreshold then
                    cur, max = fr.standing - fr.reactionThreshold, fr.nextThreshold - fr.reactionThreshold
                end
            else
                label = Standing(d.reaction)
                if d.currentStanding and d.currentReactionThreshold and d.nextReactionThreshold then
                    cur = d.currentStanding - d.currentReactionThreshold
                    max = d.nextReactionThreshold - d.currentReactionThreshold
                end
            end
        elseif GetFactionInfoByID then                              -- Classic
            local n, _, standingID, barMin, barMax, barValue = GetFactionInfoByID(id)
            if not n or n == "" then return nil end
            name, label = n, Standing(standingID)
            if barMin and barMax and barValue then cur, max = barValue - barMin, barMax - barMin end
        else
            return nil
        end
        local s = Clean(name) .. ": " .. (Clean(label) or "?")
        if cur and max and max > 0 and cur < max then
            s = s .. " " .. Amount(cur) .. " / " .. Amount(max)
        end
        return s
    end,

    spell = function(id, plain)
        local info = C_Spell.GetSpellInfo(id)
        if not (info and info.name and info.name ~= "") then
            if C_Spell.IsSpellDataCached and not C_Spell.IsSpellDataCached(id) then
                return Request("spell", id)
            end
            return nil
        end
        local link = GameLink(C_Spell.GetSpellLink(id)) or Named(info.name, "ff71d5ff", plain)
        return Icon(info.iconID, plain) .. link
    end,

    -- The journal's mount id; a mount's spell or item id finds it too
    mount = function(id, plain)
        local MJ = C_MountJournal
        if not (MJ and MJ.GetMountInfoByID) then return nil end
        local name, spellID, icon, _, _, _, _, _, _, _, collected = MJ.GetMountInfoByID(id)
        if not name then
            local mid = (MJ.GetMountFromSpell and MJ.GetMountFromSpell(id))
                or (MJ.GetMountFromItem and MJ.GetMountFromItem(id))
            if mid then name, spellID, icon, _, _, _, _, _, _, _, collected = MJ.GetMountInfoByID(mid) end
        end
        if not name or name == "" then return nil end
        local link = spellID and GameLink(C_Spell.GetSpellLink(spellID)) or Named(name, "ff71d5ff", plain)
        return Icon(icon, plain) .. link .. Mark(collected, plain, true)
    end,

    -- Battle pet by species id: "1/3" owned, a red cross when none. No link:
    -- a pet link needs one owned pet's own stats
    pet = function(id, plain)
        local PJ = C_PetJournal
        if not (PJ and PJ.GetPetInfoBySpeciesID) then return nil end
        local name, icon = PJ.GetPetInfoBySpeciesID(id)
        if type(name) ~= "string" or name == "" then return nil end
        local s = Icon(icon, plain) .. Clean(name)
        local n, limit = PJ.GetNumCollectedInfo(id)
        if type(n) ~= "number" then return s end
        if n > 0 then return s .. " " .. n .. "/" .. (tonumber(limit) or n) end
        return s .. Mark(false, plain, true)
    end,
}

-- ---------------------------------------------------------------------------
-- TIME, MONEY AND LOCKOUTS (S3)
-- ---------------------------------------------------------------------------
-- Tokens drawn since the last redraw (lower-case name, or the kind of a
-- {{kind:arg}} token): game events only redraw when one of theirs is here.
local used = {}
-- The countdown text each {{reset:x}} showed last: the ticker redraws when
-- the text would read differently now
local shownReset = {}
-- When the soonest lockout the views showed runs out (time())
local lockExpire

-- 2d 4h, then 4h 12m, then 12m, then < 1m
local function Countdown(secs)
    secs = math.max(0, math.floor(secs or 0))
    local d, h, m = math.floor(secs / 86400), math.floor(secs % 86400 / 3600), math.floor(secs % 3600 / 60)
    if d > 0 then return string.format(L["TOKEN_DUR_DH"], d, h) end
    if h > 0 then return string.format(L["TOKEN_DUR_HM"], h, m) end
    if m > 0 then return string.format(L["TOKEN_DUR_M"], m) end
    return L["TOKEN_DUR_LT_M"]
end

-- From the client's own reset clock (the region's day and hour), as the
-- task resets and reset alarms do
local RESET_FN = { weekly = "GetSecondsUntilWeeklyReset", daily = "GetSecondsUntilDailyReset" }
local function ResetText(kind)
    local fn = RESET_FN[kind] and C_DateAndTime and C_DateAndTime[RESET_FN[kind]]
    local secs = fn and fn()
    if type(secs) ~= "number" then return nil end
    return Countdown(secs)
end

-- 12,345 (g) 67 (s) 89 (c) with the game's coin pictures; plain 12,345g 67s 89c.
-- A part that is 0 is left out, as the game's own money text does
local COIN = "|TInterface\\MoneyFrame\\UI-%sIcon:0:0:2:0|t"
local function Money(plain)
    local m = GetMoney()
    if issecretvalue and issecretvalue(m) then return "?" end
    if type(m) ~= "number" then return nil end
    local parts = {}
    local function Add(n, coin, sym)
        if plain then parts[#parts + 1] = Amount(n) .. (Clean(sym) or "")
        else parts[#parts + 1] = Amount(n) .. " " .. COIN:format(coin) end
    end
    local g, s, c = math.floor(m / 10000), math.floor(m % 10000 / 100), m % 100
    if g > 0 then Add(g, "Gold", GOLD_AMOUNT_SYMBOL or "g") end
    if s > 0 then Add(s, "Silver", SILVER_AMOUNT_SYMBOL or "s") end
    if c > 0 or #parts == 0 then Add(c, "Copper", COPPER_AMOUNT_SYMBOL or "c") end
    return { raw = table.concat(parts, " ") }
end

-- The reader's lockouts, one entry per instance name with its difficulties
-- in the game's order. The game fills the list after RequestRaidInfo: asked
-- once, and again when a shown lockout runs out or a boss dies;
-- UPDATE_INSTANCE_INFO then redraws.
local raidInfoAsked
local function AskRaidInfo() pcall(RequestRaidInfo) end
local function SavedInstances()
    if not raidInfoAsked then raidInfoAsked = true; AskRaidInfo() end
    local list, byName, now = {}, {}, time()
    for i = 1, (GetNumSavedInstances() or 0) do
        local name, _, reset, _, locked, extended, _, _, _, diffName, numEnc, progress, _, instID
            = GetSavedInstanceInfo(i)
        if type(name) == "string" and name ~= "" and (locked or extended) then
            local e = byName[name]
            if not e then
                e = { name = name, id = instID, diffs = {} }
                byName[name] = e; list[#list + 1] = e
            end
            e.diffs[#e.diffs + 1] = { name = diffName, n = numEnc, done = progress }
            if type(reset) == "number" and reset > 0 and (not lockExpire or now + reset < lockExpire) then
                lockExpire = now + reset
            end
        end
    end
    return list
end

-- "Nerub-ar Palace: Heroic 5/8, Mythic 8/8" + a tick on a cleared one
local function LockoutText(e, plain)
    local parts = {}
    for _, d in ipairs(e.diffs) do
        local s = Clean(d.name) or "?"
        local n, done = tonumber(d.n) or 0, tonumber(d.done) or 0
        if n > 0 then
            s = s .. " " .. done .. "/" .. n
            if done >= n then s = s .. Mark(true, plain) end
        end
        parts[#parts + 1] = s
    end
    return Clean(e.name) .. ": " .. table.concat(parts, ", ")
end

LIVE.gold = Money
-- Every lockout on one line, "none" when there is none (Dukul, 2026-10-17)
LIVE.lockouts = function(plain)
    local out = {}
    for _, e in ipairs(SavedInstances()) do out[#out + 1] = LockoutText(e, plain) end
    return { raw = #out > 0 and table.concat(out, ", ") or L["TOKEN_NONE"] }
end

-- {{kind:text}}: tokens whose argument is a word, not an id. Each gets the
-- argument trimmed and returns the text, or nil = as typed.
local ARGTOK = {
    reset = function(arg)
        local kind = arg:lower()
        local v = ResetText(kind)
        if v then shownReset[kind] = v end
        return v
    end,

    -- Any part of the name, any case, or the instance id. Not saved: the
    -- name as written + "not saved"
    lockout = function(arg, plain)
        local want, out = arg:lower(), {}
        for _, e in ipairs(SavedInstances()) do
            if e.name:lower():find(want, 1, true) or tostring(e.id) == arg then
                out[#out + 1] = LockoutText(e, plain)
            end
        end
        if #out == 0 then return (Clean(arg) or "") .. ": " .. L["TOKEN_NOT_SAVED"] end
        return table.concat(out, ", ")
    end,
}

-- {{kind:id}} and {{kind:text}}
local function ArgValue(name, arg, plain)
    local lname = name:lower()
    local fn, a = IDTOK[lname]
    if fn then
        a = tonumber(arg:match("^%s*(%d+)%s*$"))
    else
        fn = ARGTOK[lname]
        a = fn and arg:match("^%s*(.-)%s*$")
    end
    if not fn or not a or a == "" then return nil end
    used[lname] = true
    local ok, v = pcall(fn, a, plain)
    if not ok or v == "" then return nil end
    return v
end

local function Value(set, name, plain)
    local fn = set[name:lower()]
    if not fn then return nil, false end
    local ok, v = pcall(fn, plain)
    if not ok then return nil, true end
    if type(v) == "table" then v = v.raw else v = Clean(v) end
    if v == "" then v = nil end
    return v, true
end

-- \{{x}} | {{x}} | {{x:arg}}. Anything else between the braces (spaces, a
-- second colon-less word) is not a token and stays as typed.
local TOKEN_PAT = "(\\?){{(%a[%w_]*)(:?)([^{}\n]*)}}"

local CustomValue   -- the player's own tokens (S4), below

local function Replace(text, set, unescape, plain)
    if not text or not text:find("{{", 1, true) then return text end
    return (text:gsub(TOKEN_PAT, function(bs, name, colon, arg)
        local whole = "{{" .. name .. colon .. arg .. "}}"
        if bs ~= "" then return unescape and whole or nil end
        -- {{kind:id}} / {{kind:text}}: live only (S2, S3)
        if colon ~= "" then return set == LIVE and ArgValue(name, arg, plain) or nil end
        if arg ~= "" then return nil end
        local v, known = Value(set, name, plain)
        if not known then
            if set == LIVE then return CustomValue(name, plain) end
            return nil
        end
        if set == LIVE then used[name:lower()] = true end
        -- A live token with no value shows nothing; a snapshot one stays
        if v == nil then return set == LIVE and "" or nil end
        return v
    end))
end

-- ---------------------------------------------------------------------------
-- CUSTOM TOKENS (S4)
-- ---------------------------------------------------------------------------
-- BigNoteBoxNotesDB.tokens[name:lower()] = { name, text, created, updated }:
-- data only, never code. The name follows the token rule (a letter, then
-- letters, digits, _) and may not be a built-in name; the text is one line
-- without "|" (escape codes break chat; the built-in tokens inside make
-- their own pictures and links).
local MAX_DEPTH, MAX_NAME, MAX_TEXT = 3, 24, 255

local function CustomStore(create)
    local ndb = BNB.NotesDB and BNB.NotesDB()
    if not ndb then return nil end
    if not ndb.tokens and create then ndb.tokens = {} end
    return ndb.tokens
end

local function Builtin(lname)
    return SNAPSHOT[lname] or LIVE[lname] or IDTOK[lname] or ARGTOK[lname]
end

local function CleanText(t)
    t = tostring(t or ""):gsub("[\r\n]+", " "):gsub("|", "")
    t = t:match("^%s*(.-)%s*$") or ""
    if #t > MAX_TEXT then t = t:sub(1, MAX_TEXT) end
    return t
end

local depth = 0
CustomValue = function(name, plain)
    local s = CustomStore(false)
    local rec = s and s[name:lower()]
    if type(rec) ~= "table" or type(rec.text) ~= "string" or depth >= MAX_DEPTH then return nil end
    depth = depth + 1
    -- Snapshot tokens inside fill too, with today's values: the definition
    -- is the writer's own, so "{{date}}" there means the day it is drawn
    local ok, v = pcall(function()
        return Replace(Replace(rec.text, SNAPSHOT, false, plain), LIVE, true, plain)
    end)
    depth = depth - 1
    if not ok then return nil end
    return v
end

local function CustomChanged()
    BNB.SendMessage("CustomTokensChanged")
    BNB.Debounce("tokensChanged", 0, SendChanged)
end

function T.Custom()
    local out, s = {}, CustomStore(false)
    for key, rec in pairs(s or {}) do
        if type(rec) == "table" and type(rec.name) == "string" and type(rec.text) == "string" then
            out[#out + 1] = { key = key, name = rec.name, text = rec.text }
        end
    end
    table.sort(out, function(a, b) return a.key < b.key end)
    return out
end

function T.GetCustom(name)
    local s = CustomStore(false)
    local rec = s and type(name) == "string" and s[name:lower()]
    if type(rec) == "table" then return rec end
end

-- Returns true, or nil and the reason to show. Braces typed around the
-- name ({{raidtime}}) are dropped.
function T.SetCustom(name, text, oldName)
    name = tostring(name or ""):gsub("[{}%s]", "")
    if name == "" or #name > MAX_NAME or not name:match("^%a[%w_]*$") then
        return nil, L["TOKEN_CUSTOM_ERR_NAME"]
    end
    local key = name:lower()
    if Builtin(key) then return nil, string.format(L["TOKEN_CUSTOM_ERR_BUILTIN"], name) end
    text = CleanText(text)
    if text == "" then return nil, L["TOKEN_CUSTOM_ERR_TEXT"] end
    local s = CustomStore(true)
    if not s then return nil, L["TOKEN_CUSTOM_ERR_NAME"] end
    local oldKey = type(oldName) == "string" and oldName:lower() or nil
    if s[key] and key ~= oldKey then return nil, string.format(L["TOKEN_CUSTOM_ERR_TAKEN"], name) end
    local now = time()
    local prev = oldKey and s[oldKey]
    if oldKey and oldKey ~= key then s[oldKey] = nil end
    local created = now
    if type(prev) == "table" and prev.created then created = prev.created end
    s[key] = { name = name, text = text, created = created, updated = now }
    CustomChanged()
    return true
end

function T.DeleteCustom(name)
    local s = CustomStore(false)
    if not (s and type(name) == "string" and s[name:lower()]) then return end
    s[name:lower()] = nil
    CustomChanged()
end

-- What a definition gives right now (the settings page's preview)
function T.CustomPreview(text)
    text = CleanText(text)
    local ok, v = pcall(function() return Replace(Replace(text, SNAPSHOT, false), LIVE, true) end)
    if ok then return v end
    return text
end

-- The JSON full backup (Features/NoteExport.lua), next to the templates
function T.BackupList()
    local out = {}
    for _, e in ipairs(T.Custom()) do out[#out + 1] = { name = e.name, text = e.text } end
    return out
end

-- Adds the backup's tokens whose name is free; returns how many
function T.ImportRecords(list)
    if type(list) ~= "table" then return 0 end
    local n, s = 0, CustomStore(true)
    if not s then return 0 end
    for _, raw in ipairs(list) do
        if type(raw) == "table" and type(raw.name) == "string" and type(raw.text) == "string"
           and not s[raw.name:lower()] and T.SetCustom(raw.name, raw.text) then
            n = n + 1
        end
    end
    return n
end

-- ---------------------------------------------------------------------------
-- REDRAW ON GAME EVENTS (S3)
-- ---------------------------------------------------------------------------
-- Event -> the tokens it changes. TokensChanged goes out (debounced) only
-- when one of them was drawn since the last redraw; sending clears the list
-- and the redrawn views mark theirs again, so a note that was closed stops
-- costing anything. An event this client lacks is skipped.
local EVENTS = {
    PLAYER_MONEY                  = { "gold" },
    PLAYER_LEVEL_UP               = { "level" },
    PLAYER_LEVEL_CHANGED          = { "level" },
    ZONE_CHANGED_NEW_AREA         = { "here" },
    PLAYER_ENTERING_WORLD         = { "here" },
    PLAYER_GUILD_UPDATE           = { "guild", "guildrank" },
    GUILD_RANKS_UPDATE            = { "guildrank" },
    PLAYER_EQUIPMENT_CHANGED      = { "ilvl" },
    PLAYER_AVG_ITEM_LEVEL_UPDATE  = { "ilvl" },
    PLAYER_SPECIALIZATION_CHANGED = { "spec" },
    ACTIVE_TALENT_GROUP_CHANGED   = { "spec" },
    UPDATE_INSTANCE_INFO          = { "lockout", "lockouts" },
    QUEST_TURNED_IN               = { "quest" },
    CURRENCY_DISPLAY_UPDATE       = { "currency" },
    UPDATE_FACTION                = { "rep" },
    MAJOR_FACTION_RENOWN_LEVEL_CHANGED = { "rep" },
    ACHIEVEMENT_EARNED            = { "achievement" },
    NEW_MOUNT_ADDED               = { "mount" },
    COMPANION_LEARNED             = { "mount", "pet" },
    NEW_PET_ADDED                 = { "pet" },
}

local function Redraw()
    used, shownReset, lockExpire = {}, {}, nil
    BNB.Debounce("tokensChanged", 0.2, SendChanged)
end

local IsValid = C_EventUtils and C_EventUtils.IsEventValid
for event, names in pairs(EVENTS) do
    if not IsValid or IsValid(event) then
        BNB.RegisterEvent(event, function()
            for _, n in ipairs(names) do
                if used[n] then Redraw(); return end
            end
        end)
    end
end

-- A boss kill changes a lockout: ask the game again a moment later (the
-- save is not there yet when the encounter ends)
BNB.RegisterEvent("ENCOUNTER_END", function()
    if used.lockout or used.lockouts then BNB.Debounce("tokensRaidInfo", 3, AskRaidInfo) end
end)

-- Countdowns: every 5 s while one was drawn, a redraw when its text would
-- read differently now; a shown lockout that has run out asks the game again
C_Timer.NewTicker(5, function()
    if used.reset then
        for kind, shown in pairs(shownReset) do
            if ResetText(kind) ~= shown then Redraw(); return end
        end
    end
    if (used.lockout or used.lockouts) and lockExpire and time() >= lockExpire then
        lockExpire = nil
        AskRaidInfo()
    end
end)

-- Live tokens filled, escapes dropped: the text as the reader sees it.
-- mode "plain": for an edit box or chat (see the header)
function T.Fill(text, mode)
    return Replace(text, LIVE, true, mode == "plain")
end

-- Snapshot tokens filled, live ones and escapes kept: a note made from a
-- template (ALL-68). blank = a snapshot token with no value right now
-- ({{instance}} out in the world) becomes "" instead of staying as typed
function T.Snapshot(text, blank)
    if not blank then return Replace(text, SNAPSHOT, false) end
    if not text or not text:find("{{", 1, true) then return text end
    return (text:gsub(TOKEN_PAT, function(bs, name, colon, arg)
        if bs ~= "" or colon ~= "" or arg ~= "" then return nil end
        local v, known = Value(SNAPSHOT, name)
        if not known then return nil end
        return v or ""
    end))
end

-- true when the text still holds a snapshot token (a template title whose
-- {{target}} had no value falls back to the template's name)
function T.HasSnapshot(text)
    if not text or not text:find("{{", 1, true) then return false end
    for bs, name in text:gmatch("(\\?){{(%a[%w_]*)}}") do
        if bs == "" and SNAPSHOT[name:lower()] then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- THE TOOLBAR'S TOKEN LIST (S2, UI/WysiwygBar.lua)
-- ---------------------------------------------------------------------------
-- Groups in menu order. Labels / tooltips: L["TOKEN_GROUP_<group>"],
-- L["TOKEN_DESC_<NAME>"], one shared line per kind L["TOKEN_KIND_<KIND>"].
-- A new token goes in its set above AND here. In a live group, "reset:weekly"
-- is a whole token with its argument (TOKEN_DESC_RESET_WEEKLY) and "lockout:"
-- one whose argument the writer types (inserted with the cursor before }}).
T.MENU = {
    { group = "SNAPSHOT", kind = "snapshot",
      list = { "date", "time", "zone", "subzone", "instance", "target", "coords" } },
    { group = "LIVE", kind = "live",
      list = { "me", "name", "realm", "class", "race", "level", "faction", "spec", "ilvl",
               "guild", "guildrank", "here", "gold" } },
    { group = "TIME", kind = "live",
      list = { "reset:weekly", "reset:daily", "lockout:", "lockouts" } },
    { group = "ID", kind = "id",
      list = { "item", "quest", "achievement", "currency", "rep", "spell", "mount", "pet" } },
}

-- The id each id token's tooltip example uses: there on most clients
-- (Hearthstone, "A Threat Within", Level 10, Honor, Stormwind, Brown Horse,
-- Mechanical Squirrel). One this client lacks just shows no example.
local EXAMPLE_ID = { item = 6948, quest = 783, achievement = 6, currency = 1792, rep = 72,
                     spell = 8690, mount = 6, pet = 39 }

-- Id tokens whose data this client does not have are left out of the list
-- (they still show as typed in a note): no achievements on Forever or Era,
-- no pet journal data on Forever (Dukul, 2026-10-17). Asked of the game's
-- data, not of the client, so a client that gains them lists them.
local HAS = {
    achievement = function() return type((select(2, GetAchievementInfo(6)))) == "string" end,   -- Level 10
    pet   = function() return type((C_PetJournal.GetPetInfoBySpeciesID(39))) == "string" end,
    mount = function() return (C_MountJournal.GetNumMounts() or 0) > 0 end,
}
function T.Available(name)
    local fn = HAS[name]
    if not fn then return true end
    local ok, yes = pcall(fn)
    return ok and yes and true or false
end

-- For the tooltip: what the token gives right now, and how it is written.
-- An id token's example is filled from EXAMPLE_ID (nil value = no example,
-- or its data is still loading).
function T.Preview(name, kind)
    if kind == "snapshot" then return (Value(SNAPSHOT, name)), "{{" .. name .. "}}" end
    local base, arg = name:match("^(%a+):(.*)$")
    if kind == "live" and base then
        -- {{lockout:}}: the example is the reader's first lockout, if any
        if arg == "" then
            local ok, list = pcall(SavedInstances)
            local first = ok and list[1]
            if not first then return nil, "{{" .. base .. ":" .. L["TOKEN_EXAMPLE_INSTANCE"] .. "}}" end
            arg = first.name
        end
        return ArgValue(base, arg, false), "{{" .. base .. ":" .. arg .. "}}"
    end
    if kind == "live" then return (Value(LIVE, name)), "{{" .. name .. "}}" end
    local written = "{{" .. name .. ":" .. (EXAMPLE_ID[name] or 1) .. "}}"
    local v = ArgValue(name, tostring(EXAMPLE_ID[name] or 1), false)
    return v, written
end

-- ---------------------------------------------------------------------------
-- EXPAND AS TYPED
-- ---------------------------------------------------------------------------
-- The closing }} of a snapshot token turns it into its value. undoID returns
-- the note id whose undo stack the box uses (main editor, Focus mode), or is
-- nil (sticky inline edit: no undo there). Hooked, so call it after the box's
-- own OnTextChanged is set.
function T.WireExpand(eb, undoID)
    if not eb or eb._bnbTokenExpand then return end
    eb._bnbTokenExpand = true
    eb:HookScript("OnTextChanged", function(self, userInput)
        if not userInput or self._showingPlaceholder then return end
        local text = self:GetText() or ""
        local cur  = self:GetCursorPosition() or 0
        if cur < 6 or text:sub(cur - 1, cur) ~= "}}" then return end
        local s, _, bs, name = text:sub(1, cur):find("(\\?){{(%a[%w_]*)}}$")
        if not s or bs ~= "" then return end
        local v = Value(SNAPSHOT, name)
        if not v then return end
        local newText = text:sub(1, s - 1) .. v .. text:sub(cur + 1)
        local newCur  = s - 1 + #v
        local id = undoID and undoID()
        -- The token as typed first, so one Undo brings it back
        if id then BNB.UndoPush(id, text, cur) end
        BNB._undoActive = true
        self:SetText(newText)
        BNB._undoActive = false
        self:SetCursorPosition(newCur)
        if id then
            BNB.UndoPush(id, newText, newCur)
            if BNB._refreshUndoButtons then BNB._refreshUndoButtons() end
        end
    end)
end

-- ---------------------------------------------------------------------------
-- THE {{ LIST AS TYPED (S4)
-- ---------------------------------------------------------------------------
-- Typing {{ opens a list of tokens under the cursor: the player's own first,
-- then the built-ins, narrowed by what follows the braces. Up / Down move,
-- Enter, Tab or a click puts the token in and closes the }}, Esc or anything
-- that is not part of a token name closes the list. Enter in a box of many
-- lines types no new line then; in a one-line box (tl;dr) it also does what
-- Enter does there (saves), since that cannot be held back. One shared list.
-- undoID as in WireExpand; onChange() = the box's own "text changed" (mark
-- dirty), since a SetText from here is not typing.
local AC_ROWS, AC_ROW_H, AC_W = 8, 20, 300
local _ac
local _eat   -- { eb, text, cur }: the new line Enter types after a pick

-- Every pick, in list order: { word, label, kind, now() }
local function Entries()
    local out = {}
    for _, c in ipairs(T.Custom()) do
        local text = c.text
        out[#out + 1] = { word = c.name, kind = "custom", desc = text,
                          now = function() return T.CustomPreview(text) end }
    end
    for _, g in ipairs(T.MENU) do
        for _, name in ipairs(g.list) do
            if T.Available(name) then
                local base = name:gsub(":$", "")
                local open = g.kind == "id" or base ~= name
                local kind = g.kind
                out[#out + 1] = { word = open and (base .. ":") or name, kind = kind, open = open,
                                  base = base, name = name,
                                  desc = L["TOKEN_DESC_" .. base:upper():gsub(":", "_")],
                                  now = function() return (T.Preview(name, kind)) end }
            end
        end
    end
    return out
end

-- While the list shows, the box is in alt-arrow mode (as the chat box):
-- plain arrows then go to OnArrowPressed and leave the cursor alone. A box
-- of many lines moves its cursor on an arrow and never fires OnArrowPressed
-- (Dukul, 2026-10-17: "The arrow keys don't work").
local function ArrowMode(eb, on)
    if not (eb and eb.SetAltArrowKeyMode) then return end
    if on then
        if eb._bnbAltPrev == nil then
            eb._bnbAltPrev = eb:GetAltArrowKeyMode() and true or false
            eb:SetAltArrowKeyMode(true)
        end
    elseif eb._bnbAltPrev ~= nil then
        eb:SetAltArrowKeyMode(eb._bnbAltPrev)
        eb._bnbAltPrev = nil
    end
end

local function Hide()
    if _ac then
        ArrowMode(_ac._eb, false)
        _ac:Hide()
        _ac._eb = nil
        if GameTooltip:IsOwned(_ac) then GameTooltip:Hide() end
    end
end

local function ShowTip()
    local e = _ac.matches[_ac.sel]
    if not e then return end
    GameTooltip:SetOwner(_ac, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("TOPLEFT", _ac, "TOPRIGHT", 4, 0)
    local hint = L["TOKEN_ARG_NAME"]
    if e.kind == "id" then hint = "id" end
    GameTooltip:AddLine("{{" .. e.word .. (e.open and hint or "") .. "}}", 1, 1, 1)
    if e.kind == "custom" then
        GameTooltip:AddLine(L["TOKEN_CUSTOM_KIND"], 0.6, 0.8, 1, true)
    elseif e.desc then
        GameTooltip:AddLine(e.desc, 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(L["TOKEN_KIND_" .. e.kind:upper()], 0.6, 0.6, 0.6, true)
    end
    if e.kind == "custom" then GameTooltip:AddLine(e.desc, 0.8, 0.8, 0.8, true) end
    GameTooltip:AddLine(L["TOKEN_AC_HINT"], 0.4, 0.85, 0.4, true)
    GameTooltip:Show()
end

local function Paint()
    for i, r in ipairs(_ac.rows) do r._sel:SetShown(i == _ac.sel) end
    ShowTip()
end

-- The token in: "{{" .. partial at the cursor becomes the whole token; an
-- argument token leaves the cursor before its }}; a snapshot token with a
-- value goes in as that value (one Undo brings the token back, as typing it)
local function Accept(i)
    local e = _ac and _ac.matches[i or _ac.sel]
    local eb = _ac and _ac._eb
    if not (e and eb) then return end
    local opts = eb._bnbTokenAC
    local text, cur, s = eb:GetText() or "", _ac._cur, _ac._start
    local tail = cur + 1
    if text:sub(tail, tail + 1) == "}}" then tail = tail + 2 end   -- already closed
    local token = "{{" .. e.word .. "}}"
    local back = e.open and 2 or 0
    local value = e.kind == "snapshot" and not e.open and e.now() or nil
    local id = opts.undoID and opts.undoID()
    Hide()
    local newText, newCur
    local function Put(ins, b)
        newText = text:sub(1, s - 1) .. ins .. text:sub(tail)
        newCur  = s - 1 + #ins - b
        BNB._undoActive = true
        eb:SetText(newText)
        BNB._undoActive = false
        eb:SetCursorPosition(newCur)
        if id then BNB.UndoPush(id, newText, newCur) end
    end
    if id then BNB.UndoPush(id, text, cur) end
    Put(token, back)
    if value then Put(value, 0) end
    if id and BNB._refreshUndoButtons then BNB._refreshUndoButtons() end
    if opts.onChange then opts.onChange() end
    return newText, newCur
end

local function Build()
    if _ac then return end
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    BNB.EnsureBackdrop(f)
    BNB.SetBackdrop(f, 0.05, 0.05, 0.08, 0.97, 0.40, 0.40, 0.50, 1)
    f:SetFrameStrata("TOOLTIP")   -- no keyboard here: the box keeps its keys
    f:SetClampedToScreen(true)
    f:SetWidth(AC_W)
    f:EnableMouse(true)
    f:Hide()
    f.rows, f.matches, f.sel = {}, {}, 1
    for i = 1, AC_ROWS do
        local r = CreateFrame("Button", nil, f)
        r:SetHeight(AC_ROW_H)
        r:SetPoint("TOPLEFT",  f, "TOPLEFT",  4, -4 - (i - 1) * AC_ROW_H)
        r:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4 - (i - 1) * AC_ROW_H)
        local hl = r:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.08)
        local sel = r:CreateTexture(nil, "BACKGROUND")
        sel:SetAllPoints(); sel:SetColorTexture(0.2, 0.4, 0.7, 0.45)
        sel:Hide()
        r._sel = sel
        local name = r:CreateFontString(nil, "OVERLAY", "BNBFontHighlightSmall")
        name:SetPoint("LEFT", r, "LEFT", 6, 0)
        name:SetJustifyH("LEFT"); name:SetWordWrap(false)
        r._name = name
        local now = r:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
        now:SetPoint("LEFT", name, "RIGHT", 8, 0)
        now:SetPoint("RIGHT", r, "RIGHT", -6, 0)
        now:SetJustifyH("RIGHT"); now:SetWordWrap(false)
        now:SetTextColor(0.55, 0.55, 0.55)
        r._now = now
        r:SetScript("OnEnter", function() f.sel = i; Paint() end)
        r:SetScript("OnClick", function()
            local eb = f._eb
            local _, newCur = Accept(i)
            if eb and newCur then eb:SetFocus(); eb:SetCursorPosition(newCur) end
        end)
        f.rows[i] = r
    end
    f:SetScript("OnHide", function(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    _ac = f
end

-- The window the box sits in: the list goes on its parent chain's top so it
-- shows where the box shows (Focus mode hides UIParent)
local function TopOf(frame)
    local f = frame
    while f:GetParent() and f:GetParent() ~= UIParent and f:GetParent() ~= WorldFrame do
        f = f:GetParent()
    end
    return f:GetParent() or UIParent
end

local function Open(eb, start, cur, partial)
    Build()
    local low, list = partial:lower(), {}
    for _, e in ipairs(Entries()) do
        if e.word:lower():sub(1, #low) == low and e.word:lower() ~= low then list[#list + 1] = e end
    end
    if #list == 0 then Hide(); return end
    local f = _ac
    if f._eb and f._eb ~= eb then ArrowMode(f._eb, false) end
    if f._eb ~= eb or f._start ~= start then f.sel = 1 end
    f._eb, f._start, f._cur, f.matches = eb, start, cur, list
    if f.sel > math.min(#list, AC_ROWS) then f.sel = 1 end
    for i, r in ipairs(f.rows) do
        local e = list[i]
        if e and i <= AC_ROWS then
            local word = e.word
            if e.open then word = word .. "|cff888888" .. (e.kind == "id" and "id" or L["TOKEN_ARG_NAME"]) .. "|r" end
            local label = "{{" .. word .. "}}"
            if e.kind == "custom" then label = "|cff99ccff{{" .. e.word .. "}}|r" end
            r._name:SetText(label)
            local ok, now = pcall(e.now)
            r._now:SetText((ok and not e.open and now) or "")
            r:Show()
        else
            r:Hide()
        end
    end
    local shown = math.min(#list, AC_ROWS)
    f:SetHeight(shown * AC_ROW_H + 8)
    local parent = TopOf(eb)
    if f:GetParent() ~= parent then f:SetParent(parent); f:SetFrameStrata("TOOLTIP") end
    f:SetScale(eb:GetEffectiveScale() / parent:GetEffectiveScale())
    f:ClearAllPoints()
    local c = eb._bnbCaret
    if c then
        f:SetPoint("TOPLEFT", eb, "TOPLEFT", c.x, c.y - c.h - 2)
    else
        f:SetPoint("TOPLEFT", eb, "BOTTOMLEFT", 0, -2)
    end
    ArrowMode(eb, true)
    f:Show()
    Paint()
end

-- What is typed between {{ and the cursor, if the cursor is in a token name
local function Partial(eb)
    local text = eb:GetText() or ""
    local cur = eb:GetCursorPosition() or 0
    local head = text:sub(1, cur)
    local s, _, partial = head:find("{{([%w_:]*)$")
    if not s then return nil end
    if s > 1 and head:sub(s - 1, s - 1) == "\\" then return nil end   -- \{{ = text
    if partial ~= "" and not partial:match("^%a") then return nil end
    return s, cur, partial
end

function T.TrackCaret(eb)
    if not eb then return end
    eb:HookScript("OnCursorChanged", function(self, x, y, _, h)
        local c = self._bnbCaret or {}
        c.x, c.y, c.h = x or 0, y or 0, h or 12
        self._bnbCaret = c
    end)
end

function T.WireAutocomplete(eb, undoID, onChange)
    if not eb or eb._bnbTokenAC then return end
    eb._bnbTokenAC = { undoID = undoID, onChange = onChange }
    T.TrackCaret(eb)
    eb:HookScript("OnTextChanged", function(self, userInput)
        -- The new line after an Enter pick: taken out again
        local eat = _eat
        if eat and eat.eb == self then
            _eat = nil
            local text = self:GetText() or ""
            if text == eat.text:sub(1, eat.cur) .. "\n" .. eat.text:sub(eat.cur + 1) then
                BNB._undoActive = true
                self:SetText(eat.text)
                BNB._undoActive = false
                self:SetCursorPosition(eat.cur)
                return
            end
        end
        if not userInput or self._showingPlaceholder then return end
        local s, cur, partial = Partial(self)
        if s then Open(self, s, cur, partial)
        elseif _ac and _ac._eb == self then Hide() end
    end)
    eb:HookScript("OnTabPressed", function(self)
        if _ac and _ac:IsShown() and _ac._eb == self then Accept() end
    end)
    eb:HookScript("OnArrowPressed", function(self, key)
        if not (_ac and _ac:IsShown() and _ac._eb == self) then return end
        if key == "UP" or key == "DOWN" then
            local n = math.min(#_ac.matches, AC_ROWS)
            if key == "DOWN" then _ac.sel = _ac.sel % n + 1
            else _ac.sel = (_ac.sel <= 1) and n or (_ac.sel - 1) end
            Paint()
        else
            -- Left / Right: the list closes and the cursor takes that step,
            -- which alt-arrow mode held back
            local pos = self:GetCursorPosition() or 0
            Hide()
            if key == "LEFT" then self:SetCursorPosition(math.max(0, pos - 1))
            elseif key == "RIGHT" then self:SetCursorPosition(pos + 1) end
        end
    end)
    -- Enter: OnKeyDown runs before the box acts on the key, so the token is
    -- in before a one-line box's OnEnterPressed reads the text. Ctrl+Enter
    -- stays the sticky's "end the edit".
    eb:HookScript("OnKeyDown", function(self, key)
        if not (_ac and _ac:IsShown() and _ac._eb == self) then return end
        if (key == "ENTER" or key == "NUMPADENTER") and not IsControlKeyDown() then
            local newText, newCur = Accept()
            if newText and self:IsMultiLine() then _eat = { eb = self, text = newText, cur = newCur } end
            C_Timer.After(0, function() if _eat and _eat.eb == self then _eat = nil end end)
        end
    end)
    eb:HookScript("OnEscapePressed", function(self) if _ac and _ac._eb == self then Hide() end end)
    -- A moment later, so a click on a row still lands
    eb:HookScript("OnEditFocusLost", function(self)
        C_Timer.After(0.15, function()
            if _ac and _ac._eb == self and not self:HasFocus() then Hide() end
        end)
    end)
    eb:HookScript("OnHide", function(self) if _ac and _ac._eb == self then Hide() end end)
end

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

local function IdValue(name, arg, plain)
    local fn = IDTOK[name:lower()]
    if not fn then return nil end
    local id = tonumber(arg:match("^%s*(%d+)%s*$"))
    if not id then return nil end
    local ok, v = pcall(fn, id, plain)
    if not ok or v == "" then return nil end
    return v
end

local function Value(set, name)
    local fn = set[name:lower()]
    if not fn then return nil, false end
    local ok, v = pcall(fn)
    if not ok then return nil, true end
    if type(v) == "table" then v = v.raw else v = Clean(v) end
    if v == "" then v = nil end
    return v, true
end

-- \{{x}} | {{x}} | {{x:arg}}. Anything else between the braces (spaces, a
-- second colon-less word) is not a token and stays as typed.
local TOKEN_PAT = "(\\?){{(%a[%w_]*)(:?)([^{}\n]*)}}"

local function Replace(text, set, unescape, plain)
    if not text or not text:find("{{", 1, true) then return text end
    return (text:gsub(TOKEN_PAT, function(bs, name, colon, arg)
        local whole = "{{" .. name .. colon .. arg .. "}}"
        if bs ~= "" then return unescape and whole or nil end
        -- {{kind:id}}: live id tokens only (S2)
        if colon ~= "" then return set == LIVE and IdValue(name, arg, plain) or nil end
        if arg ~= "" then return nil end
        local v, known = Value(set, name)
        if not known then return nil end
        -- A live token with no value shows nothing; a snapshot one stays
        if v == nil then return set == LIVE and "" or nil end
        return v
    end))
end

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
-- A new token goes in its set above AND here.
T.MENU = {
    { group = "SNAPSHOT", kind = "snapshot",
      list = { "date", "time", "zone", "subzone", "instance", "target", "coords" } },
    { group = "LIVE", kind = "live",
      list = { "me", "name", "realm", "class", "race", "level", "faction", "spec", "ilvl",
               "guild", "guildrank", "here" } },
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
    if kind == "live" then return (Value(LIVE, name)), "{{" .. name .. "}}" end
    local written = "{{" .. name .. ":" .. (EXAMPLE_ID[name] or 1) .. "}}"
    local v = IdValue(name, tostring(EXAMPLE_ID[name] or 1), false)
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

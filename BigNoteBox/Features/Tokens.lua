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
--
-- Rules (Dukul, 2026-10-17):
--   * An unknown token, or a snapshot token left in the text, shows as typed.
--   * \{{me}} shows {{me}} as text (the backslash is dropped on display).
--   * A live token with no value right now (no guild) shows nothing.
--   * The plain editor shows tokens raw: the text being edited is what was typed.
--   * Tokens are data only. Never Lua from a note, share string or definition:
--     a shared note would run someone else's code.
--   * Names are case-insensitive. Arguments ({{item:123}}) are parsed but no
--     S1 token takes one (S2).
--
-- Every place that shows note text to the player fills it with T.Fill: the
-- rich converter (AM.ToHTML), plain sticky read view, tl;dr (BNB.NoteTldr),
-- situation toast summary, note link preview, Send to Chat.
--
-- Public API:
--   BNB.Tokens.Fill(text)               -- live tokens filled, for display
--   BNB.Tokens.Snapshot(text, blank)    -- snapshot tokens filled (templates)
--   BNB.Tokens.HasSnapshot(text)        -- a snapshot token still in the text
--   BNB.Tokens.WireExpand(eb, undoID)   -- expand snapshot tokens as typed

local BNB = BigNoteBox
if not BNB then return end

local T = {}
BNB.Tokens = T

-- A value as plain text: one line, no "|" (escape codes, and chat drops them),
-- no braces (so it can never make markup or another token)
local function Clean(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return "?" end   -- Midnight, in combat
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
    -- "/way Zone 42.3 61.0": a clickable waypoint link in rich notes (ALL-381)
    coords = function() return BNB.PlayerWayString and BNB.PlayerWayString() end,
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

local function Value(set, name)
    local fn = set[name:lower()]
    if not fn then return nil, false end
    local ok, v = pcall(fn)
    if not ok then return nil, true end
    v = Clean(v)
    if v == "" then v = nil end
    return v, true
end

-- \{{x}} | {{x}} | {{x:arg}}. Anything else between the braces (spaces, a
-- second colon-less word) is not a token and stays as typed.
local TOKEN_PAT = "(\\?){{(%a[%w_]*)(:?)([^{}\n]*)}}"

local function Replace(text, set, unescape)
    if not text or not text:find("{{", 1, true) then return text end
    return (text:gsub(TOKEN_PAT, function(bs, name, colon, arg)
        local whole = "{{" .. name .. colon .. arg .. "}}"
        if bs ~= "" then return unescape and whole or nil end
        if colon == "" and arg ~= "" then return nil end
        local v, known = Value(set, name)
        if not known then return nil end
        -- A live token with no value shows nothing; a snapshot one stays
        if v == nil then return set == LIVE and "" or nil end
        return v
    end))
end

-- Live tokens filled, escapes dropped: the text as the reader sees it
function T.Fill(text)
    return Replace(text, LIVE, true)
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

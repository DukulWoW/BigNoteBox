-- BigNoteBox Features/OracleSearch.lua -- Oracle search: matching and ranking (ALL-69)
--
-- Pure Lua, no WoW API: UI/Oracle.lua hands it the notes and the query and
-- draws what comes back. Kept apart so LuaJIT can test it outside the game.
--
-- A query is plain words; a note matches when every word is found somewhere
-- in it. Each word scores by the best place it was found (title > tag >
-- context / who the note is about > body), so a word in the title outranks
-- the same word in the body. Ties go to the most recently edited note.
-- Prefixes (ALL-69.2) narrow the search before scoring; weights (ALL-69.3)
-- then add context boosts (this character, current zone, target...) on top
-- of the word score, so they reorder close matches without beating a title
-- hit with a body hit.
--
-- ParseQuery() below is the whole prefix grammar, pure so LuaJIT can test it
-- (_work/tools/oracle-test.lua). UI/Oracle.lua supplies the localized letter
-- and date-word maps (built from L) and does everything WoW-side: choosing
-- the note source (trash vs normal) from parsed.openAs == "trash", the
-- help listing for parsed.help, and what Enter/modifiers do with openAs.

local BNB = BigNoteBox

local OS = {}
BNB.OracleSearch = OS

-- WoW exposes date()/time() as globals (like os.date/os.time); plain Lua
-- (the LuaJIT test harness) only has the os.* versions.
local dateFn = date or os.date
local timeFn = time or os.time
local DAY = 86400

-- Prefix letter -> role. English by default; UI/Oracle.lua builds the
-- localized map from the L keys below and passes it in as opts.prefixes.
OS.DEFAULT_PREFIXES = {
    s = "sticky", f = "focus", r = "refbox", b = "trash",
    p = "player", n = "npc",   i = "item",   z = "zone",
    c = "char",   g = "global", t = "tasks", a = "alarm",
    x = "rich",   l = "plain", d = "date",
    m = "send",   -- send to chat (ALL-426)
}
-- Roles that pick how a result opens (at most one per query) rather than
-- filtering which notes match.
OS.OPEN_AS = { sticky = true, focus = true, refbox = true, trash = true, send = true }

OS.PREFIX_L_KEYS = {
    s = "ORACLE_PREFIX_STICKY", f = "ORACLE_PREFIX_FOCUS",
    r = "ORACLE_PREFIX_REFBOX", b = "ORACLE_PREFIX_TRASH",
    p = "ORACLE_PREFIX_PLAYER", n = "ORACLE_PREFIX_NPC",
    i = "ORACLE_PREFIX_ITEM",   z = "ORACLE_PREFIX_ZONE",
    c = "ORACLE_PREFIX_CHAR",   g = "ORACLE_PREFIX_GLOBAL",
    t = "ORACLE_PREFIX_TASKS",  a = "ORACLE_PREFIX_ALARM",
    x = "ORACLE_PREFIX_RICH",   l = "ORACLE_PREFIX_PLAIN",
    d = "ORACLE_PREFIX_DATE",
    m = "ORACLE_PREFIX_SEND",
}

-- `d` argument keywords -> date kind. English by default, same L pattern.
OS.DEFAULT_DATE_WORDS = {
    today = "today", yesterday = "yesterday",
    week = "week", month = "month", year = "year",
}
OS.DATE_WORD_L_KEYS = {
    today = "ORACLE_DATE_TODAY", yesterday = "ORACLE_DATE_YESTERDAY",
    week = "ORACLE_DATE_WEEK", month = "ORACLE_DATE_MONTH", year = "ORACLE_DATE_YEAR",
}

-- Base score per field a word was found in. item: a word found in an item's
-- name while the `i` prefix is on, which ranks like the title.
OS.SCORE = { title = 100, tag = 60, who = 40, body = 10, item = 100 }
-- Extra when the whole query starts or equals the title.
OS.TITLE_PREFIX_BONUS = 40
OS.TITLE_EXACT_BONUS  = 80

-- Weights (ALL-69.3): each boost is Off / Low / Normal / High, saved in
-- BigNoteBoxDB.oracleWeights[key] (nil = the default here) and handed in as
-- ctx.weights. Points are on the same scale as OS.SCORE: High is less than
-- a title hit, Low about a body hit.
OS.WEIGHT_KEYS = { "char", "zone", "fav", "opened", "target", "edited", "alarm" }
OS.WEIGHT_DEFAULTS = {
    char = "normal", zone = "normal", fav = "low", opened = "low",
    target = "high", edited = "low", alarm = "low",
}
OS.WEIGHT_LEVELS = { "off", "low", "normal", "high" }
OS.WEIGHT_POINTS = { off = 0, low = 15, normal = 30, high = 60 }
-- Recently opened / edited: full points within a day, half within a week.
OS.RECENT_FULL = DAY
OS.RECENT_HALF = 7 * DAY
-- Alarm due soon: set to go off within this many seconds.
OS.ALARM_SOON = DAY

local SNIPPET_BEFORE = 30    -- bytes of body shown before the first hit
local SNIPPET_LEN    = 140   -- bytes of body in a snippet at most

-- Body text as a reader sees it: WoW escapes and BNB markup removed, links
-- reduced to their text, runs of whitespace (newlines included) to a space.
-- Markup is only stripped from rich notes: a plain note may hold a literal
-- "{...}", which is text there.
function OS.PlainText(s, rich)
    if not s or s == "" then return "" end
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("|H.-|h(.-)|h", "%1")
    s = s:gsub("|T.-|t", ""):gsub("|A.-|a", "")
    if rich then
        s = s:gsub("{link%*[^*}]*%*([^}]*)}", "%1")
        s = s:gsub("{br}", " ")
        s = s:gsub("{/?%a[^{}]*}", "")
    end
    s = s:gsub("%s+", " ")
    return (s:gsub("^ ", ""):gsub(" $", ""))
end

-- Lower-case search text per note, rebuilt only when the note was edited.
-- Keyed by id; a stamp that differs from note.updated means stale.
local cache = {}

local function Fields(note)
    local c = cache[note.id]
    local stamp = note.updated or 0
    if c and c.stamp == stamp and c.rich == (note.richMode == true) then return c end
    local tags = {}
    for i, t in ipairs(note.tags or {}) do tags[i] = tostring(t):lower() end
    local who = {}
    -- Off situations too: still who the note is about (ALL-435)
    local sits = BNB.AllSituations(note)
    for _, ctx in ipairs(sits) do
        ctx = BNB.SituationBare(ctx)
        who[#who + 1] = (ctx:match("^%w+:(.+)$") or ctx):lower()
    end
    if note.inspectName then who[#who + 1] = tostring(note.inspectName):lower() end
    -- @who matches only who a note is about: a player context, the inspected
    -- player, or the NPC of a target note (whose name is only in its title).
    -- A zone context counts for plain words (who above), not for @.
    local about = {}
    for _, ctx in ipairs(sits) do
        ctx = BNB.SituationBare(ctx)
        local name = ctx:match("^player:(.+)$") or ctx:match("^npc:(.+)$")
        if name then about[#about + 1] = name:lower() end
    end
    if note.inspectName then about[#about + 1] = tostring(note.inspectName):lower() end
    if note.source == "target" or note.source == "inspect" then
        about[#about + 1] = (note.title or ""):lower()
    end
    -- Names of items linked in the body ("[Name]" in the link text), for `i`.
    local items = {}
    if type(note.body) == "string" then
        for name in note.body:gmatch("|Hitem:.-|h%[?(.-)%]?|h") do items[#items + 1] = name:lower() end
    end
    local plain = OS.PlainText(note.body, note.richMode == true)
    c = {
        stamp = stamp, rich = note.richMode == true,
        title = (note.title or ""):lower(),
        tags  = tags,
        who   = table.concat(who, " "),
        about = table.concat(about, "\n"),
        items = table.concat(items, "\n"),
        plain = plain,
        body  = plain:lower(),
    }
    cache[note.id] = c
    return c
end

-- Drops the cache (a note deleted, or a test starting over).
function OS.ClearCache() cache = {} end

-- Words of a query, lower-cased. An empty or blank query gives none.
function OS.Words(query)
    local words = {}
    for w in (query or ""):lower():gmatch("%S+") do words[#words + 1] = w end
    return words
end

-- Best field a word was found in, and its score; nil when it is nowhere.
local function WordScore(f, w)
    if f.title:find(w, 1, true) then return "title", OS.SCORE.title end
    for _, t in ipairs(f.tags) do
        if t:find(w, 1, true) then return "tag", OS.SCORE.tag end
    end
    if f.who ~= "" and f.who:find(w, 1, true) then return "who", OS.SCORE.who end
    if f.body:find(w, 1, true) then return "body", OS.SCORE.body end
end

-- True when any of a note's tags contains w (a #tag prefix, ALL-69.2).
local function TagsMatch(f, w)
    for _, t in ipairs(f.tags) do
        if t:find(w, 1, true) then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- PREFIXES (ALL-69.2)
--------------------------------------------------------------------------------
-- A Reference Box attachment of this type ("quest", "item"...). Shared with
-- UI/Oracle.lua's result badges, which show the same thing.
function OS.HasAttachment(note, kind)
    for _, a in ipairs(note.attachments or {}) do
        if type(a) == "table" and a.type == kind then return true end
    end
    return false
end

-- The `i` filter: an item in the Reference Box, or an item link pasted
-- straight into the body.
function OS.HasItem(note)
    return OS.HasAttachment(note, "item")
        or (type(note.body) == "string" and note.body:find("|Hitem:", 1, true) ~= nil)
end

-- Item names a note carries, lower-case, one per line: links in the body
-- (cached in Fields) plus Reference Box items, which store only an id, so
-- ctx.itemName(id) names them (C_Item in WoW; nil while not cached yet).
-- Only built while the `i` prefix is on.
local function ItemNames(note, f, ctx)
    local names = f.items
    local getName = ctx and ctx.itemName
    if not getName then return names end
    for _, a in ipairs(note.attachments or {}) do
        if type(a) == "table" and a.type == "item" and a.id then
            local name = getName(a.id)
            if type(name) == "string" and name ~= "" then names = names .. "\n" .. name:lower() end
        end
    end
    return names
end

-- The `z` filter: a note that surfaces for a zone, instance or sub-zone
-- (Features/ContextNotes.lua), as opposed to a player/NPC note (p/n). An
-- instance type or rested counts as a place too (ALL-232 S4)
local function IsZoneContext(note)
    for _, ctx in ipairs(BNB.NoteSituations(note)) do
        local kind = ctx:match("^(%a+):")
        if kind == "zone" or kind == "instance" or kind == "subzone"
           or kind == "itype" or kind == "state" then return true end
    end
    return false
end

-- Start of the local day containing t (hour/min/sec zeroed).
local function DayStart(t)
    local d = dateFn("*t", t)
    d.hour, d.min, d.sec = 0, 0, 0
    return timeFn(d)
end

-- The [start, finish] epoch range a `d` argument means. now defaults to the
-- current time; tests pass one so results do not depend on the clock.
function OS.DateRange(spec, now)
    now = now or timeFn()
    if spec.kind == "today" then
        local s = DayStart(now)
        return s, s + DAY - 1
    elseif spec.kind == "yesterday" then
        local s = DayStart(now) - DAY
        return s, s + DAY - 1
    elseif spec.kind == "days" then
        return now - spec.n * DAY, now
    elseif spec.kind == "year" then
        local s = timeFn({ year = spec.year, month = 1, day = 1, hour = 0, min = 0, sec = 0 })
        local e = timeFn({ year = spec.year + 1, month = 1, day = 1, hour = 0, min = 0, sec = 0 }) - 1
        return s, e
    elseif spec.kind == "yearmonth" then
        local s = timeFn({ year = spec.year, month = spec.month, day = 1, hour = 0, min = 0, sec = 0 })
        local ny, nm = spec.year, spec.month + 1
        if nm > 12 then nm, ny = 1, ny + 1 end
        local e = timeFn({ year = ny, month = nm, day = 1, hour = 0, min = 0, sec = 0 }) - 1
        return s, e
    end
    return 0, now
end

-- Parses one `d` argument: a date keyword (localized via dateWords, English
-- by default), a bare number (days back), a year (2026) or a year-month
-- (2026-09). nil when arg is none of those, so the caller can leave `d`
-- unconsumed (falls back to a literal search word).
function OS.ParseDateArg(arg, dateWords)
    dateWords = dateWords or OS.DEFAULT_DATE_WORDS
    local kind = dateWords[arg:lower()]
    if kind == "today" or kind == "yesterday" then
        return { kind = kind }
    elseif kind == "week" then
        return { kind = "days", n = 7 }
    elseif kind == "month" then
        return { kind = "days", n = 30 }
    elseif kind == "year" then
        return { kind = "days", n = 365 }
    end
    -- Years outside 1970..2100 are never a year: time() returns nil before
    -- 1970 on Windows, which would crash DateRange. "d 1500" is days back.
    local yy, mm = arg:match("^(%d%d%d%d)%-(%d%d?)$")
    if yy then
        yy, mm = tonumber(yy), tonumber(mm)
        if yy < 1970 or yy > 2100 or mm < 1 or mm > 12 then return nil end
        return { kind = "yearmonth", year = yy, month = mm }
    end
    local y = tonumber(arg:match("^(%d%d%d%d)$"))
    if y and y >= 1970 and y <= 2100 then return { kind = "year", year = y } end
    local n = arg:match("^(%d+)$")
    if n then return { kind = "days", n = tonumber(n) } end
    return nil
end

-- Splits s into words (whitespace-separated) and "..." phrases, so a phrase
-- can hold spaces. { word = "..." } or { phrase = "..." } per token.
local function Tokenize(s)
    local tokens, i, n = {}, 1, #s
    while i <= n do
        local c = s:sub(i, i)
        if c:match("%s") then
            i = i + 1
        elseif c == '"' then
            local j = s:find('"', i + 1)
            if j then
                tokens[#tokens + 1] = { phrase = s:sub(i + 1, j - 1) }
                i = j + 1
            else
                tokens[#tokens + 1] = { word = s:sub(i + 1) }
                i = n + 1
            end
        else
            local j = s:find('[%s"]', i) or (n + 1)
            tokens[#tokens + 1] = { word = s:sub(i, j - 1) }
            i = j
        end
    end
    return tokens
end

-- Parses a whole Oracle query into { openAs, filters, date, tags, who,
-- favorites, exclude, phrases, words, help }.
--   opts.prefixes  letter -> role map (OS.DEFAULT_PREFIXES if omitted)
--   opts.dateWords keyword -> kind map (OS.DEFAULT_DATE_WORDS if omitted)
-- Leading "letter space" tokens are consumed left to right while they name a
-- role, combinable in any order; at most one open-as role sticks (a second
-- is left as a literal word). `?` alone means "show the prefix list".
function OS.ParseQuery(query, opts)
    opts = opts or {}
    local prefixes = opts.prefixes or OS.DEFAULT_PREFIXES
    local dateWords = opts.dateWords or OS.DEFAULT_DATE_WORDS

    local parsed = {
        openAs = nil, filters = {}, date = nil,
        tags = {}, who = {}, exclude = {}, phrases = {}, words = {},
        favorites = false, help = false,
    }

    local rest = query or ""
    if rest:match("^%s*(.-)%s*$") == "?" then
        parsed.help = true
        return parsed
    end

    -- Any leading token is looked up, not only an ASCII letter, so a locale
    -- may set a letter outside a-z; a token that is no prefix ends the run.
    while true do
        local letter, tail = rest:match("^%s*(%S+)%s+(.*)$")
        if not letter then break end
        local role = prefixes[letter:lower()]
        if not role then break end
        if role == "date" then
            local arg, tail2 = tail:match("^(%S+)%s*(.*)$")
            local spec = arg and OS.ParseDateArg(arg, dateWords)
            if not spec then break end
            parsed.date = spec
            rest = tail2
        elseif OS.OPEN_AS[role] then
            if parsed.openAs then break end
            parsed.openAs = role
            rest = tail
        else
            if parsed.filters[role] then break end
            parsed.filters[role] = true
            rest = tail
        end
    end

    for _, tok in ipairs(Tokenize(rest)) do
        if tok.phrase ~= nil then
            -- Body text has its whitespace runs collapsed (PlainText); match that.
            local p = tok.phrase:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
            if p ~= "" then parsed.phrases[#parsed.phrases + 1] = p:lower() end
        else
            local w = tok.word
            if w == "#" or w == "@" or w == "-" then
                -- A symbol typed on its own, its word still to come: ignored,
                -- so the list does not jump to notes containing a bare "-".
            elseif w == "*" then
                parsed.favorites = true
            elseif w:sub(1, 1) == "#" and #w > 1 then
                parsed.tags[#parsed.tags + 1] = w:sub(2):lower()
            elseif w:sub(1, 1) == "@" and #w > 1 then
                parsed.who[#parsed.who + 1] = w:sub(2):lower()
            elseif w:sub(1, 1) == "-" and #w > 1 then
                parsed.exclude[#parsed.exclude + 1] = w:sub(2):lower()
            elseif w ~= "" then
                parsed.words[#parsed.words + 1] = w:lower()
            end
        end
    end

    return parsed
end

-- True when note passes every filter/date/favourite check in parsed.
-- ctx.charScope: "char:<key>" for this character (the `c` filter).
-- ctx.now: epoch used for the `d` filter (defaults to the current time).
-- ctx.itemName(id): an item's name, for Reference Box items under `i`.
function OS.MatchesFilters(note, parsed, ctx)
    ctx = ctx or {}
    local f = parsed.filters
    if f.player and note.source ~= "inspect" then return false end
    if f.npc and note.source ~= "target" then return false end
    if f.item and not OS.HasItem(note) then return false end
    if f.zone and not IsZoneContext(note) then return false end
    if f.char and note.scope ~= ctx.charScope then return false end
    if f.global and not (note.scope == nil or note.scope == "global") then return false end
    if f.tasks and not (note.tasks and #note.tasks > 0) then return false end
    if f.alarm and note.alarm == nil then return false end
    if f.rich and note.richMode ~= true then return false end
    if f.plain and note.richMode == true then return false end
    if parsed.favorites and not (note.favorited or note.pinned) then return false end
    if parsed.date then
        local s, e = OS.DateRange(parsed.date, ctx.now)
        local c, u = note.created or 0, note.updated or 0
        if not ((c >= s and c <= e) or (u >= s and u <= e)) then return false end
    end
    return true
end

-- Moves a byte position off the middle of a UTF-8 character: forward for a
-- start, back for an end. A cut through a character draws a box in WoW.
local function CharStart(s, i)
    while i <= #s do
        local b = s:byte(i)
        if b < 0x80 or b >= 0xC0 then break end
        i = i + 1
    end
    return i
end
local function CharEnd(s, j)
    if j >= #s then return #s end
    local n = s:byte(j + 1)
    while j > 0 and n and n >= 0x80 and n < 0xC0 do
        j = j - 1
        n = s:byte(j + 1)
    end
    return j
end

-- One line of body text for a result: around the first word found in the
-- body, or the start of the body when none was.
function OS.Snippet(f, words)
    local plain = f.plain
    if plain == "" then return "" end
    local at
    for _, w in ipairs(words or {}) do
        local p = f.body:find(w, 1, true)
        if p and (not at or p < at) then at = p end
    end
    local i = 1
    if at and at > SNIPPET_BEFORE then i = CharStart(plain, at - SNIPPET_BEFORE) end
    local j = CharEnd(plain, i + SNIPPET_LEN - 1)
    local out = plain:sub(i, j)
    if i > 1 then out = "..." .. out end
    if j < #plain then out = out .. "..." end
    return out
end

-- Points for one boost at the level weights gives it (or its default).
function OS.WeightPoints(weights, key)
    local lvl = weights and weights[key]
    return OS.WEIGHT_POINTS[lvl] or OS.WEIGHT_POINTS[OS.WEIGHT_DEFAULTS[key]] or 0
end

-- 1 within RECENT_FULL of now, 0.5 within RECENT_HALF, else 0.
local function Recency(t, now)
    if type(t) ~= "number" then return 0 end
    local age = math.max(0, now - t)
    if age <= OS.RECENT_FULL then return 1 end
    if age <= OS.RECENT_HALF then return 0.5 end
    return 0
end

-- A note that surfaces where the player is now. zone = { kind = "zone" or
-- "instance", name = ..., sub = ... }, lower case (UI/Oracle.lua).
function OS.IsHereNote(note, zone)
    if not zone then return false end
    for _, ctx in ipairs(BNB.NoteSituations(note)) do
        local kind, value = ctx:match("^(%a+):(.+)$")
        if kind then
            value = value:lower()
            if kind == "subzone" then
                if zone.sub ~= nil and zone.sub ~= "" and value == zone.sub then return true end
            elseif kind == zone.kind and value == zone.name then
                return true
            end
        end
    end
    return false
end

-- A note about the current target, found the way Features/TargetNote.lua
-- and BNB.UnitNotes.FindPlayerNote find one. target = { name, realm,
-- isPlayer, npcID, isPet } (UI/Oracle.lua).
function OS.IsTargetNote(note, target)
    if not target or not target.name then return false end
    if target.isPlayer then
        local key = "player:" .. target.name
        local full = (target.realm and target.realm ~= "") and (key .. "-" .. target.realm) or key
        if note.targetPlayerKey == full or BNB.NoteHasSituation(note, full, true)
           or BNB.NoteHasSituation(note, key, true) then return true end
        return note.source == "inspect" and note.inspectName == target.name
            and (not note.inspectRealm or note.inspectRealm == "" or note.inspectRealm == target.realm)
    end
    if not target.npcID or note.targetNpcID == nil then return false end
    if tostring(note.targetNpcID) ~= tostring(target.npcID) then return false end
    -- Combat pets share a creature id: the name has to match too.
    return not target.isPet or note.title == target.name
end

-- The context boosts for one note (see OS.WEIGHT_KEYS). ctx.weights,
-- ctx.charScope, ctx.zone, ctx.target, ctx.now; no ctx = no boosts.
function OS.Boost(note, ctx)
    if not ctx then return 0 end
    local w, now = ctx.weights, ctx.now or timeFn()
    local b = 0
    if ctx.charScope and note.scope == ctx.charScope then b = b + OS.WeightPoints(w, "char") end
    if ctx.zone and OS.IsHereNote(note, ctx.zone) then b = b + OS.WeightPoints(w, "zone") end
    if note.favorited or note.pinned then b = b + OS.WeightPoints(w, "fav") end
    b = b + math.floor(OS.WeightPoints(w, "opened") * Recency(note.lastOpened, now))
    if ctx.target and OS.IsTargetNote(note, ctx.target) then b = b + OS.WeightPoints(w, "target") end
    b = b + math.floor(OS.WeightPoints(w, "edited") * Recency(note.updated, now))
    local a = note.alarm
    if type(a) == "table" and not a.fired then
        local t = a.snoozedUntil or a.time
        if type(t) == "number" and t >= now and t - now <= OS.ALARM_SOON then
            b = b + OS.WeightPoints(w, "alarm")
        end
    end
    return b
end

local function Newer(a, b)
    local ua, ub = a.note.updated or 0, b.note.updated or 0
    if ua ~= ub then return ua > ub end
    return (a.note.title or "") < (b.note.title or "")
end

-- Search notes (an array of note tables) for an already-parsed query
-- (OS.ParseQuery). #tag / @who / exclude / phrase all score and gate the
-- same way a plain word does (see WordScore), just against a narrower field
-- or with the test inverted.
--   opts.max  most results returned (default 8)
--   opts.ctx  passed through to OS.MatchesFilters (charScope, now) and
--             OS.Boost (weights, zone, target)
-- Returns an array of { note, score, snippet }, best first. A blank query
-- scores the boosts alone, so it lists the notes that matter here and now,
-- newest first among equals.
function OS.SearchParsed(notes, parsed, opts)
    local max = (opts and opts.max) or 8
    local ctx = opts and opts.ctx
    local words = parsed.words
    local hits = {}
    local whole = table.concat(words, " ")
    for _, note in ipairs(notes or {}) do
        if OS.MatchesFilters(note, parsed, ctx) then
            local f = Fields(note)
            local score, ok = 0, true
            -- Under `i` a word found in an item's name ranks like the title.
            local items = parsed.filters.item and ItemNames(note, f, ctx) or nil
            for _, w in ipairs(words) do
                local _, s = WordScore(f, w)
                if items and items ~= "" and items:find(w, 1, true) then
                    s = math.max(s or 0, OS.SCORE.item)
                end
                if not s then ok = false; break end
                score = score + s
            end
            if ok then
                for _, t in ipairs(parsed.tags) do
                    if not TagsMatch(f, t) then ok = false; break end
                    score = score + OS.SCORE.tag
                end
            end
            if ok then
                for _, w in ipairs(parsed.who) do
                    if f.about == "" or not f.about:find(w, 1, true) then ok = false; break end
                    score = score + OS.SCORE.who
                end
            end
            if ok then
                for _, w in ipairs(parsed.exclude) do
                    local _, s = WordScore(f, w)
                    if s then ok = false; break end
                end
            end
            if ok then
                for _, p in ipairs(parsed.phrases) do
                    local _, s = WordScore(f, p)
                    if not s then ok = false; break end
                    score = score + s
                end
            end
            if ok then
                if whole ~= "" then
                    if f.title == whole then score = score + OS.TITLE_EXACT_BONUS
                    elseif f.title:sub(1, #whole) == whole then score = score + OS.TITLE_PREFIX_BONUS end
                end
                score = score + OS.Boost(note, ctx)
                hits[#hits + 1] = { note = note, score = score, f = f }
            end
        end
    end
    table.sort(hits, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return Newer(a, b)
    end)
    local snippetWords = words
    if #parsed.phrases > 0 then
        snippetWords = {}
        for i, w in ipairs(words) do snippetWords[i] = w end
        for _, p in ipairs(parsed.phrases) do snippetWords[#snippetWords + 1] = p end
    end
    local out = {}
    for i = 1, math.min(max, #hits) do
        local h = hits[i]
        out[i] = { note = h.note, score = h.score, snippet = OS.Snippet(h.f, snippetWords) }
    end
    return out
end

-- Search notes for a raw query string: OS.ParseQuery then OS.SearchParsed.
-- opts is shared by both (prefixes, dateWords, ctx, max).
function OS.Search(notes, query, opts)
    return OS.SearchParsed(notes, OS.ParseQuery(query, opts), opts)
end

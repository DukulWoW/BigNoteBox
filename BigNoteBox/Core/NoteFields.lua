-- BigNoteBox Core/NoteFields.lua
-- The one list of saved note fields (CMP-01, ALL-136.5).
--
-- Copy, history snapshots, the JSON backup, share strings, Direct Send and
-- every import read this list, so a new note field is one line here. Before
-- it, each of them kept its own hand-written field list, and each list missed
-- a different set (backups lost tasks, shares lost the icon frame).
--
-- Columns:
--   [1] key
--   [2] types an import accepts: s string, n number, b boolean, t table
--   share    = Share window group (BNB.SHARE_GROUPS); "text" is always sent;
--              nil = never shared (this player's own: scope, pin, alarm...)
--   nocopy   = a copy and a history snapshot leave it out
--   internal = never backed up or shared either (implies nocopy)
--
-- Loads before Core/NoteManager.lua, with no dependencies, so the luajit tools
-- in _work/tools can load it on its own.

local BNB = BigNoteBox

-- Share window checkboxes, in display order (ALL-179). Title, body and rich
-- mode ("text") are always sent and have no checkbox.
BNB.SHARE_GROUPS = {
    { key = "tags",      label = "SHARE_GRP_TAGS",      tip = "SHARE_GRP_TAGS_TIP" },
    { key = "tasks",     label = "SHARE_GRP_TASKS",     tip = "SHARE_GRP_TASKS_TIP" },
    { key = "refbox",    label = "SHARE_GRP_REFBOX",    tip = "SHARE_GRP_REFBOX_TIP" },
    { key = "look",      label = "SHARE_GRP_LOOK",      tip = "SHARE_GRP_LOOK_TIP" },
    { key = "situation", label = "SHARE_GRP_SITUATION", tip = "SHARE_GRP_SITUATION_TIP" },
    { key = "unit",      label = "SHARE_GRP_UNIT",      tip = "SHARE_GRP_UNIT_TIP" },
}

local FIELDS = {
    -- Text: always shared
    { "title",       "s", share = "text" },
    { "body",        "s", share = "text" },
    { "richMode",    "b", share = "text" },
    { "tags",        "t", share = "tags" },
    { "tasks",       "t", share = "tasks" },
    { "taskList",    "t", share = "tasks" },
    { "attachments", "t", share = "refbox" },
    -- Look
    { "icon",             "s", share = "look" },
    { "iconSource",       "s", share = "look" },
    { "iconFrame",        "s", share = "look" },
    { "titleColor",       "t", share = "look" },
    { "fontOverride",     "s", share = "look" },
    { "fontSize",         "n", share = "look" },
    { "textAlign",        "s", share = "look" },
    { "fontOutline",      "s", share = "look" },
    { "borderOverride",   "s", share = "look" },
    { "borderScale",      "n", share = "look" },
    { "borderOffset",     "n", share = "look" },
    { "borderBrightness", "n", share = "look" },
    { "lineHeight",       "sn", share = "look" },
    -- Situation: where the note pops up, and its waypoint
    { "context",        "s", share = "situation" },
    { "contextDisplay", "s", share = "situation" },
    { "contextLeave",   "s", share = "situation" },
    { "waypoint",       "t", share = "situation" },
    { "wpClearOnLeave", "b", share = "situation" },
    -- Unit: who a target or inspect note is about (model viewer, Oracle
    -- badges, the "note already exists" lookup)
    { "source",                     "s",  share = "unit" },
    { "targetNpcID",                "sn", share = "unit" },
    { "targetPlayerKey",            "s",  share = "unit" },
    { "targetIsPet",                "b",  share = "unit" },
    { "targetFaction",              "s",  share = "unit" },
    { "targetClassification",       "s",  share = "unit" },
    { "targetAttackable",           "b",  share = "unit" },
    { "targetDisplayID",            "n",  share = "unit" },
    { "inspectName",                "s",  share = "unit" },
    { "inspectRealm",               "s",  share = "unit" },
    { "inspectFaction",             "s",  share = "unit" },
    { "inspectRaceID",              "n",  share = "unit" },
    { "inspectSexID",               "n",  share = "unit" },
    { "inspectGearItems",           "t",  share = "unit" },
    { "inspectTransmogItems",       "t",  share = "unit" },
    { "inspectTransmogAppearances", "t",  share = "unit" },
    -- This player's own: backed up, never shared (review question 6: the
    -- receiver's sidebar picks the scope, and an alarm is personal)
    { "scope",     "s" },
    { "pinned",    "b" },
    { "favorited", "b" },
    { "locked",    "b" },
    { "alarm",     "t", nocopy = true },   -- a copy would ring twice
    -- When and where the note was made
    { "created",    "n", nocopy = true },
    { "updated",    "n", nocopy = true },
    { "coordX",     "n", nocopy = true },
    { "coordY",     "n", nocopy = true },
    { "coordMapID", "n", nocopy = true },
    { "coordZone",  "s", nocopy = true },
    -- Internal: identity, edit history, bookkeeping
    { "id",             "s", internal = true },
    { "history",        "t", internal = true },
    { "manualSnapshot", "t", internal = true },
    { "lastOpened",     "n", internal = true },
    { "updatedAt",      "n", internal = true },
    { "deletedAt",      "n", internal = true },
}

BNB.NOTE_FIELDS = {}   -- ordered definitions
BNB.NOTE_FIELD  = {}   -- key -> definition
for _, e in ipairs(FIELDS) do
    local def = {
        key = e[1], types = e[2], share = e.share,
        internal = e.internal or nil,
        nocopy   = (e.nocopy or e.internal) or nil,
    }
    BNB.NOTE_FIELDS[#BNB.NOTE_FIELDS + 1] = def
    BNB.NOTE_FIELD[def.key] = def
end

--------------------------------------------------------------------------------
-- CLEANING IMPORTED FIELDS
-- Everything that comes from outside (a JSON file, a share string, a Direct
-- Send message) goes through BNB.CleanNoteFields before it reaches a note.
--------------------------------------------------------------------------------
local TYPE_LETTER = { string = "s", number = "n", boolean = "b", table = "t" }

-- Deep copy that keeps only plain data (no functions) and stops at a sane depth
local function CopyData(v, depth)
    local tv = type(v)
    if tv ~= "table" then
        if tv == "string" or tv == "number" or tv == "boolean" then return v end
        return nil
    end
    if depth > 8 then return nil end
    local t = {}
    for k, val in pairs(v) do
        local tk = type(k)
        if tk == "string" or tk == "number" then
            t[k] = CopyData(val, depth + 1)
        end
    end
    return t
end

-- Keeps the array items that pass ok(item). An empty list stays an empty
-- list; a list that had items but none valid becomes nil.
local function FilterArray(arr, ok)
    local out = {}
    for _, item in ipairs(arr) do
        if ok(item) then out[#out + 1] = item end
    end
    if #out == 0 and next(arr) ~= nil then return nil end
    return out
end

local function IsTable(v) return type(v) == "table" end

-- Shape checks for the table fields: a value that does not fit is dropped
-- (returns nil) rather than reaching code that expects the real shape. The
-- old share format turned nested tables into the string "null", for example.
local SHAPES = {
    tags = function(v)
        local out = {}
        for _, tag in ipairs(v) do
            if type(tag) == "string" and tag ~= "" then out[#out + 1] = tag end
        end
        return out
    end,
    tasks = function(v)
        return FilterArray(v, function(t) return IsTable(t) and type(t.text) == "string" end)
    end,
    attachments = function(v)
        return FilterArray(v, function(a)
            return IsTable(a) and type(a.type) == "string" and a.id ~= nil
        end)
    end,
    inspectGearItems     = function(v) return FilterArray(v, IsTable) end,
    inspectTransmogItems = function(v) return FilterArray(v, IsTable) end,
    titleColor = function(v)
        if type(v.r) == "number" and type(v.g) == "number" and type(v.b) == "number" then return v end
    end,
    waypoint = function(v)
        if type(v.mapID) == "number" and type(v.x) == "number" and type(v.y) == "number" then return v end
    end,
}

-- Returns a new table with the fields of src that are in the schema, have an
-- accepted type and shape, and pass want(def) (nil = every non-internal
-- field). Tables are deep copies, so the result shares nothing with src.
function BNB.CleanNoteFields(src, want)
    local out = {}
    if type(src) ~= "table" then return out end
    for _, def in ipairs(BNB.NOTE_FIELDS) do
        local v = src[def.key]
        local letter = v ~= nil and TYPE_LETTER[type(v)]
        if letter and def.types:find(letter, 1, true)
           and not def.internal and (not want or want(def)) then
            v = CopyData(v, 1)
            if type(v) == "table" and SHAPES[def.key] then v = SHAPES[def.key](v) end
            -- WoW fonts have no tab glyph (drawn as a box, ALL-196) and the
            -- editor cannot type one, so a tab from outside becomes 4 spaces
            if (def.key == "body" or def.key == "title") and type(v) == "string" then
                v = v:gsub("\t", "    ")
            end
            out[def.key] = v
        end
    end
    return out
end

-- BigNoteBox Features/NoteTemplates.lua
-- Note templates (ALL-68). A template is the shareable part of a note
-- (text, tags, tasks, look, an optional situation), never scope, pin, alarm,
-- unit or coords. S1: the 12 built-ins, picked in the New Note dialog
-- (UI/NewNoteDialog.lua: 5 cards, the rest on its More page). S2 adds the
-- player's own (BigNoteBoxNotesDB.templates), S3 sharing.
--
-- Built-ins live here with their text in L keys, read-only. Body text is rich
-- markup; a plain note gets it with the markup stripped (AM.StripMarkup).
-- Snapshot tokens ({{date}}, {{zone}}, {{instance}}, {{target}}...,
-- Features/Tokens.lua) are filled when the note is made; one with no value
-- right then is left out. Live tokens ({{me}}) stay in the text.
--
-- Fields of a template:
--   key       id ("boss"); art = the card picture name (Assets/Templates/tmp-<art>)
--   name/desc L keys (card label, tooltip, the line under the cards)
--   icon      note icon; color = title colour { r, g, b } or nil
--   title     L key, may hold snapshot tokens; a token with no value falls
--             back to the name
--   body      L key, rich markup
--   tags      L key, tags separated by ","
--   tasks     L key, one task per line; reset = "daily" / "weekly" (the
--             task list's own reset, Features/TaskManager.lua)
--   situation "instance" = the instance the player is in when it is made
--
-- The player's own templates (S2) live in BigNoteBoxNotesDB.templates
-- ([id] = record), so they go wherever the notes go (dev mode set, Factory
-- Reset). A record:
--   name, desc  the player's words (desc may be nil)
--   icon        the template's own icon, picked in the save window: its row
--               and the note made from it (nil = the saved note icon)
--   fields      note fields as saved (BNB.CleanNoteFields: text always, the
--               ticked share groups, never unit / scope / pin / alarm)
--   groups      the ticked share groups ({ tags = true, ... }), reused by
--               Replace from current note
--   instance    true = the instance the player is in when it is made (a
--               duplicated Boss / Dungeon built-in)
--   created, updated
-- Ids start with "u", so they never meet a built-in key. Tasks are copied as
-- saved, ticks included (Dukul, 2026-10-17), with new task ids per note.
-- Every change sends TemplatesChanged ().
--
-- Public API:
--   BNB.Templates.Get(key)            -> template or nil ("blank" = nil); a
--                                        user template comes back as a view:
--                                        { key, user = true, rec, icon, color }
--   BNB.Templates.QUICK               -> card keys in the New Note dialog
--   BNB.Templates.More()              -> the built-ins on the More page
--   BNB.Templates.All()               -> every built-in, in list order
--   BNB.Templates.User()              -> the player's templates, by name
--   BNB.Templates.Name(tpl) / Desc(tpl) -> display text, built-in or user
--   BNB.Templates.Rich(tpl)           -> a note made from it starts rich
--   BNB.Templates.Title(tpl)          -> suggested title, tokens filled
--   BNB.Templates.Fill(id, tpl, rich, own) -> the template onto a new note;
--                                        own = fields the dialog wrote itself
--   BNB.Templates.SaveFromNote(noteID, name, desc, groups, icon) -> id
--   BNB.Templates.ReplaceFromNote(id, noteID)
--   BNB.Templates.Rename(id, name) / SetDesc(id, desc) / Delete(id)
--   BNB.Templates.Duplicate(key)      -> new id (a built-in becomes the player's)
--   BNB.Templates.SAVE_GROUPS         -> the share groups a template can hold
--   BNB.Templates.SetIcon(id, icon)
--   BNB.Templates.Preview(tpl)        -> tooltip lines: start of the body,
--                                        tags, task count
-- Sharing and backup (S3):
--   BNB.Templates.Encode(key)         -> share code "BNBT1:..." (a built-in
--                                        goes out as a player's template)
--   BNB.Templates.TryImport(str)      -> handled, message, ok; handled = it
--                                        was a template code (adds it)
--   BNB.Templates.BackupList()        -> records for the JSON backup
--   BNB.Templates.ImportRecords(list) -> how many were added (a template
--                                        already here, same id, is skipped)

local BNB = BigNoteBox
if not BNB then return end
local L = BNB.L

local TPL = {}
BNB.Templates = TPL

local ICONS = "Interface\\Icons\\"

-- Palette colours (BNB.COLOR_PALETTE), so the dialog's swatch ring finds them
local CARDINAL = { r = 0.769, g = 0.118, b = 0.227 }
local MIKADO   = { r = 1.000, g = 0.788, b = 0.055 }
local BONE     = { r = 0.937, g = 0.894, b = 0.690 }
local BEL_AIR  = { r = 0.000, g = 0.635, b = 0.910 }
local BABYLON  = { r = 0.133, g = 0.694, b = 0.298 }
local PHEASANT = { r = 0.725, g = 0.478, b = 0.341 }
local NEPTUNE  = { r = 0.439, g = 0.573, b = 0.745 }

local LIST = {
    { key = "boss", art = "boss", icon = ICONS .. "INV_Misc_Head_Dragon_01", color = CARDINAL,
      title = "TPL_BOSS_TITLE", body = "TPL_BOSS_BODY", tags = "TPL_BOSS_TAGS",
      situation = "instance" },
    { key = "dungeon", icon = ICONS .. "INV_Misc_Map_01", color = BEL_AIR,
      title = "TPL_DUNGEON_TITLE", body = "TPL_DUNGEON_BODY", tags = "TPL_DUNGEON_TAGS",
      situation = "instance" },
    { key = "weekly", art = "weekly", icon = ICONS .. "INV_Scroll_03", color = MIKADO,
      title = "TPL_WEEKLY_TITLE", body = "TPL_WEEKLY_BODY", tags = "TPL_WEEKLY_TAGS",
      tasks = "TPL_WEEKLY_TASKS", reset = "weekly" },
    { key = "daily", icon = ICONS .. "INV_Misc_PocketWatch_01", color = BONE,
      title = "TPL_DAILY_TITLE", body = "TPL_DAILY_BODY", tags = "TPL_DAILY_TAGS",
      tasks = "TPL_DAILY_TASKS", reset = "daily" },
    { key = "farming", icon = ICONS .. "INV_Pick_02", color = PHEASANT,
      title = "TPL_FARMING_TITLE", body = "TPL_FARMING_BODY", tags = "TPL_FARMING_TAGS" },
    { key = "collection", icon = ICONS .. "Ability_Mount_RidingHorse", color = BABYLON,
      title = "TPL_COLLECTION_TITLE", body = "TPL_COLLECTION_BODY", tags = "TPL_COLLECTION_TAGS",
      tasks = "TPL_COLLECTION_TASKS" },
    { key = "crafting", icon = ICONS .. "Trade_BlackSmithing", color = PHEASANT,
      title = "TPL_CRAFTING_TITLE", body = "TPL_CRAFTING_BODY", tags = "TPL_CRAFTING_TAGS",
      tasks = "TPL_CRAFTING_TASKS" },
    { key = "player", icon = ICONS .. "INV_Misc_GroupNeedMore", color = NEPTUNE,
      title = "TPL_PLAYER_TITLE", body = "TPL_PLAYER_BODY", tags = "TPL_PLAYER_TAGS" },
    { key = "guide", icon = ICONS .. "INV_Scroll_05", color = BONE,
      title = "TPL_GUIDE_TITLE", body = "TPL_GUIDE_BODY", tags = "TPL_GUIDE_TAGS",
      tasks = "TPL_GUIDE_TASKS" },
    { key = "alts", icon = ICONS .. "INV_Misc_Coin_02", color = MIKADO,
      title = "TPL_ALTS_TITLE", body = "TPL_ALTS_BODY", tags = "TPL_ALTS_TAGS" },
    { key = "raidnight", icon = ICONS .. "Ability_Warrior_BattleShout", color = CARDINAL,
      title = "TPL_RAIDNIGHT_TITLE", body = "TPL_RAIDNIGHT_BODY", tags = "TPL_RAIDNIGHT_TAGS",
      tasks = "TPL_RAIDNIGHT_TASKS" },
    { key = "journal", art = "diary", icon = ICONS .. "INV_Misc_Note_02", color = nil,
      title = "TPL_JOURNAL_TITLE", body = "TPL_JOURNAL_BODY", tags = "TPL_JOURNAL_TAGS" },
}

local BY_KEY = {}
for _, t in ipairs(LIST) do
    t.name = "TPL_" .. t.key:upper() .. "_NAME"
    t.desc = "TPL_" .. t.key:upper() .. "_DESC"
    BY_KEY[t.key] = t
end

-- The New Note dialog's cards, left to right (Dukul, 2026-10-17)
TPL.QUICK = { "blank", "boss", "weekly", "journal", "more" }

-- The player's templates table, made on first write
local function Store(create)
    local ndb = BNB.NotesDB and BNB.NotesDB()
    if not ndb then return nil end
    if not ndb.templates and create then ndb.templates = {} end
    return ndb.templates
end

local function Rec(id)
    local s = Store()
    return id and s and s[id] or nil
end

local function View(id, rec)
    local f = rec.fields or {}
    return { key = id, user = true, rec = rec, icon = rec.icon or f.icon, color = f.titleColor }
end

function TPL.Get(key)
    if not key then return nil end
    if BY_KEY[key] then return BY_KEY[key] end
    local rec = Rec(key)
    return rec and View(key, rec) or nil
end

function TPL.All() return LIST end

function TPL.User()
    local out = {}
    for id, rec in pairs(Store() or {}) do out[#out + 1] = View(id, rec) end
    table.sort(out, function(a, b)
        local na, nb = (a.rec.name or ""):lower(), (b.rec.name or ""):lower()
        if na ~= nb then return na < nb end
        return a.key < b.key
    end)
    return out
end

function TPL.Name(tpl)
    if not tpl then return L["TPL_BLANK_NAME"] end
    if tpl.user then return tpl.rec.name or "" end
    return L[tpl.name]
end

function TPL.Desc(tpl)
    if not tpl then return L["TPL_BLANK_DESC"] end
    if tpl.user then
        local d = tpl.rec.desc
        if d and d ~= "" then return d end
        return L["TPL_USER_NO_DESC"]
    end
    return L[tpl.desc]
end

function TPL.Rich(tpl)
    if not BNB.RichEnabled() then return false end
    if tpl and tpl.user then return tpl.rec.fields and tpl.rec.fields.richMode == true or false end
    return true
end

-- Every built-in not on a quick card, in list order
function TPL.More()
    local quick, out = {}, {}
    for _, k in ipairs(TPL.QUICK) do quick[k] = true end
    for _, t in ipairs(LIST) do
        if not quick[t.key] then out[#out + 1] = t end
    end
    return out
end

-- One line per entry, blank lines and spaces around dropped
local function Lines(text, sep)
    local out = {}
    for part in (text or ""):gmatch("[^" .. sep .. "]+") do
        part = part:match("^%s*(.-)%s*$")
        if part ~= "" then out[#out + 1] = part end
    end
    return out
end

function TPL.Title(tpl)
    if not tpl then return "" end
    local raw
    if tpl.user then raw = tpl.rec.fields and tpl.rec.fields.title or "" else raw = L[tpl.title] end
    if raw == "" then return TPL.Name(tpl) end
    local Tk = BNB.Tokens
    local filled = Tk and Tk.Snapshot(raw) or raw
    if Tk and Tk.HasSnapshot(filled) then return TPL.Name(tpl) end
    return filled
end

-- The body as the new note gets it: rich markup, or stripped for a plain
-- note; tasks written into the text when the Tasks module is off
local function Body(tpl, rich)
    local body = L[tpl.body]
    if not rich then
        local AM = BNB.AdvancedMode
        body = AM and AM.StripMarkup and AM.StripMarkup(body) or body
    end
    if tpl.tasks and not BNB.TasksEnabled() then
        local list = {}
        for _, line in ipairs(Lines(L[tpl.tasks], "\n")) do list[#list + 1] = "- " .. line end
        body = body .. "\n\n" .. table.concat(list, "\n")
    end
    return BNB.Tokens and BNB.Tokens.Snapshot(body, true) or body
end

-- Fills a note just made (CreateNote) from a template: body, tags, tasks with
-- their reset, the situation. The dialog's own picks (title, icon, colour,
-- font, rich) are written by the dialog.
-- The instance the player is in now, as a situation list, or nil
local function InstanceSituation()
    if not (BNB.SituationsEnabled() and BNB.GetCurrentZone) then return nil end
    local kind, name = BNB.GetCurrentZone()
    if kind == "instance" and name and name ~= "" then return { "instance:" .. name } end
    return nil
end

local function Snap(text)
    if type(text) ~= "string" then return text end
    return BNB.Tokens and BNB.Tokens.Snapshot(text, true) or text
end

-- Copied tasks get new ids (a sub-task follows its parent), so two notes
-- made from one template never share a task id (Not again today keys on it)
local function CopyTasks(tasks)
    local map, out = {}, {}
    for _, t in ipairs(tasks) do map[t.id or ""] = BNB.GenerateID() end
    for i, t in ipairs(tasks) do
        local c = BNB.DeepCopy(t)
        c.id = map[t.id or ""]
        if t.parentID then c.parentID = map[t.parentID] end
        c.text = Snap(c.text)
        out[i] = c
    end
    return out
end

-- A player's template onto a new note: every saved field the dialog did not
-- write itself (own), the body stripped for a plain note, tokens filled
local function FillUser(id, rec, rich, own)
    local f, updates = rec.fields or {}, {}
    own = own or {}
    for k, v in pairs(f) do
        if k ~= "title" and k ~= "richMode" and own[k] == nil then updates[k] = BNB.DeepCopy(v) end
    end
    local body = f.body or ""
    if f.richMode and not rich then
        local AM = BNB.AdvancedMode
        body = AM and AM.StripMarkup and AM.StripMarkup(body) or body
    end
    updates.body = Snap(body)
    if updates.tldr then updates.tldr = BNB.CleanTldr(Snap(updates.tldr)) end
    if type(f.tasks) == "table" then updates.tasks = CopyTasks(f.tasks) end
    if rec.instance then updates.situations = InstanceSituation() or updates.situations end
    BNB.UpdateNote(id, updates)
end

function TPL.Fill(id, tpl, rich, own)
    if not (id and tpl) then return end
    if tpl.user then return FillUser(id, tpl.rec, rich, own) end
    local updates = { body = Body(tpl, rich) }
    local tags = Lines(L[tpl.tags], ",")
    if #tags > 0 then updates.tags = tags end
    if tpl.situation == "instance" then updates.situations = InstanceSituation() end
    BNB.UpdateNote(id, updates)

    local T = BNB.Task
    if tpl.tasks and T and BNB.TasksEnabled() then
        if tpl.reset then T.UpdateList(id, { resetType = tpl.reset }) end
        for _, line in ipairs(Lines(L[tpl.tasks], "\n")) do
            T.AddTask(id, BNB.Tokens and BNB.Tokens.Snapshot(line, true) or line)
        end
    end
end

--------------------------------------------------------------------------------
-- THE PLAYER'S TEMPLATES (S2)
--------------------------------------------------------------------------------
-- The share groups a template can hold, in the Share window's order: every
-- group but unit (who a note is about belongs to that note)
TPL.SAVE_GROUPS = {}
for _, g in ipairs(BNB.SHARE_GROUPS) do
    if g.key ~= "unit" then TPL.SAVE_GROUPS[#TPL.SAVE_GROUPS + 1] = g end
end

local function Changed() BNB.SendMessage("TemplatesChanged") end

local function CleanName(s)
    s = (s or ""):gsub("[\r\n\t]", " "):match("^%s*(.-)%s*$")
    return s
end

-- The note's text plus the ticked groups, never unit
local function FieldsOf(note, groups)
    return BNB.CleanNoteFields(note, function(def)
        return def.share == "text"
            or (def.share ~= nil and def.share ~= "unit" and groups[def.share] == true)
    end)
end

local function CopyGroups(groups)
    local out = {}
    for _, g in ipairs(TPL.SAVE_GROUPS) do
        if groups and groups[g.key] then out[g.key] = true end
    end
    return out
end

function TPL.SaveFromNote(noteID, name, desc, groups, icon)
    local note = BNB.GetNote(noteID)
    name = CleanName(name)
    if not note or name == "" then return nil end
    local s = Store(true)
    if not s then return nil end
    groups = CopyGroups(groups)
    local id = "u" .. BNB.GenerateID()
    local now = time()
    desc = CleanName(desc)
    s[id] = { name = name, desc = desc ~= "" and desc or nil, icon = icon, fields = FieldsOf(note, groups),
              groups = groups, created = now, updated = now }
    Changed()
    return id
end

function TPL.ReplaceFromNote(id, noteID)
    local rec, note = Rec(id), BNB.GetNote(noteID)
    if not (rec and note) then return false end
    rec.fields  = FieldsOf(note, rec.groups or {})
    rec.instance = nil   -- the note's own situations now, if any were saved
    rec.updated = time()
    Changed()
    return true
end

function TPL.Rename(id, name)
    local rec = Rec(id)
    name = CleanName(name)
    if not rec or name == "" then return false end
    rec.name, rec.updated = name, time()
    Changed()
    return true
end

function TPL.SetDesc(id, desc)
    local rec = Rec(id)
    if not rec then return false end
    desc = CleanName(desc)
    rec.desc, rec.updated = desc ~= "" and desc or nil, time()
    Changed()
    return true
end

function TPL.Delete(id)
    local s = Store()
    if not (s and s[id]) then return end
    s[id] = nil
    Changed()
end

-- A built-in as the player's own record: rich body, tasks as real tasks
local function FromBuiltin(t)
    local f = { title = L[t.title], body = L[t.body], richMode = true, icon = t.icon }
    if t.color then f.titleColor = { r = t.color.r, g = t.color.g, b = t.color.b } end
    local groups = { look = true }
    local tags = Lines(L[t.tags], ",")
    if #tags > 0 then f.tags = tags; groups.tags = true end
    if t.tasks then
        f.tasks = {}
        for i, line in ipairs(Lines(L[t.tasks], "\n")) do
            f.tasks[i] = { id = BNB.GenerateID(), text = line, completed = false, order = i,
                           resetType = t.reset }
        end
        if t.reset then f.taskList = { resetType = t.reset } end
        groups.tasks = true
    end
    if t.situation then groups.situation = true end
    return f, groups, t.situation == "instance" or nil
end

function TPL.Duplicate(key)
    local tpl = TPL.Get(key)
    if not tpl then return nil end
    local s = Store(true)
    if not s then return nil end
    local rec
    if tpl.user then
        rec = BNB.DeepCopy(tpl.rec)
        rec.name = string.format(L["TPL_COPY_FMT"], tpl.rec.name or "")
    else
        local f, groups, inst = FromBuiltin(tpl)
        rec = { name = L[tpl.name], desc = L[tpl.desc], icon = tpl.icon, fields = f, groups = groups, instance = inst }
    end
    local now = time()
    rec.created, rec.updated = now, now
    local id = "u" .. BNB.GenerateID()
    s[id] = rec
    Changed()
    return id
end

function TPL.SetIcon(id, icon)
    local rec = Rec(id)
    if not rec then return false end
    rec.icon, rec.updated = icon, time()
    Changed()
    return true
end

--------------------------------------------------------------------------------
-- PREVIEW (tooltips on the More page, the cards and the Settings rows)
--------------------------------------------------------------------------------
local PREVIEW_LINES, PREVIEW_CHARS = 4, 60

function TPL.Preview(tpl)
    if not tpl then return {} end
    local body, rich, tags, tasks
    if tpl.user then
        local f = tpl.rec.fields or {}
        body, rich, tags = f.body or "", f.richMode, f.tags or {}
        tasks = type(f.tasks) == "table" and #f.tasks or 0
    else
        body, rich, tags = L[tpl.body], true, Lines(L[tpl.tags], ",")
        tasks = tpl.tasks and #Lines(L[tpl.tasks], "\n") or 0
    end
    local AM = BNB.AdvancedMode
    if rich and AM and AM.StripMarkup then body = AM.StripMarkup(body) end
    local out = {}
    for _, line in ipairs(Lines(body, "\n")) do
        if #out >= PREVIEW_LINES then out[#out + 1] = "..."; break end
        if #line > PREVIEW_CHARS then line = line:sub(1, PREVIEW_CHARS) .. "..." end
        out[#out + 1] = line
    end
    if #tags > 0 then out[#out + 1] = string.format(L["TPL_PREVIEW_TAGS_FMT"], table.concat(tags, ", ")) end
    if tasks > 0 then out[#out + 1] = string.format(L["TPL_PREVIEW_TASKS_FMT"], tasks) end
    return out
end

--------------------------------------------------------------------------------
-- SHARING AND BACKUP (S3)
-- A template code is "BNBT1:" + LibDeflate print encoding of a LibSerialize
-- payload { v = 1, kind = "template", tpl = record }; the note codes are
-- "BNB1:" / "BNB2:", so no reader of those takes one for a note. Whatever
-- comes in, a code or a backup, goes through CleanRecord: plain strings, the
-- known groups, share fields only (BNB.CleanNoteFields, never unit).
--------------------------------------------------------------------------------
local SHARE_PREFIX = "BNBT1:"
local NAME_MAX, DESC_MAX = 60, 80

local function Str(v, max)
    if type(v) ~= "string" then return nil end
    v = CleanName(v)
    if v == "" then return nil end
    return v:sub(1, max)
end

local function CleanRecord(raw)
    if type(raw) ~= "table" then return nil end
    local name = Str(raw.name, NAME_MAX)
    if not name or type(raw.fields) ~= "table" then return nil end
    local fields = BNB.CleanNoteFields(raw.fields, function(def)
        return def.share ~= nil and def.share ~= "unit"
    end)
    local icon = raw.icon
    if type(icon) ~= "string" and type(icon) ~= "number" then icon = nil end
    local groups = CopyGroups(type(raw.groups) == "table" and raw.groups or nil)
    for k in pairs(groups) do if raw.groups[k] ~= true then groups[k] = nil end end
    local now = time()
    return { name = name, desc = Str(raw.desc, DESC_MAX), icon = icon, fields = fields, groups = groups,
             instance = raw.instance == true or nil,
             created = tonumber(raw.created) or now, updated = tonumber(raw.updated) or now }
end

-- The record to send: a player's as saved, a built-in as Duplicate makes it
local function OutRecord(tpl)
    if tpl.user then return BNB.DeepCopy(tpl.rec) end
    local f, groups, inst = FromBuiltin(tpl)
    return { name = L[tpl.name], desc = L[tpl.desc], icon = tpl.icon, fields = f, groups = groups,
             instance = inst }
end

function TPL.Encode(key)
    local tpl = TPL.Get(key)
    local ls = LibStub and LibStub("LibSerialize", true)
    local ld = BNB.GetDeflate and BNB.GetDeflate()
    if not (tpl and ls and ld) then return nil, L["TPL_SHARE_ERR"] end
    local rec = OutRecord(tpl)
    rec.created, rec.updated = nil, nil
    local ok, serialized = pcall(ls.Serialize, ls, { v = 1, kind = "template", tpl = rec })
    if not ok or not serialized then return nil, L["TPL_SHARE_ERR"] end
    return SHARE_PREFIX .. ld:EncodeForPrint(ld:CompressDeflate(serialized))
end

local function Decode(str)
    local ls = LibStub and LibStub("LibSerialize", true)
    local ld = BNB.GetDeflate and BNB.GetDeflate()
    if not (ls and ld) then return nil end
    local compressed = ld:DecodeForPrint(str:sub(#SHARE_PREFIX + 1))
    local serialized = compressed and ld:DecompressDeflate(compressed)
    if not serialized then return nil end
    local ok, payload = ls:Deserialize(serialized)
    if not ok or type(payload) ~= "table" or payload.kind ~= "template" then return nil end
    return CleanRecord(payload.tpl)
end

function TPL.TryImport(str)
    if type(str) ~= "string" then return false end
    str = str:match("^%s*(.-)%s*$")
    if str:sub(1, #SHARE_PREFIX) ~= SHARE_PREFIX then return false end
    local rec = Decode(str)
    local s = rec and Store(true)
    if not s then return true, L["TPL_IMPORT_ERR"], false end
    local now = time()
    rec.created, rec.updated = now, now
    s["u" .. BNB.GenerateID()] = rec
    Changed()
    return true, string.format(L["TPL_IMPORTED_FMT"], rec.name), true
end

function TPL.BackupList()
    local out = {}
    for _, v in ipairs(TPL.User()) do
        local rec = BNB.DeepCopy(v.rec)
        rec.id = v.key
        out[#out + 1] = rec
    end
    return out
end

function TPL.ImportRecords(list)
    if type(list) ~= "table" then return 0 end
    local s, n = Store(true), 0
    if not s then return 0 end
    for _, raw in ipairs(list) do
        local rec = CleanRecord(raw)
        local id = type(raw) == "table" and type(raw.id) == "string" and raw.id:match("^u[%w%-_]+$")
        if rec and not (id and s[id]) then
            s[id or ("u" .. BNB.GenerateID())] = rec
            n = n + 1
        end
    end
    if n > 0 then Changed() end
    return n
end

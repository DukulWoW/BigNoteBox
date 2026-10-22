-- BigNoteBox Core/SystemNotes.lua -- System folders (ALL-511)
--
-- Folders every player has, built from files the addon ships: Patch notes
-- (UI/WhatsNew.lua registers it from UI/PatchHistory.lua) and Help (UI/Help.lua,
-- from UI/HelpData.lua, ALL-512) Decided with Dukul, 2026-10-19: their notes are made at draw
-- time and never saved, so no migration per release and nothing in backups,
-- history or the trash. They sit after the Notes section, open read-only in
-- the editor (locked, cannot be unlocked) and can be copied to a normal note.
-- A setting hides each folder; Patch notes can hide one release at a time.
--
-- A system note is a table only BNB.GetNote can see (it falls back to SYS.Get
-- for an id starting "sys-"). UpdateNote, DeleteNote, StampOpened and the
-- history read BigNoteBoxNotesDB.notes directly, so every write refuses one;
-- CopyNote takes one as its source (title, body and richMode only).
--
-- A note's fields: id, title, body, richMode, scope "global", tags {},
-- locked true, pinned false, created / updated, system = its folder key,
-- sysItem = what Hide saves (a release's version).
--
-- Saved (BigNoteBoxDB.sysFolders, account data: Profiles SHARED):
--   sysFolders[key] = { open = bool, hidden = { [sysItem] = true } }
-- Folder on / off is a per-profile setting named by the provider (DEFAULTS).
--
-- PUBLIC API (BNB.SystemNotes):
--   SYS.Register(p)       p = { key, order, name = L key, setting = DEFAULTS
--                         key, prefix = id prefix, r, g, b = name colour,
--                         icon = the notes' list icon (a note's own wins),
--                         iconFrame = its icon frame key (UI/IconFrames.lua),
--                         Build(rich) -> notes newest first, canHide = bool }
--   SYS.IsSystem(id)      true for any "sys-" id
--   SYS.Folders()         { provider, ... } of the folders switched on, in order
--   SYS.Notes(key)        that folder's notes, hidden ones left out
--   SYS.Search(key, lower) those of them whose title or text has lower (a
--                         lower-case search text; nil = all), as the list search
--   SYS.Get(id)           the note, or nil (hidden, folder off, unknown)
--   SYS.FolderOf(id)      the folder key of a system note id
--   SYS.IsOpen(key) / SYS.SetOpen(key, open)   folders start closed
--   SYS.Hide(id)          hides that note (provider.canHide)
--   SYS.ShowHidden(key)   brings every hidden one back
--   SYS.HiddenCount(key)
--   SYS.Invalidate()      rebuild on next read (Rich Notes switched)
--   SYS.Reveal(key, on)   shows a folder whose setting is off for this session
--                         (on = false takes that back); a help link opens a
--                         topic while the Help folder is hidden (ALL-512)
-- Every change sends "SystemNotesChanged" (the list redraws on it).
--------------------------------------------------------------------------------

local BNB = BigNoteBox

local SYS = {}
BNB.SystemNotes = SYS

SYS.PREFIX = "sys-"

local _providers = {}   -- key -> provider
local _order     = {}   -- providers by order
local _built     = {}   -- key -> { rich = bool, list = { note, ... } }
local _byID      = {}   -- id -> note (every built note, hidden included)
local _revealed  = {}   -- key -> true: shown this session although switched off

local function Changed(key) BNB.SendMessage("SystemNotesChanged", key) end

local function State(key, create)
    local db = BigNoteBoxDB
    if not db then return nil end
    if type(db.sysFolders) ~= "table" then
        if not create then return nil end
        db.sysFolders = {}
    end
    local s = db.sysFolders[key]
    if type(s) ~= "table" then
        if not create then return nil end
        s = {}
        db.sysFolders[key] = s
    end
    return s
end

function SYS.Register(p)
    if type(p) ~= "table" or not p.key or _providers[p.key] then return end
    _providers[p.key] = p
    _order[#_order + 1] = p
    table.sort(_order, function(a, b) return (a.order or 0) < (b.order or 0) end)
end

function SYS.IsSystem(id)
    return type(id) == "string" and id:sub(1, #SYS.PREFIX) == SYS.PREFIX
end

local function Enabled(p)
    if not p.setting or _revealed[p.key] then return true end
    local v = BigNoteBoxDB and BigNoteBoxDB[p.setting]
    if v == nil then v = BNB.DEFAULTS and BNB.DEFAULTS[p.setting] end
    return v ~= false
end

-- The folder's notes, built once per Rich Notes state
local function Built(p)
    local rich = BNB.RichEnabled and BNB.RichEnabled() or false
    local b = _built[p.key]
    if b and b.rich == rich then return b.list end
    if b then
        for _, n in ipairs(b.list) do _byID[n.id] = nil end
    end
    local ok, list = pcall(p.Build, rich)
    if not ok or type(list) ~= "table" then
        if not ok then geterrorhandler()(list) end
        list = {}
    end
    for _, n in ipairs(list) do
        n.scope, n.tags, n.locked, n.pinned = "global", n.tags or {}, true, false
        n.system = p.key
        n.icon = n.icon or p.icon
        n.iconFrame = n.iconFrame or p.iconFrame
        -- A provider may say a note is plain (a Help topic written plain)
        if n.richMode == nil then n.richMode = rich end
        n.updated = n.updated or n.created
        _byID[n.id] = n
    end
    _built[p.key] = { rich = rich, list = list }
    return list
end

function SYS.Folders()
    local out = {}
    for _, p in ipairs(_order) do
        if Enabled(p) then out[#out + 1] = p end
    end
    return out
end

local function IsHidden(n)
    local s = State(n.system, false)
    return s and s.hidden and n.sysItem and s.hidden[n.sysItem] == true or false
end

function SYS.Notes(key)
    local p = _providers[key]
    if not (p and Enabled(p)) then return {} end
    local out = {}
    for _, n in ipairs(Built(p)) do
        if not IsHidden(n) then out[#out + 1] = n end
    end
    return out
end

function SYS.Search(key, lower)
    local list = SYS.Notes(key)
    if not lower or lower == "" then return list end
    local hits = {}
    for _, n in ipairs(list) do
        local lt, lb = BNB.NoteLower(n, "title"), BNB.NoteLower(n, "body")
        if (lt and lt:find(lower, 1, true)) or (lb and lb:find(lower, 1, true)) then
            hits[#hits + 1] = n
        end
    end
    return hits
end

function SYS.FolderOf(id)
    if not SYS.IsSystem(id) then return nil end
    for _, p in ipairs(_order) do
        if p.prefix and id:sub(1, #p.prefix) == p.prefix then return p.key end
    end
end

function SYS.Get(id)
    local key = SYS.FolderOf(id)
    local p = key and _providers[key]
    if not (p and Enabled(p)) then return nil end
    Built(p)   -- builds, or rebuilds after a Rich Notes switch
    local n = _byID[id]
    if n and not IsHidden(n) then return n end
end

function SYS.Provider(key) return _providers[key] end

function SYS.IsOpen(key)
    local s = State(key, false)
    return s ~= nil and s.open == true
end

function SYS.SetOpen(key, open)
    local s = State(key, true)
    if not s then return end
    open = open and true or nil
    if s.open == open then return end
    s.open = open
    Changed(key)
end

function SYS.Hide(id)
    local n = SYS.Get(id)
    local p = n and _providers[n.system]
    if not (p and p.canHide and n.sysItem) then return end
    local s = State(n.system, true)
    s.hidden = s.hidden or {}
    s.hidden[n.sysItem] = true
    if BNB._currentNoteID == id and BNB.SelectNote then BNB.SelectNote(nil) end
    Changed(n.system)
end

function SYS.HiddenCount(key)
    local s = State(key, false)
    local c = 0
    for _ in pairs(s and s.hidden or {}) do c = c + 1 end
    return c
end

function SYS.ShowHidden(key)
    local s = State(key, false)
    if not (s and s.hidden and next(s.hidden)) then return end
    s.hidden = nil
    Changed(key)
end

function SYS.Invalidate()
    wipe(_built); wipe(_byID)
    Changed(nil)
end

function SYS.Reveal(key, on)
    on = on ~= false or nil
    if _revealed[key] == on then return end
    _revealed[key] = on
    Changed(key)
end

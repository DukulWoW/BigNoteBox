-- BigNoteBox Core/Folders.lua -- The player's note folders (ALL-510)
--
-- Decided with Dukul, 2026-10-19: one level only (no folders in folders), a
-- note is in one folder at most (tags stay "what it is about"), one folder
-- list for the whole account. A folder shows on a tab when it holds a note
-- visible there; an empty folder shows on every tab, so it can be filled.
-- Folders sort A-Z; the notes inside follow the list sort. A pinned note in
-- a folder shows under Pinned only (the folder count still has it). Each
-- folder remembers whether it is open; `folderStartOpen` (Settings > Notes)
-- is how a new one starts. System folders (Patch notes, Help, ALL-511) are
-- built from shipped files and never stored here.
--
-- Saved in BigNoteBoxNotesDB.folders (made on first write, no schema bump):
--   folders[id] = { name, color, open, created }
--   color = a palette key of BNB.TagColors.LIST (nil = no colour); a key
--   no longer in the palette reads as no colour
-- A note's folder is `note.folder` = a folder id (Core/NoteFields.lua: copied,
-- backed up, never shared). An id with no folder here (deleted, a note from
-- another account, the trash) reads as no folder: F.Of(note).
--
-- PUBLIC API (BNB.Folders):
--   F.ART_CLOSED / _OPEN / _FULL / _EMPTY   Dukul's folder pictures (colour)
--   F.Art(open, hasNotes)  the list's picture for a folder
--   F.List()             { { id, name, color, open }, ... } A-Z
--   F.Get(id)            the record or nil
--   F.Any()              true while there is at least one folder
--   F.Of(note)           its folder id, nil when none or unknown
--   F.Create(name, color) -> id (a name already used returns that folder)
--   F.Rename(id, name)   -> true, or false + message key
--   F.SetColor(id, key)  palette key or nil
--   F.Color(id)          r, g, b or nil
--   F.Text(id, text)     text (default the name) in the folder's colour
--   F.IsOpen(id) / F.SetOpen(id, open)
--   F.Delete(id)         the folder goes, its notes go back to no folder
--   F.Move(ids, id)      notes into folder id (nil = out of folders)
--   F.CountAll(id)       live notes in it, every tab
--   F.Counts()           { [id] = live notes in it }, one pass
--   F.OpenFor(noteID)    opens the note's folder (a note opened from outside)
--   F.FindByName(name)   id of the folder with that name (any case)
--   F.BackupList(notes)  folders for a JSON backup (nil notes = all)
--   F.ImportList(list)   a backup's folders in; -> backup id -> id here
--   F.ImportID(id, map)  a note's folder id on import, or nil
--   F.MAX_NAME
--   BNB.FoldersEnabled() / BNB.ApplyFoldersModule(on)   the module switch (ALL-514)
-- Every change sends "FoldersChanged" (the list redraws on it); moving notes
-- sends the usual NoteChanged per note.
--------------------------------------------------------------------------------

local BNB = BigNoteBox

local F = {}
BNB.Folders = F

-- Dukul's pictures (2026-10-19), in colour, so never tinted: the folder's
-- colour is on its name. Closed = closed; open = full while it holds notes
-- on this tab, empty without ("ui-folder-full to show that the folder has
-- content", "use ui-folder-empty"); ui-folder-open is the menus' folder
local ART = "Interface\\AddOns\\BigNoteBox\\Assets\\UI\\"
F.ART_CLOSED = ART .. "ui-folder-closed"
F.ART_OPEN   = ART .. "ui-folder-open"
F.ART_FULL   = ART .. "ui-folder-full"
F.ART_EMPTY  = ART .. "ui-folder-empty"
F.MAX_NAME   = 40

-- The list's picture for a folder: open or not, notes in it or not
function F.Art(open, hasNotes)
    if not open then return F.ART_CLOSED end
    return hasNotes and F.ART_FULL or F.ART_EMPTY
end

-- Skin mode's note list folder (Dukul, 2026-10-19): white art, tinted in the
-- folder's name colour; open / closed only
F.ART_SKIN_OPEN   = ART .. "ui-note-list-folder-open"
F.ART_SKIN_CLOSED = ART .. "ui-note-list-folder-closed"

-- Draws a folder picture on tex: the normal look = Dukul's colour art as it is
-- drawn, skin mode = the white art in r, g, b (the folder name's colour)
function F.PaintArt(tex, open, hasNotes, r, g, b)
    if BigNoteBoxDB and BigNoteBoxDB.skinMode then
        tex:SetTexture(open and F.ART_SKIN_OPEN or F.ART_SKIN_CLOSED)
        if not r then r, g, b = BNB.HeaderColor() end
        tex:SetVertexColor(r, g, b)
    else
        tex:SetTexture(F.Art(open, hasNotes))
        tex:SetVertexColor(1, 1, 1)
    end
end

-- The Pinned / Notes headers' pictures (Dukul, 2026-10-20): art = "pinned"
-- or "notes"; normal = ui-note-list-<art> in colour, skin mode = its -skin
-- art tinted in r, g, b (the header colour when none). The folder view's No
-- folder header uses "notes" too
function F.PaintSectionArt(tex, art, r, g, b)
    local path = ART .. "ui-note-list-" .. art
    if BigNoteBoxDB and BigNoteBoxDB.skinMode then
        tex:SetTexture(path .. "-skin")
        if not r then r, g, b = BNB.HeaderColor() end
        tex:SetVertexColor(r, g, b)
    else
        tex:SetTexture(path)
        tex:SetVertexColor(1, 1, 1)
    end
end

local function Store(create)
    local ndb = BNB.NotesDB and BNB.NotesDB()
    if not ndb then return nil end
    if ndb.folders == nil and create then ndb.folders = {} end
    return ndb.folders
end

local function Changed(id) BNB.SendMessage("FoldersChanged", id) end

local function Trim(s)
    if type(s) ~= "string" then return "" end
    -- One line, no WoW escapes: it is drawn in headers and menus
    s = s:gsub("[\r\n\t]", " "):gsub("|", "")
    return (s:match("^%s*(.-)%s*$"))
end

local function NewID(store)
    local id
    repeat
        id = string.format("fld-%08x%04x", time(), math.random(0, 0xFFFF))
    until not store[id]
    return id
end

local function Palette(key)
    local TC = BNB.TagColors
    if not (TC and key) then return nil end
    for _, c in ipairs(TC.LIST) do
        if c.key == key then return c end
    end
end

function F.Get(id)
    local s = Store(false)
    local rec = s and id and s[id]
    if type(rec) == "table" then return rec end
end

function F.Any()
    local s = Store(false)
    return s ~= nil and next(s) ~= nil
end

function F.Of(note)
    local id = note and note.folder
    if id and F.Get(id) then return id end
end

function F.List()
    local out = {}
    for id, rec in pairs(Store(false) or {}) do
        if type(rec) == "table" then
            out[#out + 1] = { id = id, name = rec.name or "", color = rec.color, open = rec.open }
        end
    end
    table.sort(out, function(a, b)
        local la, lb = a.name:lower(), b.name:lower()
        if la ~= lb then return la < lb end
        return a.id < b.id
    end)
    return out
end

function F.FindByName(name)
    local low = Trim(name):lower()
    if low == "" then return nil end
    for id, rec in pairs(Store(false) or {}) do
        if type(rec) == "table" and (rec.name or ""):lower() == low then return id end
    end
end

function F.Create(name, color)
    name = Trim(name)
    if name == "" then return nil end
    if #name > F.MAX_NAME then name = name:sub(1, F.MAX_NAME) end
    local found = F.FindByName(name)
    if found then return found end
    local s = Store(true); if not s then return nil end
    local id = NewID(s)
    local db = BigNoteBoxDB
    local open = db and db.folderStartOpen
    if open == nil then open = BNB.DEFAULTS.folderStartOpen end
    s[id] = { name = name, color = Palette(color) and color or nil,
              open = open and true or false, created = time() }
    Changed(id)
    return id
end

function F.Rename(id, name)
    local rec = F.Get(id); if not rec then return false end
    name = Trim(name)
    if name == "" then return false, "FOLDER_ERR_EMPTY" end
    if #name > F.MAX_NAME then name = name:sub(1, F.MAX_NAME) end
    local other = F.FindByName(name)
    if other and other ~= id then return false, "FOLDER_ERR_TAKEN" end
    if rec.name == name then return true end
    rec.name = name
    Changed(id)
    return true
end

function F.SetColor(id, key)
    local rec = F.Get(id); if not rec then return end
    if key and not Palette(key) then return end
    if rec.color == key then return end
    rec.color = key
    Changed(id)
end

function F.Color(id)
    local rec = F.Get(id)
    local c = rec and Palette(rec.color)
    if c then return c.r, c.g, c.b end
end

function F.Text(id, text)
    local rec = F.Get(id)
    text = text or (rec and rec.name) or ""
    local r, g, b = F.Color(id)
    if not r then return text end
    return string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, text)
end

function F.IsOpen(id)
    local rec = F.Get(id)
    return rec and rec.open == true or false
end

function F.SetOpen(id, open)
    local rec = F.Get(id); if not rec then return end
    open = open and true or false
    if rec.open == open then return end
    rec.open = open
    Changed(id)
end

-- Notes into a folder. Filing is not editing: noTouch, so "Edited" sort and
-- the Oracle's recent weight stay put
function F.Move(ids, id)
    if id and not F.Get(id) then return 0 end
    local n = 0
    for _, noteID in ipairs(ids or {}) do
        local note = BNB.GetNote(noteID)
        if note and F.Of(note) ~= id then
            if id then
                BNB.UpdateNote(noteID, { folder = id }, { noTouch = true })
            else
                BNB.UpdateNote(noteID, { _clear = { "folder" } }, { noTouch = true })
            end
            n = n + 1
        end
    end
    return n
end

function F.CountAll(id)
    local ndb, n = BNB.NotesDB(), 0
    for _, note in pairs(ndb and ndb.notes or {}) do
        if note.folder == id then n = n + 1 end
    end
    return n
end

-- Folder id -> live notes in it, every tab, in one pass (the list asks this
-- on each redraw: an empty folder shows on every tab)
function F.Counts()
    local ndb, out = BNB.NotesDB(), {}
    if not (ndb and ndb.folders) then return out end
    for _, note in pairs(ndb.notes or {}) do
        local id = note.folder
        if id then out[id] = (out[id] or 0) + 1 end
    end
    return out
end

-- The folder goes; its notes stay, in no folder (Dukul, 2026-10-19). Trashed
-- notes keep the id, which then reads as no folder (F.Of)
function F.Delete(id)
    local s = Store(false)
    if not (s and s[id]) then return end
    local ids = {}
    for noteID, note in pairs(BNB.NotesDB().notes or {}) do
        if note.folder == id then ids[#ids + 1] = noteID end
    end
    s[id] = nil
    for _, noteID in ipairs(ids) do
        BNB.UpdateNote(noteID, { _clear = { "folder" } }, { noTouch = true })
    end
    Changed(id)
end

-- ── Backups (ALL-510 S2) ─────────────────────────────────────────────────────
-- Folders ride with the notes in a JSON backup: notes = nil (the full backup)
-- gives every folder, empty ones too; a list of notes gives the folders they
-- are in. { { id, name, color, open }, ... } A-Z, nil when none
function F.BackupList(notes)
    local used
    if notes then
        used = {}
        for _, note in ipairs(notes) do
            local id = F.Of(note)
            if id then used[id] = true end
        end
    end
    local out = {}
    for _, f in ipairs(F.List()) do
        if not used or used[f.id] then
            out[#out + 1] = { id = f.id, name = f.name, color = f.color, open = f.open }
        end
    end
    return #out > 0 and out or nil
end

-- A backup's folders, before its notes: a name already here is that folder
-- (any case), any other is made. Returns backup id -> folder id here
function F.ImportList(list)
    local map = {}
    if type(list) ~= "table" then return map end
    for _, rec in ipairs(list) do
        if type(rec) == "table" and type(rec.id) == "string" and type(rec.name) == "string" then
            local id = F.FindByName(rec.name)
            if not id then
                id = F.Create(rec.name, type(rec.color) == "string" and rec.color or nil)
                if id and type(rec.open) == "boolean" then F.SetOpen(id, rec.open) end
            end
            if id then map[rec.id] = id end
        end
    end
    return map
end

-- A note's folder id on import: the backup's folder as mapped, else the same
-- id when that folder is here (a note exported on its own, same account),
-- else none
function F.ImportID(id, map)
    if type(id) ~= "string" then return nil end
    if map and map[id] then return map[id] end
    if F.Get(id) then return id end
end

function F.OpenFor(noteID)
    local id = F.Of(BNB.GetNote(noteID))
    if id and not F.IsOpen(id) then F.SetOpen(id, true) end
end

-- ── Module switch (ALL-514, Dukul 2026-10-19) ────────────────────────────────
-- `foldersEnabled` (DEFAULTS true; off in the setup wizard's Minimal), read
-- only through BNB.FoldersEnabled(). Off = every way to make, see or fill a
-- folder is gone: folder headers (notes in a folder show under Notes), the
-- folder view and its button, Move to folder, drag onto headers, New folder,
-- Copy / Move into a folder, the New note dialog's folder. The data stays
-- (note.folder, BigNoteBoxNotesDB.folders, backups, copies), so switching
-- back on brings the filing back. The system folders (Patch notes) are not
-- part of it: they keep their own setting.
function BNB.FoldersEnabled()
    return not BigNoteBoxDB or BigNoteBoxDB.foldersEnabled ~= false
end

-- After the switch changed: out of the folder view, then everything that
-- shows folders redraws from FoldersChanged / FoldersModule
function BNB.ApplyFoldersModule(on)
    local db = BigNoteBoxDB
    if not on and db and db.tagTreeMode and db.treeSource == "folders" and BNB.SetTagTreeMode then
        BNB.SetTagTreeMode(false)
    end
    BNB.SendMessage("FoldersModule", on)
    Changed(nil)
end

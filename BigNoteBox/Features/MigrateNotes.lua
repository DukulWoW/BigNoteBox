-- BigNoteBox Features/MigrateNotes.lua
local BNB = BigNoteBox
-- Detects NoteworthyII, TakeANote, YetAnotherNotepad, Notepad, Notes,
-- TinyPad, PurpleNotes, SimpleNote, QuickNotes, and OneWoW Notes and
-- offers to migrate their notes into BNB.
--
-- Public API (BNB.Migration.*):
--   DetectAvailable()       -> array of addon keys that are loaded and not migrationDone
--   HasAny()                -> true if any of the three addons are loaded at all
--   CollectPreview(sel)     -> returns array of preview entries from current selections
--   Run(sel)                -> executes migration then C_UI.Reload()
--   ShowPopup()             -> shows the login popup
--   ShowAddonPopup(key)     -> shows the per-addon confirm popup from Advanced tab
--
-- SavedVariables flags (in BigNoteBoxDB):
--   migrationDone     = { NoteworthyII=true, ... }   set after successful run
--   migrationDeclined = { NoteworthyII=true, ... }   set when "Don't ask again" ticked

local ASSETS = "Interface\\AddOns\\BigNoteBox\\Assets\\"

BNB.Migration = BNB.Migration or {}
local M = BNB.Migration

local ADDON_KEYS  = { "NoteworthyII", "TakeANote", "YetAnotherNotepad", "Notepad", "NotepadChar", "Notes", "TinyPad", "PurpleNotes", "SimpleNote", "QuickNotes", "OneWoWNotes" }
local ADDON_NAMES = {
    NoteworthyII      = "Noteworthy II",
    TakeANote         = "TakeANote",
    YetAnotherNotepad = "Yet Another Notepad",
    Notepad           = "Notepad",
    NotepadChar       = "Notepad (character)",
    Notes             = "Notes",
    TinyPad           = "TinyPad",
    PurpleNotes       = "PurpleNotes",
    SimpleNote        = "SimpleNote",
    QuickNotes        = "QuickNotes",
    OneWoWNotes       = "OneWoW Notes",
}
-- Maps addon keys to the actual WoW addon folder name for IsAddOnLoaded.
-- NotepadChar shares the same addon folder as Notepad.
local ADDON_LOAD_NAME = {
    NoteworthyII      = "NoteworthyII",
    TakeANote         = "TakeANote",
    YetAnotherNotepad = "YetAnotherNotepad",
    Notepad           = "Notepad",
    NotepadChar       = "Notepad",
    Notes             = "Notes",
    TinyPad           = "TinyPad",
    PurpleNotes       = "PurpleNotes",
    SimpleNote        = "SimpleNote",
    QuickNotes        = "QuickNotes",
    OneWoWNotes       = "OneWoW_Notes",
}

-- Expose for use by ConfigWindow and other modules
M.ADDON_KEYS      = ADDON_KEYS
M.ADDON_NAMES     = ADDON_NAMES
M.ADDON_LOAD_NAME = ADDON_LOAD_NAME

local WIN_W  = 420
local PAD    = 16

-- ── Character normalisation ───────────────────────────────────────────────────
-- Both "Name-Realm" and "Name - Realm" normalise to "name-realm" for matching.
local function NormalizeCharKey(k)
    return (k:lower():gsub("%s*-%s*", "-"):gsub("%s+", ""))
end

-- Try to match a raw foreign-addon char key to a BNB known character key.
-- Returns the BNB key on match, nil otherwise.
-- Primary source: BigNoteBoxDB.knownChars (populated on every login with the
-- correct normalised realm name). Falls back to scanning note.character fields
-- and finally the current player via GetNormalizedRealmName.
local function MatchCharKey(rawKey)
    local norm = NormalizeCharKey(rawKey)
    local db   = BigNoteBoxDB

    -- 1. Check knownChars — most reliable, uses GetNormalizedRealmName
    if db and db.knownChars then
        for key in pairs(db.knownChars) do
            if NormalizeCharKey(key) == norm then return key end
        end
    end

    -- 2. Scan existing character-scoped notes
    if db and db.notes then
        for _, note in pairs(db.notes) do
            if note.character and NormalizeCharKey(note.character) == norm then
                return note.character
            end
        end
    end

    -- 3. Current player (GetNormalizedRealmName matches what BNB stores)
    local name  = UnitName("player")
    local realm = GetNormalizedRealmName()
    if name and realm then
        local cur = name .. "-" .. realm
        if NormalizeCharKey(cur) == norm then return cur end
    end

    return nil
end

-- ── Note creation helper ──────────────────────────────────────────────────────
local function CreateMigratedNote(title, body, tags, charKey)
    if not body or body:match("^%s*$") then return end
    if not title or title == "" then title = "Imported Note" end
    -- Use the low-level BNB.CreateNote (returns id) not BNB.CreateNewNote
    -- which opens the interactive UI dialog and does not return an id.
    local id = BNB.CreateNote(title, body)
    if not id then return end
    -- Scope
    if charKey then
        BNB.UpdateNote(id, { scope = "character", character = charKey })
    else
        BNB.UpdateNote(id, { scope = "global" })
    end
    -- Tags
    if tags and #tags > 0 then
        local note = BNB.GetNote and BNB.GetNote(id)
        local existing = (note and note.tags) or {}
        for _, t in ipairs(tags) do
            local found = false
            for _, et in ipairs(existing) do
                if et:lower() == t:lower() then found = true; break end
            end
            if not found then tinsert(existing, t) end
        end
        BNB.UpdateNote(id, { tags = existing })
    end
    return id
end

-- ── Collect preview entries ───────────────────────────────────────────────────
-- sel = { NoteworthyII=true/false, TakeANote=true/false, YetAnotherNotepad=true/false,
--         takeANoteCategoryTags=true/false }
-- Returns array of { title, scope, charLabel, tags, bodyPreview }
function M.CollectPreview(sel)
    local entries = {}

    -- NoteworthyII
    if sel.NoteworthyII and Noteworthy_DB then
        local db = Noteworthy_DB
        -- Character notes: iterate character_list
        local charList = db["character_list"] or {}
        for _, ck in ipairs(charList) do
            local body = db[ck]
            if body and not body:match("^%s*$") then
                local matched = MatchCharKey(ck)
                local charLabel = matched or (ck .. " (no match - global)")
                tinsert(entries, {
                    addon      = "NoteworthyII",
                    title      = ck,
                    scope      = matched and "character" or "global",
                    charLabel  = charLabel,
                    tags       = { "NoteworthyII" },
                    bodyPreview = body:sub(1, 100),
                })
            end
        end
        -- Shared text
        local shared = db["shared_text"]
        if shared and not shared:match("^%s*$") then
            tinsert(entries, {
                addon      = "NoteworthyII",
                title      = "Shared Notes",
                scope      = "global",
                charLabel  = "Global",
                tags       = { "NoteworthyII" },
                bodyPreview = shared:sub(1, 100),
            })
        end
        -- Quick text
        local quick = db["quick_text"]
        if quick and not quick:match("^%s*$") then
            tinsert(entries, {
                addon      = "NoteworthyII",
                title      = "Quick Notes",
                scope      = "global",
                charLabel  = "Global",
                tags       = { "NoteworthyII" },
                bodyPreview = quick:sub(1, 100),
            })
        end
    end

    -- TakeANote
    if sel.TakeANote and TakeANoteDB then
        local profile = TakeANoteDB["profile"]
        if profile and profile["categories"] then
            for _, cat in ipairs(profile["categories"]) do
                if cat.notes then
                    for _, note in ipairs(cat.notes) do
                        if note.text and not note.text:match("^%s*$") then
                            local tags = sel.takeANoteCategoryTags
                                and { "TakeANote", cat.name }
                                or  { "TakeANote" }
                            tinsert(entries, {
                                addon      = "TakeANote",
                                title      = (note.title and note.title ~= "") and note.title or "Imported Note",
                                scope      = "global",
                                charLabel  = "Global",
                                tags       = tags,
                                bodyPreview = note.text:sub(1, 100),
                            })
                        end
                    end
                end
            end
        end
    end

    -- YetAnotherNotepad
    if sel.YetAnotherNotepad and YAnotepadDB then
        local charDB = YAnotepadDB["char"]
        if charDB then
            local globalIdx = 1
            for ck, cdata in pairs(charDB) do
                if cdata.notes then
                    local matched = MatchCharKey(ck)
                    local charLabel = matched or (ck .. " (no match - global)")
                    -- YAN notes array is sparse (index 1 may be nil) — use pairs
                    for _, entry in pairs(cdata.notes) do
                        if entry and entry[1] and not entry[1]:match("^%s*$") then
                            tinsert(entries, {
                                addon      = "YetAnotherNotepad",
                                title      = "YetAnotherNotepad " .. globalIdx,
                                scope      = matched and "character" or "global",
                                charLabel  = charLabel,
                                tags       = { "YetAnotherNotepad" },
                                bodyPreview = entry[1]:sub(1, 100),
                            })
                            globalIdx = globalIdx + 1
                        end
                    end
                end
            end
        end
    end

    -- Notepad (global)
    if sel.Notepad and Notepad_Vars and Notepad_Vars.Notes then
        for _, note in ipairs(Notepad_Vars.Notes) do
            local body = note.Note
            if body and not body:match("^%s*$") then
                local title = (note.Title and note.Title ~= "") and note.Title or "Imported Note"
                tinsert(entries, {
                    addon       = "Notepad",
                    title       = title,
                    scope       = "global",
                    charLabel   = "Global",
                    tags        = { "Notepad" },
                    bodyPreview = body:sub(1, 100),
                })
            end
        end
    end

    -- Notepad (per-character — current player only)
    if sel.NotepadChar and Notepad_CVars and Notepad_CVars.Notes then
        local name  = UnitName("player")
        local realm = GetNormalizedRealmName()
        local charKey = name and realm and (name .. "-" .. realm) or nil
        local matched = charKey and MatchCharKey(charKey)
        local charLabel = matched or (charKey and (charKey .. " (no match - global)") or "Unknown")
        for _, note in ipairs(Notepad_CVars.Notes) do
            local body = note.Note
            if body and not body:match("^%s*$") then
                local title = (note.Title and note.Title ~= "") and note.Title or "Imported Note"
                tinsert(entries, {
                    addon       = "NotepadChar",
                    title       = title,
                    scope       = matched and "character" or "global",
                    charLabel   = charLabel,
                    tags        = { "Notepad" },
                    bodyPreview = body:sub(1, 100),
                })
            end
        end
    end

    -- Notes (type 1 = regular note only; other types e.g. todo lists are not supported)
    if sel.Notes and NotesData and NotesData.notes then
        for _, note in ipairs(NotesData.notes) do
            if note.type == 1 then
                local body = note.text
                if body and not body:match("^%s*$") then
                    local title = (note.title and note.title ~= "") and note.title or "Imported Note"
                    tinsert(entries, {
                        addon       = "Notes",
                        title       = title,
                        scope       = "global",
                        charLabel   = "Global",
                        tags        = { "Notes" },
                        bodyPreview = body:sub(1, 100),
                    })
                end
            end
        end
    end

    -- TinyPad (plain string array, no titles)
    if sel.TinyPad and TinyPadPages then
        for i, body in ipairs(TinyPadPages) do
            if body and not body:match("^%s*$") then
                tinsert(entries, {
                    addon       = "TinyPad",
                    title       = "TinyPad " .. i,
                    scope       = "global",
                    charLabel   = "Global",
                    tags        = { "TinyPad" },
                    bodyPreview = body:sub(1, 100),
                })
            end
        end
    end

    -- PurpleNotes (flat array, optional title)
    if sel.PurpleNotes and PurpleNotesDB and PurpleNotesDB.notes then
        for _, note in ipairs(PurpleNotesDB.notes) do
            local body = note.text
            if body and not body:match("^%s*$") then
                local title = (note.title and note.title ~= "") and note.title or "Imported Note"
                tinsert(entries, {
                    addon       = "PurpleNotes",
                    title       = title,
                    scope       = "global",
                    charLabel   = "Global",
                    tags        = { "PurpleNotes" },
                    bodyPreview = body:sub(1, 100),
                })
            end
        end
    end

    -- SimpleNote (flat array, title + text + updated timestamp)
    if sel.SimpleNote and SimpleNoteDB and SimpleNoteDB.notes then
        for _, note in ipairs(SimpleNoteDB.notes) do
            local body = note.text
            if body and not body:match("^%s*$") then
                local title = (note.title and note.title ~= "") and note.title or "Imported Note"
                tinsert(entries, {
                    addon       = "SimpleNote",
                    title       = title,
                    scope       = "global",
                    charLabel   = "Global",
                    tags        = { "SimpleNote" },
                    bodyPreview = body:sub(1, 100),
                })
            end
        end
    end

    -- QuickNotes (SavedVariablesPerCharacter: sequential string array, current char only)
    if sel.QuickNotes and CharNotesDB then
        local name  = UnitName("player")
        local realm = GetNormalizedRealmName()
        local charKey = name and realm and (name .. "-" .. realm) or nil
        local matched = charKey and MatchCharKey(charKey)
        local charLabel = matched or (charKey and (charKey .. " (no match - global)") or "Unknown")
        for i, body in ipairs(CharNotesDB) do
            if body and not body:match("^%s*$") then
                tinsert(entries, {
                    addon       = "QuickNotes",
                    title       = "QuickNotes " .. i,
                    scope       = matched and "character" or "global",
                    charLabel   = charLabel,
                    tags        = { "QuickNotes" },
                    bodyPreview = body:sub(1, 100),
                })
            end
        end
    end

    -- OneWoW Notes (keyed tables in global and per-character storage)
    if sel.OneWoWNotes and OneWoW_Notes_DB then
        local odb = OneWoW_Notes_DB

        -- Global notes
        local globalNotes = odb.global and odb.global.notes
        if globalNotes then
            for _, note in pairs(globalNotes) do
                local body = note.content
                if body and not body:match("^%s*$") then
                    local title = (note.title and note.title ~= "") and note.title or "Imported Note"
                    local tags  = { "OneWoW" }
                    if note.category and note.category ~= "" then tinsert(tags, note.category) end
                    local nt = note.noteType
                    if nt == "daily" or nt == "weekly" then tinsert(tags, nt) end
                    if note.tags then
                        for _, t in ipairs(note.tags) do
                            local found = false
                            for _, et in ipairs(tags) do if et == t then found = true; break end end
                            if not found then tinsert(tags, t) end
                        end
                    end
                    tinsert(entries, {
                        addon       = "OneWoWNotes",
                        title       = title,
                        scope       = "global",
                        charLabel   = "Global",
                        tags        = tags,
                        bodyPreview = body:sub(1, 100),
                    })
                end
            end
        end

        -- Per-character notes (iterate all char keys)
        if odb.char then
            for ck, cdata in pairs(odb.char) do
                local charNotes = cdata.notes
                if charNotes then
                    local matched   = MatchCharKey(ck)
                    local charLabel = matched or (ck .. " (no match - global)")
                    for _, note in pairs(charNotes) do
                        local body = note.content
                        if body and not body:match("^%s*$") then
                            local title = (note.title and note.title ~= "") and note.title or "Imported Note"
                            local tags  = { "OneWoW" }
                            if note.category and note.category ~= "" then tinsert(tags, note.category) end
                            local nt = note.noteType
                            if nt == "daily" or nt == "weekly" then tinsert(tags, nt) end
                            if note.tags then
                                for _, t in ipairs(note.tags) do
                                    local found = false
                                    for _, et in ipairs(tags) do if et == t then found = true; break end end
                                    if not found then tinsert(tags, t) end
                                end
                            end
                            tinsert(entries, {
                                addon       = "OneWoWNotes",
                                title       = title,
                                scope       = matched and "character" or "global",
                                charLabel   = charLabel,
                                tags        = tags,
                                bodyPreview = body:sub(1, 100),
                            })
                        end
                    end
                end
            end
        end
    end

    return entries
end

-- ── Run migration ─────────────────────────────────────────────────────────────
function M.Run(sel)
    local db = BigNoteBoxDB
    db.migrationDone = db.migrationDone or {}

    if sel.NoteworthyII and Noteworthy_DB then
        local ndb = Noteworthy_DB
        for _, ck in ipairs(ndb["character_list"] or {}) do
            local body = ndb[ck]
            if body and not body:match("^%s*$") then
                local matched = MatchCharKey(ck)
                CreateMigratedNote(ck, body, { "NoteworthyII" }, matched)
            end
        end
        local shared = ndb["shared_text"]
        if shared and not shared:match("^%s*$") then
            CreateMigratedNote("Shared Notes", shared, { "NoteworthyII" }, nil)
        end
        local quick = ndb["quick_text"]
        if quick and not quick:match("^%s*$") then
            CreateMigratedNote("Quick Notes", quick, { "NoteworthyII" }, nil)
        end
        db.migrationDone.NoteworthyII = true
    end

    if sel.TakeANote and TakeANoteDB then
        local profile = TakeANoteDB["profile"]
        if profile and profile["categories"] then
            for _, cat in ipairs(profile["categories"]) do
                if cat.notes then
                    for _, note in ipairs(cat.notes) do
                        if note.text and not note.text:match("^%s*$") then
                            local tags = sel.takeANoteCategoryTags
                                and { "TakeANote", cat.name }
                                or  { "TakeANote" }
                            local title = (note.title and note.title ~= "") and note.title or "Imported Note"
                            CreateMigratedNote(title, note.text, tags, nil)
                        end
                    end
                end
            end
        end
        db.migrationDone.TakeANote = true
    end

    if sel.YetAnotherNotepad and YAnotepadDB then
        local charDB = YAnotepadDB["char"]
        if charDB then
            local globalIdx = 1
            for ck, cdata in pairs(charDB) do
                if cdata.notes then
                    local matched = MatchCharKey(ck)
                    -- YAN notes array is sparse (index 1 may be nil) — use pairs
                    for _, entry in pairs(cdata.notes) do
                        if entry and entry[1] and not entry[1]:match("^%s*$") then
                            CreateMigratedNote(
                                "YetAnotherNotepad " .. globalIdx,
                                entry[1],
                                { "YetAnotherNotepad" },
                                matched
                            )
                            globalIdx = globalIdx + 1
                        end
                    end
                end
            end
        end
        db.migrationDone.YetAnotherNotepad = true
    end

    -- Notepad (global)
    if sel.Notepad and Notepad_Vars and Notepad_Vars.Notes then
        for _, note in ipairs(Notepad_Vars.Notes) do
            local body = note.Note
            if body and not body:match("^%s*$") then
                local title = (note.Title and note.Title ~= "") and note.Title or "Imported Note"
                CreateMigratedNote(title, body, { "Notepad" }, nil)
            end
        end
        db.migrationDone.Notepad = true
    end

    -- Notepad (per-character — current player only)
    -- Notepad_CVars is a SavedVariablesPerCharacter; WoW scopes it to the
    -- current character automatically. We match it to a BNB known char key.
    if sel.NotepadChar and Notepad_CVars and Notepad_CVars.Notes then
        local name  = UnitName("player")
        local realm = GetNormalizedRealmName()
        local charKey = name and realm and (name .. "-" .. realm) or nil
        local matched = charKey and MatchCharKey(charKey)
        for _, note in ipairs(Notepad_CVars.Notes) do
            local body = note.Note
            if body and not body:match("^%s*$") then
                local title = (note.Title and note.Title ~= "") and note.Title or "Imported Note"
                CreateMigratedNote(title, body, { "Notepad" }, matched)
            end
        end
        db.migrationDone.NotepadChar = true
    end

    -- Notes (type 1 = regular note only)
    if sel.Notes and NotesData and NotesData.notes then
        for _, note in ipairs(NotesData.notes) do
            if note.type == 1 then
                local body = note.text
                if body and not body:match("^%s*$") then
                    local title = (note.title and note.title ~= "") and note.title or "Imported Note"
                    CreateMigratedNote(title, body, { "Notes" }, nil)
                end
            end
        end
        db.migrationDone.Notes = true
    end

    -- TinyPad (plain string array, no titles)
    if sel.TinyPad and TinyPadPages then
        for i, body in ipairs(TinyPadPages) do
            if body and not body:match("^%s*$") then
                CreateMigratedNote("TinyPad " .. i, body, { "TinyPad" }, nil)
            end
        end
        db.migrationDone.TinyPad = true
    end

    -- PurpleNotes
    if sel.PurpleNotes and PurpleNotesDB and PurpleNotesDB.notes then
        for _, note in ipairs(PurpleNotesDB.notes) do
            local body = note.text
            if body and not body:match("^%s*$") then
                local title = (note.title and note.title ~= "") and note.title or "Imported Note"
                CreateMigratedNote(title, body, { "PurpleNotes" }, nil)
            end
        end
        db.migrationDone.PurpleNotes = true
    end

    -- SimpleNote
    if sel.SimpleNote and SimpleNoteDB and SimpleNoteDB.notes then
        for _, note in ipairs(SimpleNoteDB.notes) do
            local body = note.text
            if body and not body:match("^%s*$") then
                local title = (note.title and note.title ~= "") and note.title or "Imported Note"
                CreateMigratedNote(title, body, { "SimpleNote" }, nil)
            end
        end
        db.migrationDone.SimpleNote = true
    end

    -- QuickNotes (SavedVariablesPerCharacter: sequential string array, current char only)
    if sel.QuickNotes and CharNotesDB then
        local name    = UnitName("player")
        local realm   = GetNormalizedRealmName()
        local charKey = name and realm and (name .. "-" .. realm) or nil
        local matched = charKey and MatchCharKey(charKey)
        for i, body in ipairs(CharNotesDB) do
            if body and not body:match("^%s*$") then
                CreateMigratedNote("QuickNotes " .. i, body, { "QuickNotes" }, matched)
            end
        end
        db.migrationDone.QuickNotes = true
    end

    -- OneWoW Notes
    if sel.OneWoWNotes and OneWoW_Notes_DB then
        local odb = OneWoW_Notes_DB

        -- Helper: build tag list for a OneWoW note
        local function BuildOneWoWTags(note)
            local tags = { "OneWoW" }
            if note.category and note.category ~= "" then tinsert(tags, note.category) end
            local nt = note.noteType
            if nt == "daily" or nt == "weekly" then tinsert(tags, nt) end
            if note.tags then
                for _, t in ipairs(note.tags) do
                    local found = false
                    for _, et in ipairs(tags) do if et == t then found = true; break end end
                    if not found then tinsert(tags, t) end
                end
            end
            return tags
        end

        -- Global notes
        if odb.global and odb.global.notes then
            for _, note in pairs(odb.global.notes) do
                local body = note.content
                if body and not body:match("^%s*$") then
                    local title = (note.title and note.title ~= "") and note.title or "Imported Note"
                    local id    = CreateMigratedNote(title, body, BuildOneWoWTags(note), nil)
                    if id and note.favorite then
                        BNB.UpdateNote(id, { favorited = true })
                    end
                end
            end
        end

        -- Per-character notes (iterate all char keys)
        if odb.char then
            for ck, cdata in pairs(odb.char) do
                if cdata.notes then
                    local matched = MatchCharKey(ck)
                    for _, note in pairs(cdata.notes) do
                        local body = note.content
                        if body and not body:match("^%s*$") then
                            local title = (note.title and note.title ~= "") and note.title or "Imported Note"
                            local id    = CreateMigratedNote(title, body, BuildOneWoWTags(note), matched)
                            if id and note.favorite then
                                BNB.UpdateNote(id, { favorited = true })
                            end
                        end
                    end
                end
            end
        end

        db.migrationDone.OneWoWNotes = true
    end

    C_UI.Reload()
end

-- ── Detection helpers ─────────────────────────────────────────────────────────
function M.HasAny()
    for _, k in ipairs(ADDON_KEYS) do
        if C_AddOns.IsAddOnLoaded(ADDON_LOAD_NAME[k] or k) then return true end
    end
    return false
end

function M.DetectAvailable()
    local db  = BigNoteBoxDB
    local out = {}
    for _, k in ipairs(ADDON_KEYS) do
        if C_AddOns.IsAddOnLoaded(ADDON_LOAD_NAME[k] or k) then
            local done     = db.migrationDone     and db.migrationDone[k]
            local declined = db.migrationDeclined and db.migrationDeclined[k]
            if not done and not declined then
                tinsert(out, k)
            end
        end
    end
    return out
end

-- ── Preview window ────────────────────────────────────────────────────────────
local _previewFrame

local function BuildPreviewWindow()
    if _previewFrame then return _previewFrame end

    local skinMode = BigNoteBoxDB and BigNoteBoxDB.skinMode
    local f, titleH

    if skinMode then
        f = BNB.CreateSkinFrame(UIParent, false, "BNBMigratePreviewFrame", false)
        f:SetFrameStrata("DIALOG"); f:SetFrameLevel(100); f:SetToplevel(true)
        f:SetSize(WIN_W, 440)
        local titleBar = BNB.CreateSkinStrip(f, true, false)
        titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
        titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
        titleBar:SetHeight(28)
        titleBar:EnableMouse(true)
        titleBar:RegisterForDrag("LeftButton")
        titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
        titleBar:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)
        local titleLbl = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        titleLbl:SetPoint("CENTER", titleBar, "CENTER", -12, 0)
        titleLbl:SetTextColor(1, 0.82, 0)
        titleLbl:SetText("Migration Preview")
        f._titleLbl = titleLbl
        local closeBtn = CreateFrame("Button", nil, titleBar, "UIPanelButtonTemplate")
        closeBtn:SetSize(24, 22)
        closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", 0, 0)
        closeBtn:SetText("X")
        closeBtn:SetScript("OnClick", function() f:Hide() end)
        titleH = 28
        f:SetScript("OnShow", function() BNB.ApplyMainWindowSkin() end)
    else
        f = CreateFrame("Frame", "BNBMigratePreviewFrame", UIParent, "ButtonFrameTemplate")
        f:SetFrameStrata("DIALOG"); f:SetFrameLevel(100); f:SetToplevel(true)
        f:SetSize(WIN_W, 440)
        ButtonFrameTemplate_HidePortrait(f)
        ButtonFrameTemplate_HideButtonBar(f)
        if f.Inset then f.Inset:Hide() end
        f:SetTitle("Migration Preview")
        if f.CloseButton then
            f.CloseButton:SetScript("OnClick", function() f:Hide() end)
        end
        titleH = 32
    end

    f:SetMovable(true); f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    tinsert(UISpecialFrames, "BNBMigratePreviewFrame")

    -- Scroll area
    local sf = CreateFrame("ScrollFrame", nil, f, "ScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, -(titleH + 8))
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(PAD + 20), PAD)

    local ct = CreateFrame("Frame", nil, sf)
    ct:SetWidth(WIN_W - PAD * 2 - 20)
    ct:SetHeight(1)
    sf:SetScrollChild(ct)

    f._ct = ct
    f._sf = sf
    _previewFrame = f
    return f
end

local function PopulatePreview(entries)
    local f  = BuildPreviewWindow()

    -- Hide the old content frame (SetParent(nil) is invalid in WoW).
    -- Create a fresh child of the ScrollFrame and register it as the new scroll child.
    if f._ct then f._ct:Hide() end
    local ct = CreateFrame("Frame", nil, f._sf)
    ct:SetWidth(WIN_W - PAD * 2 - 20)
    ct:SetHeight(1)
    f._sf:SetScrollChild(ct)
    f._ct = ct

    local y        = 0
    local CW       = WIN_W - PAD * 2 - 20
    local lastAddon = nil

    if #entries == 0 then
        local lbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        lbl:SetWidth(CW); lbl:SetJustifyH("LEFT")
        lbl:SetTextColor(0.55, 0.55, 0.55)
        lbl:SetText("No notes to migrate with the current selection.")
        y = y - 24
    else
        for _, e in ipairs(entries) do
            -- Addon header
            if e.addon ~= lastAddon then
                if lastAddon then y = y - 8 end
                local hdr = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                hdr:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
                hdr:SetWidth(CW); hdr:SetJustifyH("LEFT")
                hdr:SetTextColor(1, 0.82, 0)
                hdr:SetText(ADDON_NAMES[e.addon] or e.addon)
                y = y - 20
                lastAddon = e.addon
            end

            -- Entry row: bullet + title + scope badge
            local row = CreateFrame("Frame", nil, ct)
            row:SetPoint("TOPLEFT", ct, "TOPLEFT", 8, y)
            row:SetSize(CW - 8, 18)

            local bullet = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            bullet:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
            bullet:SetText("|cff66bb6a*|r")
            bullet:SetWidth(10)

            local titleLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            titleLbl:SetPoint("LEFT", bullet, "RIGHT", 4, 0)
            titleLbl:SetWidth(CW - 140)
            titleLbl:SetJustifyH("LEFT")
            titleLbl:SetText(e.title)

            local scopeLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            scopeLbl:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            scopeLbl:SetWidth(130)
            scopeLbl:SetJustifyH("RIGHT")
            local scopeColor = e.scope == "character" and "|cff88bbff" or "|cffaaaaaa"
            scopeLbl:SetText(scopeColor .. e.charLabel .. "|r")

            -- Tooltip with body preview
            local preview = e.bodyPreview or ""
            row:EnableMouse(true)
            row:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(e.title, 1, 0.82, 0)
                GameTooltip:AddLine("Tags: " .. table.concat(e.tags, ", "), 0.6, 0.6, 0.6, true)
                if preview ~= "" then
                    GameTooltip:AddLine(" ", 1, 1, 1)
                    GameTooltip:AddLine(preview .. (e.bodyPreview and #e.bodyPreview == 100 and "..." or ""), 0.8, 0.8, 0.8, true)
                end
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)

            y = y - 20
        end
    end

    ct:SetHeight(math.max(math.abs(y) + 8, 1))
    return f
end

function M.ShowPreview(sel)
    local entries = M.CollectPreview(sel)
    local f = PopulatePreview(entries)
    -- Always reposition so it doesn't open under the popup
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "CENTER", 20, 200)
    f:Show()
    f:Raise()
end

-- ── Per-addon confirm popup (from Advanced tab) ───────────────────────────────
local _addonPopup

function M.ShowAddonPopup(key)
    if _addonPopup then _addonPopup:Hide() end

    local skinMode = BigNoteBoxDB and BigNoteBoxDB.skinMode
    local f, titleH
    local name = ADDON_NAMES[key] or key

    if skinMode then
        f = BNB.CreateSkinFrame(UIParent, false, nil, false)
        f:SetFrameStrata("DIALOG"); f:SetToplevel(true)
        f:SetSize(360, 200)
        local titleBar = BNB.CreateSkinStrip(f, true, false)
        titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
        titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
        titleBar:SetHeight(28)
        titleBar:EnableMouse(true)
        titleBar:RegisterForDrag("LeftButton")
        titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
        titleBar:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)
        local tl = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        tl:SetPoint("CENTER", titleBar, "CENTER", -12, 0)
        tl:SetTextColor(1, 0.82, 0)
        tl:SetText("Migrate " .. name)
        f._titleLbl = tl
        local cb2 = CreateFrame("Button", nil, titleBar, "UIPanelButtonTemplate")
        cb2:SetSize(24, 22); cb2:SetPoint("RIGHT", titleBar, "RIGHT", 0, 0)
        cb2:SetText("X"); cb2:SetScript("OnClick", function() f:Hide() end)
        titleH = 28
        f:SetScript("OnShow", function() BNB.ApplyMainWindowSkin() end)
    else
        f = CreateFrame("Frame", nil, UIParent, "ButtonFrameTemplate")
        f:SetFrameStrata("DIALOG"); f:SetToplevel(true)
        f:SetSize(360, 200)
        ButtonFrameTemplate_HidePortrait(f)
        ButtonFrameTemplate_HideButtonBar(f)
        if f.Inset then f.Inset:Hide() end
        f:SetTitle("Migrate " .. name)
        if f.CloseButton then f.CloseButton:SetScript("OnClick", function() f:Hide() end) end
        titleH = 32
    end

    f:SetMovable(true); f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    f:SetPoint("CENTER")

    local ct = f  -- draw directly on f
    local y  = -(titleH + 12)
    local CW = 360 - PAD * 2

    local desc = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    desc:SetPoint("TOPLEFT", ct, "TOPLEFT", PAD, y)
    desc:SetWidth(CW); desc:SetJustifyH("LEFT"); desc:SetWordWrap(true)
    desc:SetTextColor(0.8, 0.8, 0.8)
    desc:SetText("This will import notes from " .. name .. " into BigNoteBox and reload the UI. Your notes in " .. name .. " are not affected.")
    y = y - 46

    -- TakeANote sub-option
    local sel = { [key] = true, takeANoteCategoryTags = false }
    if key == "TakeANote" then
        local catCb = CreateFrame("CheckButton", nil, ct, "UICheckButtonTemplate")
        catCb:SetSize(24, 24)
        catCb:SetPoint("TOPLEFT", ct, "TOPLEFT", PAD - 2, y + 2)
        catCb:SetChecked(false)
        local catLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        catLbl:SetPoint("LEFT", catCb, "RIGHT", 4, 0)
        catLbl:SetText("Use category names as tags")
        catCb:SetScript("OnClick", function(self)
            sel.takeANoteCategoryTags = self:GetChecked() and true or false
        end)
        y = y - 30
    end

    -- NotepadChar / QuickNotes info text (per-character scope)
    if key == "NotepadChar" or key == "QuickNotes" then
        local infoLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        infoLbl:SetPoint("TOPLEFT", ct, "TOPLEFT", PAD, y)
        infoLbl:SetWidth(CW); infoLbl:SetJustifyH("LEFT"); infoLbl:SetWordWrap(true)
        infoLbl:SetTextColor(0.5, 0.5, 0.5)
        infoLbl:SetText("Per-character notes only import for the currently logged-in character. Log in with each character to migrate their notes.")
        y = y - 40
    end

    -- Reload warning
    local warn = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    warn:SetPoint("TOPLEFT", ct, "TOPLEFT", PAD, y)
    warn:SetWidth(CW); warn:SetJustifyH("LEFT"); warn:SetWordWrap(true)
    warn:SetTextColor(1, 0.6, 0.0)
    warn:SetText("|cffff9900Warning:|r A UI reload is required after migration.")
    y = y - 36

    local previewBtn = BNB.CreateButton(nil, ct, "Preview", 100, 24)
    previewBtn:SetPoint("TOPLEFT", ct, "TOPLEFT", PAD, y)
    previewBtn:SetScript("OnClick", function()
        M.ShowPreview(sel)
    end)

    local confirmBtn = BNB.CreateButton(nil, ct, "Migrate Now", 110, 24)
    confirmBtn:SetPoint("BOTTOMRIGHT", ct, "BOTTOMRIGHT", -PAD, PAD)
    confirmBtn:SetScript("OnClick", function()
        f:Hide()
        M.Run(sel)
    end)

    -- Resize to fit
    f:SetHeight(math.abs(y) + 24 + PAD + 24 + PAD)

    _addonPopup = f
    f:Show()
end

-- ── Login popup ───────────────────────────────────────────────────────────────
local _popup

function M.ShowPopup()
    local available = M.DetectAvailable()
    if #available == 0 then return end

    if _popup then _popup:Hide() end

    local skinMode = BigNoteBoxDB and BigNoteBoxDB.skinMode
    local f, titleH

    -- Window
    if skinMode then
        f = BNB.CreateSkinFrame(UIParent, false, "BNBMigratePopupFrame", false)
        f:SetFrameStrata("DIALOG"); f:SetToplevel(true)
        local titleBar = BNB.CreateSkinStrip(f, true, false)
        titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
        titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
        titleBar:SetHeight(28)
        titleBar:EnableMouse(true)
        titleBar:RegisterForDrag("LeftButton")
        titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
        titleBar:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)
        local tl = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        tl:SetPoint("CENTER", titleBar, "CENTER", -12, 0)
        tl:SetTextColor(1, 0.82, 0)
        tl:SetText("Migrate to BigNoteBox")
        f._titleLbl = tl
        local xBtn = CreateFrame("Button", nil, titleBar, "UIPanelButtonTemplate")
        xBtn:SetSize(24, 22); xBtn:SetPoint("RIGHT", titleBar, "RIGHT", 0, 0)
        xBtn:SetText("X"); xBtn:SetScript("OnClick", function() f:Hide() end)
        titleH = 28
        f:SetScript("OnShow", function() BNB.ApplyMainWindowSkin() end)
    else
        f = CreateFrame("Frame", "BNBMigratePopupFrame", UIParent, "ButtonFrameTemplate")
        f:SetFrameStrata("DIALOG"); f:SetToplevel(true)
        ButtonFrameTemplate_HidePortrait(f)
        ButtonFrameTemplate_HideButtonBar(f)
        if f.Inset then f.Inset:Hide() end
        f:SetTitle("Migrate to BigNoteBox")
        if f.CloseButton then f.CloseButton:SetScript("OnClick", function() f:Hide() end) end
        titleH = 32
    end

    f:SetSize(WIN_W, 100)  -- height set at end
    f:SetMovable(true); f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    f:SetPoint("CENTER")
    tinsert(UISpecialFrames, "BNBMigratePopupFrame")

    local ct  = f
    local CW  = WIN_W - PAD * 2
    local y   = -(titleH + 12)

    -- Logo
    local logo = ct:CreateTexture(nil, "ARTWORK")
    logo:SetSize(80, 80)
    logo:SetPoint("TOP", ct, "TOP", 0, y)
    logo:SetTexture(ASSETS .. "logo")
    y = y - 88

    -- Title
    local titleLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleLbl:SetPoint("TOP", ct, "TOP", 0, y)
    titleLbl:SetJustifyH("CENTER")
    titleLbl:SetTextColor(1, 0.82, 0)
    titleLbl:SetText("Migrate to BigNoteBox")
    y = y - 26

    -- "You currently have X" line
    local addonNames = {}
    for _, k in ipairs(available) do tinsert(addonNames, ADDON_NAMES[k]) end
    local detectedLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    detectedLbl:SetPoint("TOP", ct, "TOP", 0, y)
    detectedLbl:SetWidth(CW); detectedLbl:SetJustifyH("CENTER"); detectedLbl:SetWordWrap(true)
    detectedLbl:SetTextColor(0.9, 0.9, 0.9)
    local addonList = table.concat(addonNames, ", ")
    detectedLbl:SetText("You currently have |cff66bb6a" .. addonList .. "|r, why not move it all to BNB?")
    y = y - 36

    -- Explanatory text
    local explainLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    explainLbl:SetPoint("TOPLEFT", ct, "TOPLEFT", PAD, y)
    explainLbl:SetWidth(CW); explainLbl:SetJustifyH("LEFT"); explainLbl:SetWordWrap(true)
    explainLbl:SetTextColor(0.7, 0.7, 0.7)
    explainLbl:SetText("Moving your notes to BigNoteBox keeps everything in one place. Your notes in other addons are not touched as this is a copy, not a move. A UI reload is required after migration. You can safely disable and/or remove the other addons after migration.")
    y = y - 56

    -- Separator
    local sep = ct:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1); sep:SetPoint("TOPLEFT", ct, "TOPLEFT", PAD, y)
    sep:SetPoint("TOPRIGHT", ct, "TOPRIGHT", -PAD, y)
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset then
        local p = BNB.GetSkinPreset()
        local br, bg_, bb = BNB.SkinBorderOf(p)
        sep:SetColorTexture(br, bg_, bb, 0.8)
        BNB.RegisterSkinRule(sep, 0.8)
    else
        sep:SetColorTexture(0.3, 0.3, 0.3, 0.8)
    end
    y = y - 14

    -- Per-addon checkboxes + sub-options
    local sel            = {}
    local declinedCbs    = {}  -- "don't ask again" checkboxes
    local addonCbs       = {}
    local migrateBtn     -- forward ref
    local previewBtn     -- forward ref

    local function RefreshMigrateBtn()
        if not migrateBtn then return end
        local any = false
        for _, k in ipairs(available) do
            if sel[k] then any = true; break end
        end
        migrateBtn:SetEnabled(any)
    end

    local function RefreshPreviewBtn()
        if not previewBtn then return end
        local any = false
        for _, k in ipairs(available) do
            if sel[k] then any = true; break end
        end
        previewBtn:SetEnabled(any)
    end

    for _, k in ipairs(available) do
        sel[k] = false

        local cb = CreateFrame("CheckButton", nil, ct, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("TOPLEFT", ct, "TOPLEFT", PAD - 2, y + 2)
        cb:SetChecked(false)
        local cbLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        cbLbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        cbLbl:SetText("Migrate " .. (ADDON_NAMES[k] or k))
        addonCbs[k] = cb
        y = y - 30

        -- NotepadChar / QuickNotes info text (per-character scope)
        if k == "NotepadChar" or k == "QuickNotes" then
            local infoLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            infoLbl:SetPoint("TOPLEFT", ct, "TOPLEFT", PAD + 18, y)
            infoLbl:SetWidth(WIN_W - PAD * 2 - 18)
            infoLbl:SetJustifyH("LEFT")
            infoLbl:SetWordWrap(true)
            infoLbl:SetTextColor(0.5, 0.5, 0.5)
            infoLbl:SetText("Per-character notes only import for the currently logged-in character. Log in with each character to migrate their notes.")
            y = y - 30
        end

        -- TakeANote sub-option (initially hidden)
        local catCb, catLbl
        if k == "TakeANote" then
            sel.takeANoteCategoryTags = false
            catCb = CreateFrame("CheckButton", nil, ct, "UICheckButtonTemplate")
            catCb:SetSize(20, 20)
            catCb:SetPoint("TOPLEFT", ct, "TOPLEFT", PAD + 18, y + 2)
            catCb:SetChecked(false)
            catCb:SetEnabled(false)
            catCb:SetAlpha(0.4)
            catLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            catLbl:SetPoint("LEFT", catCb, "RIGHT", 4, 0)
            catLbl:SetText("Use category names as tags")
            catLbl:SetTextColor(0.5, 0.5, 0.5)
            catCb:SetScript("OnClick", function(self)
                sel.takeANoteCategoryTags = self:GetChecked() and true or false
            end)
            y = y - 26
        end

        -- Wire addon checkbox
        local _catCb, _catLbl = catCb, catLbl
        cb:SetScript("OnClick", function(self)
            sel[k] = self:GetChecked() and true or false
            if _catCb then
                _catCb:SetEnabled(sel[k])
                _catCb:SetAlpha(sel[k] and 1.0 or 0.4)
                if _catLbl then
                    _catLbl:SetTextColor(sel[k] and 0.9 or 0.5, sel[k] and 0.9 or 0.5, sel[k] and 0.9 or 0.5)
                end
            end
            RefreshMigrateBtn()
            RefreshPreviewBtn()
        end)
    end

    y = y - 8

    -- Preview button (disabled until at least one addon is checked)
    previewBtn = BNB.CreateButton(nil, ct, "Preview", 100, 24)
    previewBtn:SetEnabled(false)
    previewBtn:SetPoint("TOPLEFT", ct, "TOPLEFT", PAD, y)
    previewBtn:SetScript("OnClick", function()
        M.ShowPreview(sel)
    end)
    y = y - 36

    -- "Don't ask again" per addon
    local daaY = y
    local daaLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    daaLbl:SetPoint("TOPLEFT", ct, "TOPLEFT", PAD, daaY)
    daaLbl:SetTextColor(0.5, 0.5, 0.5)
    daaLbl:SetText("Don't ask again:")
    daaY = daaY - 24

    for _, k in ipairs(available) do
        local daaCb = CreateFrame("CheckButton", nil, ct, "UICheckButtonTemplate")
        daaCb:SetSize(20, 20)
        daaCb:SetPoint("TOPLEFT", ct, "TOPLEFT", PAD - 2, daaY + 2)
        daaCb:SetChecked(false)
        local daaItemLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        daaItemLbl:SetPoint("LEFT", daaCb, "RIGHT", 4, 0)
        daaItemLbl:SetText(ADDON_NAMES[k] or k)
        daaItemLbl:SetTextColor(0.55, 0.55, 0.55)
        declinedCbs[k] = daaCb
        daaY = daaY - 24
    end

    -- The "don't ask" block sits below preview; track the bottom
    local contentBottom = math.min(y, daaY) - 16

    -- Reload warning, pinned above migrate button
    local warnLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    warnLbl:SetPoint("BOTTOMRIGHT", ct, "BOTTOMRIGHT", -PAD, PAD + 32)
    warnLbl:SetJustifyH("RIGHT")
    warnLbl:SetTextColor(1, 0.6, 0.0)
    warnLbl:SetText("|cffff9900Warning:|r UI will reload after migration.")

    -- Migrate Now button, pinned to bottom centre
    migrateBtn = BNB.CreateButton(nil, ct, "Migrate Now", 120, 26)
    migrateBtn:SetPoint("BOTTOM", ct, "BOTTOM", 49, PAD)  -- shifts right so pair midpoint is at centre
    migrateBtn:SetEnabled(false)
    migrateBtn:SetScript("OnClick", function()
        -- Apply "don't ask again" for checked boxes on all available addons
        local db = BigNoteBoxDB
        db.migrationDeclined = db.migrationDeclined or {}
        for _, k in ipairs(available) do
            if declinedCbs[k] and declinedCbs[k]:GetChecked() then
                db.migrationDeclined[k] = true
            end
        end
        f:Hide()
        M.Run(sel)
    end)

    -- Cancel: anchored left of Migrate Now, together they are centred
    local cancelBtn = BNB.CreateButton(nil, ct, "Not Now", 90, 26)
    cancelBtn:SetPoint("RIGHT", migrateBtn, "LEFT", -8, 0)
    cancelBtn:SetScript("OnClick", function()
        local db = BigNoteBoxDB
        db.migrationDeclined = db.migrationDeclined or {}
        for _, k in ipairs(available) do
            if declinedCbs[k] and declinedCbs[k]:GetChecked() then
                db.migrationDeclined[k] = true
            end
        end
        f:Hide()
    end)

    -- Total height: from top to content bottom + space for buttons
    local totalH = math.abs(contentBottom) + 26 + PAD * 2 + titleH
    f:SetHeight(totalH)

    _popup = f
    f:Show()
end

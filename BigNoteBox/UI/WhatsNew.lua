-- BigNoteBox UI/WhatsNew.lua
--
-- Patch notes. Since ALL-614 (Dukul, 2026-10-29) they live in the Help book's
-- Patch notes tab (UI/HelpBook.lua), one page per release, so they no longer
-- fill the note list: the Patch notes system folder (ALL-511) and the old
-- "What's New?" window are gone. An update shows a toast that waits for a
-- click and opens that release in the Help book.
--
-- PUBLIC API:
--   BNB.WhatsNew.Open()                    -- the Help book at the newest release
--                                             (Settings > General version button,
--                                             /bnb whatsnew, the bnbui:whatsnew link)
--   BNB.WhatsNew.Releases()                -- { { version, time, lines }, ... } newest
--                                             first, this client's lines only
--   BNB.WhatsNew.PatchBody(version, lines, rich)  -- a release as note text
--   BNB.WhatsNew.CheckAndShow(newInstall)  -- called on login; the toast if the version is new
--
-- DATA:
--   BNB.PATCH_NOTES  (defined in UI/WhatsNewData.lua)
--     .version  string  -- must match BNB.ADDON_VERSION to trigger the toast
--     .entries  table   -- array, one per bullet. A plain string shows on every client;
--                          { forever = true, "text" } / { retail = true, "text" } shows on
--                          that client only (BNB.IsForever). A release with no lines for
--                          this client shows no toast.
--   BNB.PATCH_HISTORY (UI/PatchHistory.lua, generated at each release tag)
--
-- PERSISTENCE:
--   BigNoteBoxDB.lastSeenWhatsNewVersion  -- from the old window, no longer written or read
--   NotesDB().patchNote = { version, id, sum }  -- the version seen; id / sum = the
--                         last pinned patch note (before ALL-511), until it is gone

local BNB = BigNoteBox
local L   = BNB.L

BNB.WhatsNew = BNB.WhatsNew or {}
local WN = BNB.WhatsNew

-- ── Entries for this client ──────────────────────────────────────────────────
-- Drops lines tagged for the other client and unwraps tagged ones to their text.
local function ClientEntries(entries)
    local out = {}
    for _, entry in ipairs(entries or {}) do
        if type(entry) == "string" then
            out[#out + 1] = entry
        elseif type(entry) == "table" and type(entry[1]) == "string" then
            local show
            if entry.forever then show = BNB.IsForever
            elseif entry.classic then show = BNB.IsClassic   -- ALL-168
            elseif entry.retail then show = not (BNB.IsForever or BNB.IsClassic)
            else show = true end
            if show then out[#out + 1] = entry[1] end
        end
    end
    return out
end

-- ── Patch note (ALL-409, ALL-511) ────────────────────────────────────────────
-- An update shows a toast that waits for a click (source "patchnotes", so it
-- follows the Toasts module) and opens the release in the Help book's Patch
-- notes tab (ALL-614; before it the Patch notes system folder, ALL-511).
--
-- From ALL-409 to ALL-511 the release became a pinned, favourite, Global
-- note tagged Bnb / V1.23.0 / V1.23. That last note goes at the next update
-- unless the player made it theirs: NotesDB().patchNote = { version, id, sum }
-- (in the active notes set, so dev mode has its own), sum = a checksum of the
-- title and body as written; it is deleted only while that still matches and
-- the Bnb tag is on it. Pin / favourite do not count.
local PN_TAG    = "BNB"
local PN_GREEN  = "66bb6a"
local PN_ORDER  = { "New", "Change", "Fixed" }   -- other labels follow, as found
local PN_LABELS = { Changed = "Change", Added = "New" }   -- spellings WhatsNewData allows (Added: 1.6.9 to 1.7.x)

local function Checksum(note)
    local s = (note.title or "") .. "\n" .. (note.body or "")
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
    return h
end

local function HasTag(note, tag)
    for _, t in ipairs(note.tags or {}) do
        if t == tag then return true end
    end
    return false
end

-- "|cff66bb6aNew:|r text" -> "New", "text"; a line with no label -> "", line
local function SplitLabel(entry)
    local label, text = entry:match("^|c%x%x%x%x%x%x%x%x(%a+):|r%s*(.*)$")
    if not label then label, text = entry:match("^(%a+):%s+(.*)$") end
    if not label then return "", entry end
    return PN_LABELS[label] or label, text
end

-- Colour codes in a line: markup for a rich note, gone from a plain one.
-- Braces become parentheses first in a rich note, so text such as "{p}" in
-- a patch line is never read as a tag (a repair would change the body).
-- A note token ({{me}}, {{item:6948}}) is kept and escaped instead, so it
-- shows as written and is never filled (ALL-493: it read "((me))").
-- A link to a part of BigNoteBox ({link*bnbui:<key>*<text>}, ALL-617) is kept
-- too: a line can send the player straight to a Settings page. The text has
-- no braces; empty = the place's name (Settings > Modules > Spelling).
local UILINK_PAT = "{link%*bnbui:([%w%._%-]+)%*([^{}%*]*)}"

local function LineText(text, rich)
    if rich then
        local toks, links = {}, {}
        -- An already escaped \{{x}} is taken as it is (one backslash, not two)
        text = text:gsub("\\?{{(%a[%w_]*:?[^{}\n]*)}}", function(inner)
            toks[#toks + 1] = inner
            return "@@BNBTOK" .. #toks .. "@@"
        end)
        text = text:gsub(UILINK_PAT, function(key, label)
            links[#links + 1] = "{link*bnbui:" .. key .. "*" .. label .. "}"
            return "@@BNBLINK" .. #links .. "@@"
        end)
        text = text:gsub("{", "("):gsub("}", ")")
        text = text:gsub("@@BNBTOK(%d+)@@", function(n) return "\\{{" .. toks[tonumber(n)] .. "}}" end)
        text = text:gsub("@@BNBLINK(%d+)@@", function(n) return links[tonumber(n)] end)
        text = text:gsub("|c%x%x(%x%x%x%x%x%x)", "{col:%1}"):gsub("|r", "{/col}")
    else
        text = text:gsub(UILINK_PAT, function(key, label)
            if label ~= "" then return label end
            local UL = BNB.UILinks
            return UL and UL.Label(key) or key
        end)
        text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    end
    return text
end

local function PatchBody(version, entries, rich)
    local groups, order = {}, {}
    for _, label in ipairs(PN_ORDER) do groups[label] = {} end
    for _, entry in ipairs(entries) do
        local label, text = SplitLabel(entry)
        if not groups[label] then groups[label] = {}; order[#order + 1] = label end
        table.insert(groups[label], text)
    end
    -- Unlabelled lines first, then New / Change / Fixed, then any other label
    local seq = {}
    if groups[""] then seq[1] = "" end
    for _, label in ipairs(PN_ORDER) do seq[#seq + 1] = label end
    for _, label in ipairs(order) do
        if label ~= "" then seq[#seq + 1] = label end
    end

    local heading = string.format(L["PN_NOTE_HEADING"], version)
    local out = { rich and ("{h1}" .. heading .. "{/h1}") or heading }
    for _, label in ipairs(seq) do
        local lines = groups[label]
        if #lines > 0 then
            if label ~= "" then
                if rich then
                    out[#out + 1] = "{h3}{col:" .. PN_GREEN .. "}" .. label .. "{/col}{/h3}"
                else
                    out[#out + 1] = ""
                    out[#out + 1] = label
                end
            elseif not rich then
                out[#out + 1] = ""
            end
            for _, text in ipairs(lines) do
                local bullet = rich and ("{col:" .. PN_GREEN .. "}-{/col} ") or "- "
                out[#out + 1] = bullet .. LineText(text, rich)
            end
        end
    end
    return table.concat(out, "\n")
end

WN.PatchBody = PatchBody

-- A release as rows for the Help book's chips: { { label = "New" / "Change" /
-- "Fixed" / other / "", text = the line as markup (rich) or plain } }, in the
-- same order as PatchBody: unlabelled lines, New, Change, Fixed, then others
function WN.PatchRows(entries, rich)
    local groups, order = {}, {}
    for _, label in ipairs(PN_ORDER) do groups[label] = {} end
    for _, entry in ipairs(entries) do
        local label, text = SplitLabel(entry)
        if not groups[label] then groups[label] = {}; order[#order + 1] = label end
        table.insert(groups[label], text)
    end
    local seq = {}
    if groups[""] then seq[1] = "" end
    for _, label in ipairs(PN_ORDER) do seq[#seq + 1] = label end
    for _, label in ipairs(order) do
        if label ~= "" then seq[#seq + 1] = label end
    end
    local rows = {}
    for _, label in ipairs(seq) do
        for _, text in ipairs(groups[label]) do
            rows[#rows + 1] = { label = label, text = LineText(text, rich) }
        end
    end
    return rows
end

-- ── Releases (ALL-614) ───────────────────────────────────────────────────────
-- Every release in UI/PatchHistory.lua (newest first, made from the release
-- tags by _work/tools/patch-history.lua), with the release in WhatsNewData.lua
-- on top while the history file does not have it yet. Only this client's
-- lines; a release with none is left out. For the Help book's Patch notes tab.
function WN.Releases()
    local list, seen = {}, {}
    local function Add(version, entries, when)
        if seen[version] then return end
        seen[version] = true
        local lines = ClientEntries(entries)
        if #lines == 0 then return end
        list[#list + 1] = { version = version, time = when, lines = lines }
    end
    local cur  = BNB.PATCH_NOTES
    local hist = BNB.PATCH_HISTORY or {}
    if cur and cur.version then
        local inHist
        for _, r in ipairs(hist) do
            if r.version == cur.version then inHist = true; break end
        end
        if not inHist then Add(cur.version, cur.entries, nil) end
    end
    for _, r in ipairs(hist) do Add(r.version, r.entries, r.time) end
    return list
end

-- The Help book at the newest release (the version button, /bnb whatsnew)
function WN.Open()
    if BNB.HelpBook and BNB.HelpBook.OpenPatchNotes then BNB.HelpBook.OpenPatchNotes() end
end

-- The last pinned patch note goes, unless the player made it theirs; either
-- way its bookkeeping is done with (no new one is made since ALL-511)
local function RemoveOldPatchNote(ndb)
    local pn = ndb.patchNote
    if type(pn) ~= "table" then return end
    local id, sum = pn.id, pn.sum
    pn.id, pn.sum = nil, nil
    local old = id and ndb.notes and ndb.notes[id]
    if not old then return end
    if not HasTag(old, BNB.NormalizeTag(PN_TAG)) then return end
    if Checksum(old) ~= sum then return end
    BNB.DeleteNote(id, true)
end

-- A note from BigNoteBox itself (the welcome note; the patch note until ALL-511): Global, pinned,
-- favourite, and made nowhere, so no creation spot
local function MakeAddonNote(title, body, rich, tags)
    local id = BNB.CreateNote(title, body)
    if not id then return nil end
    BNB.UpdateNote(id, {
        scope = "global", tags = tags,
        pinned = true, favorited = true, richMode = rich,
        _clear = { "coordX", "coordY", "coordMapID", "coordZone", "coordSubzone" },
    })
    return id
end

local function ShowPatchToast(version)
    if not (BNB.Toast and BNB.Toast.Show) then return end
    BNB.Toast.Show({
        key    = "patchnotes",
        source = "patchnotes",
        title  = L["PN_TOAST_TITLE"],
        text   = string.format(L["PN_TOAST_TEXT"], version),
        hold   = 0,   -- waits for a click
        onClick = function()
            -- That release in the Help book's Patch notes tab (ALL-614)
            if BNB.HelpBook and BNB.HelpBook.OpenPatchNotes then BNB.HelpBook.OpenPatchNotes(version) end
        end,
    })
end

-- ── Public: CheckAndShow ──────────────────────────────────────────────────────
-- Called on login after Initialize(). Once per version per notes set: removes
-- the last pinned patch note (from before ALL-511) and shows the toast.
-- newInstall = setup not done yet: the version is only stamped, a new player
-- gets no toast for the version they installed.
function WN.CheckAndShow(newInstall)
    local data = BNB.PATCH_NOTES
    if not data or not data.version then return end
    local ndb = BNB.NotesDB and BNB.NotesDB()
    if type(ndb) ~= "table" or type(ndb.notes) ~= "table" then return end
    local pn = ndb.patchNote
    if type(pn) == "table" and pn.version == data.version then return end
    if type(pn) ~= "table" then pn = {} end
    pn.version = data.version
    ndb.patchNote = pn
    if newInstall then return end
    -- Nothing for this client in this release (e.g. a Forever-only patch on
    -- Retail): the last patch note stays
    local entries = ClientEntries(data.entries)
    if #entries == 0 then return end
    RemoveOldPatchNote(ndb)
    ShowPatchToast(data.version)
end

-- ── Welcome note (ALL-242) ───────────────────────────────────────────────────
-- Dukul's note to a new player, made once on a fresh install: Horde, Alliance
-- or (a Pandaren before choosing) Neutral text, the Forever line on Forever
-- only. Rich: "BigNoteBox" in BNB green, the site names linked, greeting and
-- sign-off in the faction colour, "Dukul" in shaman blue. Plain (Rich Notes
-- off): the URLs written out in brackets after each site name.
local WELCOME_SHAMAN = "0070dd"
local WELCOME_FACTION = {
    Horde    = { col = "ff5040", greet = "WNOTE_GREET_HORDE",    bye = "WNOTE_BYE_HORDE" },
    Alliance = { col = "4da3ff", greet = "WNOTE_GREET_ALLIANCE", bye = "WNOTE_BYE_ALLIANCE" },
    Neutral  = { col = "d8b45a", greet = "WNOTE_GREET_NEUTRAL",  bye = "WNOTE_BYE_NEUTRAL" },
}

-- Every plain-text occurrence of find in s replaced by repl (no patterns:
-- "Wago.io" has a dot)
local function ReplacePlain(s, find, repl)
    local out, pos = {}, 1
    while true do
        local st, en = s:find(find, pos, true)
        if not st then break end
        out[#out + 1] = s:sub(pos, st - 1)
        out[#out + 1] = repl
        pos = en + 1
    end
    out[#out + 1] = s:sub(pos)
    return table.concat(out)
end

-- One paragraph: the site names linked (rich) or followed by their URL
-- (plain), "BigNoteBox" green (rich). Site names go through placeholders
-- first, so the green never lands inside a URL
local function WelcomeText(text, rich)
    if not rich then
        for _, site in ipairs(BNB.SITE_LINKS) do
            text = ReplacePlain(text, site.name, site.name .. " (" .. site.url .. ")")
        end
        return text
    end
    text = text:gsub("{", "("):gsub("}", ")")   -- a translation is never read as markup
    for i, site in ipairs(BNB.SITE_LINKS) do
        text = ReplacePlain(text, site.name, "@@SITE" .. i .. "@@")
    end
    text = ReplacePlain(text, "BigNoteBox", "{col:" .. PN_GREEN .. "}BigNoteBox{/col}")
    for i, site in ipairs(BNB.SITE_LINKS) do
        text = ReplacePlain(text, "@@SITE" .. i .. "@@", "{link*" .. site.url .. "*" .. site.name .. "}")
    end
    return text
end

local function WelcomeBody(faction, rich)
    local f = WELCOME_FACTION[faction] or WELCOME_FACTION.Neutral
    local paras = {
        L[BNB.IsForever and "WNOTE_P1_FOREVER" or "WNOTE_P1"],
        L["WNOTE_P2"],
        L["WNOTE_P3"],
    }
    local greet, bye = L[f.greet], L[f.bye]
    local out = {}
    if rich then
        out[1] = "{h2}{col:" .. f.col .. "}" .. WelcomeText(greet, true) .. "{/col}{/h2}"
        for _, p in ipairs(paras) do out[#out + 1] = WelcomeText(p, true) end
        out[#out + 1] = "{p:r}{col:" .. f.col .. "}" .. WelcomeText(bye, true) .. "{/col}{br}{col:"
            .. WELCOME_SHAMAN .. "}Dukul{/col}{/p}"
    else
        out[1] = greet
        for _, p in ipairs(paras) do
            out[#out + 1] = ""
            out[#out + 1] = WelcomeText(p, false)
        end
        out[#out + 1] = ""
        out[#out + 1] = bye
        out[#out + 1] = "Dukul"
    end
    return table.concat(out, "\n")
end

-- Called on login with CheckAndShow. Decided once per account (settings
-- flag welcomeNoteDone, kept out of DEFAULTS: nil = not decided yet): a
-- fresh install with no notes gets the note, an existing install only the
-- flag, so a deleted welcome note never comes back. force (Developer tools):
-- make it now, whatever the flag and the notes say.
function WN.CheckWelcome(newInstall, force)
    local db = BigNoteBoxDB
    if not db then return end
    local ndb = BNB.NotesDB and BNB.NotesDB()
    if type(ndb) ~= "table" or type(ndb.notes) ~= "table" then return end
    if not force then
        if db.welcomeNoteDone then return end
        db.welcomeNoteDone = true
        if not newInstall or next(ndb.notes) then return end
    end
    local rich = BNB.RichEnabled and BNB.RichEnabled() or false
    local faction = UnitFactionGroup("player")
    local id = MakeAddonNote(L["WNOTE_TITLE"], WelcomeBody(faction, rich), rich,
        { BNB.NormalizeTag(PN_TAG), BNB.NormalizeTag("Welcome") })
    if not id then return end
    db.welcomeToastPending = id
    WN.ShowWelcomeToast()
end

-- The welcome note's toast waits for the end of setup: the note is made at
-- the first login, under the wizard, and the toast shows once setup is done
-- (the wizard's Quit, or the login after Finish, which reloads). Pending =
-- BigNoteBoxDB.welcomeToastPending (the note id), cleared when it shows.
-- Waits for a click, as the patch note's does, and follows the same
-- toastSources switch ("Messages from BigNoteBox").
function WN.ShowWelcomeToast()
    local db = BigNoteBoxDB
    local id = db and db.welcomeToastPending
    if not id or db.setupComplete ~= true then return end
    db.welcomeToastPending = nil
    if not (BNB.GetNote(id) and BNB.Toast and BNB.Toast.Show) then return end
    BNB.Toast.Show({
        key    = "welcome",
        source = "patchnotes",
        title  = L["WNOTE_TITLE"],
        text   = L["WNOTE_TOAST_TEXT"],
        hold   = 0,
        onClick = function()
            if BNB.OpenNoteInMain and BNB.GetNote(id) then BNB.OpenNoteInMain(id) end
        end,
    })
end

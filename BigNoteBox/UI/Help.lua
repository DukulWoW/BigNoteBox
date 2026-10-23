-- BigNoteBox UI/Help.lua - the Help system folder (ALL-512)
--
-- The help topics as read-only notes in a Help folder after Patch notes
-- (Core/SystemNotes.lua). The topics are written in doc mode (BigNoteBox_Dev,
-- a third notes set) and turned into UI/HelpData.lua by
-- _work/tools/docs-build.lua, so nothing here is saved. Decided with Dukul,
-- 2026-10-19: one Help folder, topics in doc mode's own order; each topic has
-- a fixed key the script makes from its first title; the folder can be hidden
-- (Settings > Modules > Folders), never a single topic, and a help link still
-- opens a topic while it is hidden. While there are no topics the folder does
-- not show (the list skips an empty system folder).
--
-- A topic: { key, src, title, body, rich, clients = { retail, forever,
-- classic } or nil (= every client), chapter = a chapter key or nil }. A
-- translation, when one exists, is BNB.HELP_LOCALES[locale][key] = { title,
-- body } (Locales/Help/<locale>.lua); a topic it does not have stays English.
-- A chapter of the help book (ALL-554 stage 2, a doc-mode folder): { key,
-- src, name, body, rich, icon } in BNB.HELP_CHAPTERS, body / icon from the
-- folder's Cover note; its translation is HELP_LOCALES[locale]["chapter." ..
-- key] = { name, body } (topic keys have no dot, so the two never meet).
--
-- Public API:
--   BNB.HelpNoteID(key)       "sys-help-<key>"
--   BNB.HelpTopic(key)        the topic on this client, or nil
--   BNB.HelpTopics()          every topic on this client, in order
--   BNB.OpenHelp(key)         opens it in the main window; false when unknown
--   BNB.HelpTopicText(t)      title, body (translated, pictures expanded)
--   BNB.HelpChapters()        chapters, loose: { { ch, topics }, ... } with a
--                             topic on this client, in order; loose = the
--                             topics in no chapter, in order
--   BNB.HelpChapterText(ch)   name, body (translated, pictures expanded)

local BNB = BigNoteBox
local L   = BNB.L

local PREFIX = "sys-help-"

BNB.HELP_LOCALES = BNB.HELP_LOCALES or {}

function BNB.HelpNoteID(key) return PREFIX .. tostring(key) end

local function ClientOK(t)
    local c = t.clients
    if type(c) ~= "table" then return true end
    if BNB.IsForever then return c.forever == true end
    if BNB.IsClassic then return c.classic == true end
    return c.retail == true
end

function BNB.HelpTopics()
    local out = {}
    for _, t in ipairs(BNB.HELP_TOPICS or {}) do
        if type(t) == "table" and t.key and ClientOK(t) then out[#out + 1] = t end
    end
    return out
end

function BNB.HelpTopic(key)
    for _, t in ipairs(BNB.HelpTopics()) do
        if t.key == key then return t end
    end
end

-- The reader's language when that topic is translated
local function Localized(t)
    local loc = BNB.HELP_LOCALES[GetLocale()]
    local tr = type(loc) == "table" and loc[t.key]
    if type(tr) ~= "table" then return t.title, t.body end
    return tr.title or t.title, tr.body or t.body
end

-- A topic's title and body as the reader sees them: translated when there
-- is a translation, Assets pictures expanded, markup kept (the help book,
-- UI/HelpBook.lua, ALL-554)
function BNB.HelpTopicText(t)
    local title, body = Localized(t)
    local AM = BNB.AdvancedMode
    body = AM and AM.ExpandAssetImages and AM.ExpandAssetImages(body or "") or (body or "")
    return title or t.key, body
end

-- The book's chapters on this client: a chapter none of whose topics this
-- client has is left out; a topic whose chapter is unknown counts as loose
function BNB.HelpChapters()
    local byKey, out, loose = {}, {}, {}
    for _, ch in ipairs(BNB.HELP_CHAPTERS or {}) do
        if type(ch) == "table" and ch.key then byKey[ch.key] = { ch = ch, topics = {} } end
    end
    for _, t in ipairs(BNB.HelpTopics()) do
        local c = t.chapter and byKey[t.chapter]
        if c then c.topics[#c.topics + 1] = t else loose[#loose + 1] = t end
    end
    for _, ch in ipairs(BNB.HELP_CHAPTERS or {}) do
        local c = type(ch) == "table" and ch.key and byKey[ch.key]
        if c and #c.topics > 0 then out[#out + 1] = c end
    end
    return out, loose
end

function BNB.HelpChapterText(ch)
    local loc = BNB.HELP_LOCALES[GetLocale()]
    local tr = type(loc) == "table" and loc["chapter." .. tostring(ch.key)]
    local name, body = ch.name, ch.body
    if type(tr) == "table" then name, body = tr.name or name, tr.body or body end
    local AM = BNB.AdvancedMode
    body = AM and AM.ExpandAssetImages and AM.ExpandAssetImages(body or "") or (body or "")
    return name or ch.key, body
end

local function BuildHelpFolder(rich)
    local AM = BNB.AdvancedMode
    local list = {}
    for i, t in ipairs(BNB.HelpTopics()) do
        local title, body = Localized(t)
        -- {img:@UI/name:w:h}: a picture from BigNoteBox's Assets folder,
        -- allowed in help topics only (Features/AdvancedMode.lua)
        body = AM and AM.ExpandAssetImages and AM.ExpandAssetImages(body or "") or (body or "")
        -- Rich Notes off: a rich topic shows its text without the markup
        if t.rich and not rich and AM and AM.StripMarkup then body = AM.StripMarkup(body) end
        list[#list + 1] = {
            id       = PREFIX .. t.key,
            title    = title or t.key,
            body     = body,
            richMode = (t.rich and rich) and true or false,
            created  = (BNB.HELP_BUILT or time()) - i,   -- keeps the order in a date sort
            sysItem  = t.key,
        }
    end
    return list
end

if BNB.SystemNotes then
    BNB.SystemNotes.Register({
        key = "help", order = 20, name = "SYS_FOLDER_HELP",
        setting = "sysHelp", prefix = PREFIX, canHide = false,
        r = 0x6c / 255, g = 0xb4 / 255, b = 0xee / 255,   -- the note link blue
        icon = "Interface\\Icons\\INV_Misc_QuestionMark",
        Build = BuildHelpFolder,
    })
end

function BNB.OpenHelp(key)
    if not BNB.HelpTopic(key) then
        BNB:Print(string.format(L["HELP_NOT_FOUND_FMT"], tostring(key)))
        return false
    end
    local SYS = BNB.SystemNotes
    if SYS then SYS.Reveal("help") end   -- also while the folder is hidden
    if BNB.OpenNoteInMain then BNB.OpenNoteInMain(PREFIX .. key) end
    return true
end

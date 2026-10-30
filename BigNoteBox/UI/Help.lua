-- BigNoteBox UI/Help.lua - the help topics (ALL-512)
--
-- The help topics, read in the Help book (UI/HelpBook.lua, ALL-554). Until
-- 2026-10-30 they were also read-only notes in a Help system folder after
-- your notes; that folder is gone (ALL-554 stage 4, Dukul: "Remove it").
-- The topics are written in doc mode (BigNoteBox_Dev, a third notes set) and
-- turned into UI/HelpData.lua by _work/tools/docs-build.lua, so nothing here
-- is saved. Topics keep doc mode's own order; each topic has a fixed key the
-- script makes from its first title.
--
-- A topic: { key, src, title, body, rich, clients = { retail, forever,
-- classic } or nil (= every client), chapter = a chapter key or nil, back =
-- true for the back of the book (after the chapters, the Glossary) }. A
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
--   BNB.OpenHelp(key)         opens it in the Help book; false when unknown
--   BNB.HelpLinkAsUI(link)    "bnbnote:sys-help-<key>" -> "bnbui:help.<key>"
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

-- The help lives in the Help book only (ALL-554 stage 4, 2026-10-30): the
-- Help system folder in the note list is gone, so a topic opens there
function BNB.OpenHelp(key)
    if not BNB.HelpTopic(key) then
        BNB:Print(string.format(L["HELP_NOT_FOUND_FMT"], tostring(key)))
        return false
    end
    if not BNB.HelpBook then return false end
    BNB.HelpBook.Open(key)
    return true
end

-- A "sys-help-<key>" note link (made while the Help folder existed, and the
-- book's own chapter lists) as the matching "bnbui:help.<key>" link, so a
-- note link to a topic opens it in the book; any other link as it was
function BNB.HelpLinkAsUI(link)
    local key = type(link) == "string" and link:match("^bnbnote:sys%-help%-(.+)$")   -- PREFIX
    return key and ("bnbui:help." .. key) or link
end

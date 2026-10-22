-- BigNoteBox Features/UILinks.lua - links that open a part of BigNoteBox (ALL-513)
--
-- A UI link names a place by a fixed key ("settings.modules.situations",
-- "help.situations", "oracle"); a click opens it. Only the keys in this file
-- exist, and each one only opens our own windows and pages: a note never runs
-- anything, so every note may use them, shared ones too (Dukul, 2026-10-19).
-- Two forms reach the same click (Features/NoteLinks.lua, kind bnbui):
--   |cffffcc33|Hbnbui:<key>|h<text>|h|r      chat-style, plain and rich notes;
--                                             the link button's BigNoteBox list
--   {link*bnbui:<key>*<text>}                rich markup, typed; the text may be
--                                             an {icon:...}, a picture button
-- A key this version does not have, or a place this client or setup lacks (a
-- module that is off), draws grey in a rich note; its tooltip and its click
-- say why (Dukul, 2026-10-19). A plain note's link keeps the colour it was
-- written with (the text box shows the saved text).
--
-- Public API (BNB.UILinks):
--   UL.Register(key, def)   def = { label = L key or function, open = function,
--                           avail = function -> ok, why (L key or text) }, icon }
--   UL.State(key)           ok, why  (why = nil when ok, a sentence when not)
--   UL.Label(key)           "Settings > Modules > Situations", a topic's title...
--   UL.Open(key)            opens it, or prints why not; true when opened
--   UL.Link(key, text)      the chat-style link (text = UL.Label)
--   UL.Colour(key)          "ffrrggbb" for drawing it now
--   UL.List()               { { key, label, icon }, ... } for the picker
-- A new Settings sub-page with a key gets a line in SETTINGS below.

local BNB = BigNoteBox
local L   = BNB.L
local UL  = {}
BNB.UILinks = UL

UL.SCHEME = "bnbui:"
UL.COLOR  = "ffffcc33"   -- gold, apart from note links (blue) and waypoints (green)
UL.GREY   = "ff808080"

local GEAR = "Interface\\Icons\\INV_Misc_Gear_01"
local HELP = "Interface\\Icons\\INV_Misc_QuestionMark"

local _defs, _order = {}, {}

function UL.Register(key, def)
    if type(key) ~= "string" or type(def) ~= "table" then return end
    local k = key:lower()
    if not _defs[k] then _order[#_order + 1] = k end
    def.key = key
    _defs[k] = def
end

-- "help.<key>": the topics of UI/HelpData.lua on this client (ALL-512)
local function HelpDef(topicKey)
    local t = BNB.HelpTopic and BNB.HelpTopic(topicKey)
    if not t then return nil end
    return {
        key = "help." .. topicKey, icon = HELP,
        label = function()
            local n = BNB.GetNote and BNB.GetNote(BNB.HelpNoteID(topicKey))
            return string.format(L["UILINK_HELP_FMT"], (n and n.title) or t.title or topicKey)
        end,
        open = function() BNB.OpenHelp(topicKey) end,
    }
end

local function Def(key)
    if type(key) ~= "string" then return nil end
    key = key:lower()
    if _defs[key] then return _defs[key] end
    local topic = key:match("^help%.(.+)$")
    if topic then
        -- Topic keys are lower case already (the build script makes them)
        return HelpDef(topic)
    end
end

local function Text(v)
    if type(v) == "function" then return v() end
    if type(v) ~= "string" then return nil end
    if BNB.HasL(v) then return L[v] end
    return v
end

function UL.State(key)
    local d = Def(key)
    if not d then
        if type(key) == "string" and key:lower():find("^help%.") then return false, L["UILINK_NO_TOPIC"] end
        return false, L["UILINK_UNKNOWN"]
    end
    if d.avail then
        local ok, why = d.avail()
        if not ok then return false, Text(why) or L["UILINK_NOT_HERE"] end
    end
    return true
end

function UL.Label(key)
    local d = Def(key)
    return d and Text(d.label) or tostring(key)
end

function UL.Colour(key)
    return UL.State(key) and UL.COLOR or UL.GREY
end

function UL.Open(key)
    local ok, why = UL.State(key)
    if not ok then BNB:Print(why); return false end
    local d = Def(key)
    local done, err = pcall(d.open)
    if not done then geterrorhandler()(err); return false end
    return true
end

-- Text inside a link: no escape bar, one line (as NoteLinks' Clean)
local function Clean(s)
    s = tostring(s or ""):gsub("|", ""):gsub("[\r\n]", " ")
    return s
end

function UL.Link(key, text)
    return string.format("|c%s|H%s%s|h%s|h|r", UL.COLOR, UL.SCHEME, key, Clean(text or UL.Label(key)))
end

function UL.List()
    local out = {}
    for _, k in ipairs(_order) do
        local d = _defs[k]
        out[#out + 1] = { key = d.key, label = Text(d.label) or d.key, icon = d.icon or GEAR }
    end
    for _, t in ipairs(BNB.HelpTopics and BNB.HelpTopics() or {}) do
        local key = "help." .. t.key
        out[#out + 1] = { key = key, label = UL.Label(key), icon = HELP }
    end
    return out
end

-- ── The places ───────────────────────────────────────────────────────────────

local function ModuleOff(on, nameKey)
    return function()
        if on() then return true end
        return false, string.format(L["UILINK_MODULE_OFF_FMT"], L[nameKey])
    end
end

-- Settings: every tab, and the sub-pages that have a key (UI/ConfigWindow.lua
-- NewSubPage; Modules pages without their own key go by their mode key)
local SETTINGS = {
    { "general",    "CFG_TAB_GENERAL" },
    { "notes",      "CFG_TAB_NOTES", {
        { "templates", "CFG_TPL_TITLE" }, { "tokens", "CFG_TOKENS_TITLE" } } },
    { "appearance", "CFG_TAB_APPEARANCE" },
    { "modules",    "CFG_TAB_MODULES", {
        { "oracle", "CFG_HDR_ORACLE" }, { "stickies", "CFG_CELL_STICKY_HDR" },
        { "tasks", "CFG_HDR_TASKS" }, { "refBox", "CFG_HDR_REFBOX" },
        { "sidebar", "CFG_HDR_SIDEBAR" }, { "focus", "CFG_FOCUS_ORBIT_HEADER" },
        { "richNotes", "CFG_RICH_SIZES_HEADER" }, { "history", "CFG_HDR_NOTE_HISTORY" },
        { "trash", "CFG_HDR_TRASH" }, { "alarms", "CFG_HDR_ALARMS" },
        { "quickNote", "CFG_HDR_QUICK_NOTE" }, { "unitNotes", "CFG_SUB_PLAYER_NPC" },
        { "situations", "CFG_HDR_CONTEXT_POPUP" }, { "toasts", "CFG_HDR_TOASTS" },
        { "tldr", "CFG_HDR_TLDR" }, { "folders", "CFG_FOLDERS_HEADER" },
        { "explorer", "CFG_EXPLORER_HEADER" },
        { "contextMenu", "CFG_HDR_CONTEXT_MENU" }, { "placement", "CFG_HDR_PLACEMENT" },
        { "undo", "CFG_HDR_UNDO_REDO" }, { "accessibility", "CFG_HDR_ACCESSIBILITY" } } },
    { "backup",     "CFG_TAB_BACKUP" },
    { "advanced",   "CFG_TAB_ADVANCED", { { "integrations", "CFG_HDR_INTEGRATIONS" } } },
}

for _, tab in ipairs(SETTINGS) do
    local tabKey, tabLabel = tab[1], tab[2]
    UL.Register("settings." .. tabKey, {
        label = function() return string.format(L["UILINK_SETTINGS_FMT"], L[tabLabel]) end,
        open  = function() BNB.OpenSettingsPage(tabKey) end,
    })
    for _, pg in ipairs(tab[3] or {}) do
        local pageKey, pageLabel = pg[1], pg[2]
        UL.Register("settings." .. tabKey .. "." .. pageKey, {
            label = function()
                return string.format(L["UILINK_SETTINGS_PAGE_FMT"], L[tabLabel],
                    (L[pageLabel]:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
            end,
            open  = function() BNB.OpenSettingsPage(tabKey, pageKey) end,
        })
    end
end

UL.Register("oracle", {
    label = "CFG_HDR_ORACLE", icon = "Interface\\Icons\\INV_Misc_Spyglass_03",
    open  = function() BNB.Oracle.Open() end,
    avail = ModuleOff(function() return not (BigNoteBoxDB and BigNoteBoxDB.oracleEnabled == false) end,
        "CFG_HDR_ORACLE"),
})
UL.Register("tagmanager", {
    label = "TAG_MGR_TITLE", icon = "Interface\\Icons\\INV_Misc_Note_02",
    open  = function()
        local f = _G.BigNoteBoxTagManagerFrame
        if not (f and f:IsShown()) then BNB.ToggleTagManager() end
    end,
})
UL.Register("trash", {
    label = "TW_TITLE", icon = "Interface\\Icons\\INV_Misc_Bag_10",
    open  = function() BNB.OpenTrashWindow() end,
    avail = ModuleOff(function() return BNB.TrashEnabled() end, "CFG_HDR_TRASH"),
})
UL.Register("features", {
    label = "FL_WINDOW_TITLE", icon = "Interface\\Icons\\INV_Misc_Book_12",
    open  = function() BNB.FeatureList.Open() end,
})
UL.Register("whatsnew", {
    label = "UILINK_WHATSNEW", icon = "Interface\\AddOns\\BigNoteBox\\Assets\\icon",
    open  = function() BNB.WhatsNew.Open() end,
})
UL.Register("wizard", {
    label = "UILINK_WIZARD", icon = "Interface\\Icons\\INV_Misc_Wrench_01",
    open  = function() BNB.ShowSetupWizard() end,
})
UL.Register("bugreport", {
    label = "BUG_TITLE", icon = "Interface\\Icons\\INV_Misc_AhnQirajTrinket_01",
    open  = function() BNB.ShowBugReport() end,
})

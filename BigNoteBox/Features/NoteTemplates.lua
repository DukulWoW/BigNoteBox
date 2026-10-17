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
-- Public API:
--   BNB.Templates.Get(key)            -> template or nil ("blank" = nil)
--   BNB.Templates.QUICK               -> card keys in the New Note dialog
--   BNB.Templates.More()              -> the templates on the More page
--   BNB.Templates.Title(tpl)          -> suggested title, tokens filled
--   BNB.Templates.Fill(id, tpl, rich) -> body, tags, tasks, situation onto a new note

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

function TPL.Get(key)
    return key and BY_KEY[key] or nil
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
    local raw = L[tpl.title]
    local Tk = BNB.Tokens
    local filled = Tk and Tk.Snapshot(raw) or raw
    if Tk and Tk.HasSnapshot(filled) then return L[tpl.name] end
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
function TPL.Fill(id, tpl, rich)
    if not (id and tpl) then return end
    local updates = { body = Body(tpl, rich) }
    local tags = Lines(L[tpl.tags], ",")
    if #tags > 0 then updates.tags = tags end
    if tpl.situation == "instance" and BNB.SituationsEnabled() and BNB.GetCurrentZone then
        local kind, name = BNB.GetCurrentZone()
        if kind == "instance" and name and name ~= "" then
            updates.situations = { "instance:" .. name }
        end
    end
    BNB.UpdateNote(id, updates)

    local T = BNB.Task
    if tpl.tasks and T and BNB.TasksEnabled() then
        if tpl.reset then T.UpdateList(id, { resetType = tpl.reset }) end
        for _, line in ipairs(Lines(L[tpl.tasks], "\n")) do
            T.AddTask(id, BNB.Tokens and BNB.Tokens.Snapshot(line, true) or line)
        end
    end
end

-- BigNoteBox Minimap/Minimap.lua — LibDBIcon minimap button + addon compartment

local BNB = BigNoteBox
local L = BNB.L
local ICON_PATH = "Interface\\AddOns\\BigNoteBox\\Assets\\icon"

--------------------------------------------------------------------------------
-- LibDataBroker + LibDBIcon minimap button
--------------------------------------------------------------------------------
local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
local DBIcon = LibStub and LibStub("LibDBIcon-1.0", true)

-- One click handler for the minimap button and the addon compartment.
-- Shift+Left hides / shows the sticky notes, Shift+Right opens Settings
-- (ALL-159); plain Left toggles the window, plain Right makes a new note.
function BNB.MinimapClick(button)
    if IsShiftKeyDown() then
        if button == "RightButton" then
            local cf = _G["BigNoteBoxConfigFrame"]
            if not (cf and cf:IsShown()) and BNB.OpenConfig then BNB.OpenConfig() end
        elseif BNB.Sticky and BNB.Sticky.ToggleHidden then
            BNB.Sticky.ToggleHidden()
        end
    elseif button == "RightButton" then
        if BNB.CreateNewNote then BNB.CreateNewNote() end
    else
        if BNB.ToggleWindow then BNB.ToggleWindow() end
    end
end

-- The click lines of both tooltips
function BNB.AddMinimapClickLines(tooltip)
    tooltip:AddLine(L["MINIMAP_LEFT_CLICK"], 1, 1, 1)
    tooltip:AddLine(L["MINIMAP_RIGHT_CLICK"], 1, 1, 1)
    if BNB.StickiesEnabled() then   -- Sticky Notes module (ALL-343)
        tooltip:AddLine(L["MINIMAP_SHIFT_LEFT_CLICK"], 1, 1, 1)
    end
    tooltip:AddLine(L["MINIMAP_SHIFT_RIGHT_CLICK"], 1, 1, 1)
end

-- ── Data broker (ALL-472) ───────────────────────────────────────────────────
-- The one LDB object is a data source, not a launcher, so broker bars (Titan
-- Panel, XIV Databar, ChocolateBar, ElvUI datatexts...) show a count beside the
-- icon; LibDBIcon ignores the text. BigNoteBoxDB.brokerText: "both" (notes +
-- here), "total", "here" or "none" (icon only). "Here" = the notes whose
-- situation matches now (BNB._contextMatches, Features/ContextNotes.lua).
local RECENT_MAX = 10
local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_Note_06"

local function NoteCount()
    local ndb = BNB.NotesDB and BNB.NotesDB()
    local n = 0
    if ndb and ndb.notes then
        for _ in pairs(ndb.notes) do n = n + 1 end
    end
    return n
end

local function HereCount()
    return BNB._contextMatches and #BNB._contextMatches or 0
end

local function CountText(fmtOne, fmtMany, n)
    if n == 1 then return L[fmtOne] end
    return string.format(L[fmtMany], n)
end

function BNB.BrokerText()
    local mode = (BigNoteBoxDB and BigNoteBoxDB.brokerText) or BNB.DEFAULTS.brokerText
    if mode == "none" then return "" end
    local notes = CountText("BROKER_ONE_NOTE", "BROKER_NOTES_FMT", NoteCount())
    if mode == "total" then return notes end
    local here = string.format(L["BROKER_HERE_FMT"], HereCount())
    if mode == "here" then return here end
    return notes .. ", " .. here
end

-- One tooltip line per note: icon, title in the note's title colour, and
-- when it was last edited on the right (right = nil leaves it out)
local function AddNoteLine(tooltip, note, right)
    local icon = BNB.NpcNoteIcon and BNB.NpcNoteIcon(note) or note.icon
    if not icon or icon == "" then icon = DEFAULT_ICON end
    local title = (note.title and note.title ~= "") and note.title or L["UNTITLED"]
    local text = "|T" .. icon .. ":16:16:0:0:64:64:5:59:5:59|t " .. title:gsub("|", "||")
    local c = note.titleColor
    local r, g, b = 1, 1, 1
    if c then r, g, b = c.r or 1, c.g or 1, c.b or 1 end
    if right then
        tooltip:AddDoubleLine(text, right, r, g, b, 0.6, 0.6, 0.6)
    else
        tooltip:AddLine(text, r, g, b)
    end
end

-- Notes here, then the last edited notes (all scopes, trash left out)
local function AddNoteLists(tooltip)
    local ndb = BNB.NotesDB and BNB.NotesDB()
    if not (ndb and ndb.notes) then return end
    local hr, hg, hb = BNB.HeaderColor()
    tooltip:AddLine(" ")
    tooltip:AddDoubleLine(L["BROKER_TIP_TOTAL"], tostring(NoteCount()), hr, hg, hb, 1, 1, 1)

    local here = BNB._contextMatches or {}
    if #here > 0 then
        tooltip:AddLine(" ")
        tooltip:AddLine(string.format(L["CONTEXT_BADGE"], #here), hr, hg, hb)
        for i, id in ipairs(here) do
            if i > RECENT_MAX then
                tooltip:AddLine(string.format(L["BROKER_TIP_MORE_FMT"], #here - RECENT_MAX), 0.6, 0.6, 0.6)
                break
            end
            local note = ndb.notes[id]
            if note then AddNoteLine(tooltip, note) end
        end
    end

    local recent = {}
    for _, note in pairs(ndb.notes) do recent[#recent + 1] = note end
    if #recent == 0 then return end
    table.sort(recent, function(a, b) return (a.updated or 0) > (b.updated or 0) end)
    tooltip:AddLine(" ")
    tooltip:AddLine(L["BROKER_TIP_RECENT"], hr, hg, hb)
    for i = 1, math.min(RECENT_MAX, #recent) do
        local note = recent[i]
        AddNoteLine(tooltip, note, BNB.FmtTime and BNB.FmtTime(note.updated) or nil)
    end
end

-- The whole tooltip, shared by the minimap button, broker bars and the addon
-- compartment (SlashCommands.lua)
function BNB.FillMinimapTooltip(tooltip)
    tooltip:AddLine("BigNoteBox", 0.4, 0.73, 0.42)
    AddNoteLists(tooltip)
    -- ALL-101: hidden stickies (Hide all / its keybind)
    local hidden = BNB.Sticky and BNB.Sticky.HiddenCount and BNB.Sticky.HiddenCount() or 0
    if hidden > 0 then
        tooltip:AddLine(" ")
        tooltip:AddLine(string.format(L["MINIMAP_STICKIES_HIDDEN_FMT"], hidden), 1, 0.5, 0.25)
        local key = BNB.Sticky.HideKeyText and BNB.Sticky.HideKeyText()
        if key then
            tooltip:AddLine(string.format(L["MINIMAP_STICKIES_SHOW_KEY_FMT"], key), 0.7, 0.7, 0.7)
        end
    end
    tooltip:AddLine(" ")
    BNB.AddMinimapClickLines(tooltip)
end

local ldbObject
if LDB then
    ldbObject = LDB:NewDataObject("BigNoteBox", {
        type = "data source",
        icon = ICON_PATH,
        label = "BigNoteBox",
        text = "",
        OnClick = function(self, button) BNB.MinimapClick(button) end,
        OnTooltipShow = function(tooltip)
            BNB.FillMinimapTooltip(tooltip)
            tooltip:AddLine(L["MINIMAP_DRAG"], 0.7, 0.7, 0.7)
        end,
    })
end

-- Text refresh: note changes come in bursts (autosave, imports), so one
-- update a moment after the last of them
local function RefreshBrokerText()
    if ldbObject then ldbObject.text = BNB.BrokerText() end
end

function BNB.UpdateBrokerText()
    BNB.Debounce("brokerText", 0.2, RefreshBrokerText)
end

--------------------------------------------------------------------------------
-- Init (called from Core/Initialize.lua)
--------------------------------------------------------------------------------
function BNB.InitMinimapButton()
    if not BigNoteBoxDB.minimapIcon then
        BigNoteBoxDB.minimapIcon = CopyTable(BNB.DEFAULTS.minimapIcon)
    end

    if DBIcon and ldbObject then
        DBIcon:Register("BigNoteBox", ldbObject, BigNoteBoxDB.minimapIcon)
    end

    RefreshBrokerText()
    for _, msg in ipairs({ "NoteCreated", "NoteChanged", "NoteDeleted", "NoteRestored",
                           "SituationMatches" }) do
        BNB.RegisterMessage("BrokerText", msg, BNB.UpdateBrokerText)
    end
end

function BNB.SetMinimapButtonShown(show)
    if not DBIcon then return end
    if show then
        BigNoteBoxDB.minimapIcon.hide = false
        DBIcon:Show("BigNoteBox")
    else
        BigNoteBoxDB.minimapIcon.hide = true
        DBIcon:Hide("BigNoteBox")
    end
end

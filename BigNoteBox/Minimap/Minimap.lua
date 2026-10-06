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

local ldbObject
if LDB then
    ldbObject = LDB:NewDataObject("BigNoteBox", {
        type = "launcher",
        icon = ICON_PATH,
        label = "BigNoteBox",
        OnClick = function(self, button) BNB.MinimapClick(button) end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine("BigNoteBox", 0.4, 0.73, 0.42)
            BNB.AddMinimapClickLines(tooltip)
            tooltip:AddLine(L["MINIMAP_DRAG"], 0.7, 0.7, 0.7)

            -- Badge: show contextual note count if available
            local ctxCount = BNB._contextMatches and #BNB._contextMatches or 0
            if ctxCount > 0 then
                tooltip:AddLine(" ")
                tooltip:AddLine(string.format(L["CONTEXT_BADGE"], ctxCount), 1, 0.82, 0)
            end
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
        end,
    })
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

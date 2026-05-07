-- BigNoteBox Minimap/Minimap.lua — LibDBIcon minimap button + addon compartment

local BNB = BigNoteBox
local L = BNB.L
local ICON_PATH = "Interface\\AddOns\\BigNoteBox\\Assets\\icon"

--------------------------------------------------------------------------------
-- LibDataBroker + LibDBIcon minimap button
--------------------------------------------------------------------------------
local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
local DBIcon = LibStub and LibStub("LibDBIcon-1.0", true)

local ldbObject
if LDB then
    ldbObject = LDB:NewDataObject("BigNoteBox", {
        type = "launcher",
        icon = ICON_PATH,
        label = "BigNoteBox",
        OnClick = function(self, button)
            if button == "RightButton" then
                if BNB.CreateNewNote then BNB.CreateNewNote() end
            else
                if BNB.ToggleWindow then BNB.ToggleWindow() end
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine("BigNoteBox", 0.4, 0.73, 0.42)
            tooltip:AddLine(L["MINIMAP_LEFT_CLICK"], 1, 1, 1)
            tooltip:AddLine(L["MINIMAP_RIGHT_CLICK"], 1, 1, 1)
            tooltip:AddLine(L["MINIMAP_DRAG"], 0.7, 0.7, 0.7)

            -- Badge: show contextual note count if available
            if BNB._contextNoteCount and BNB._contextNoteCount > 0 then
                tooltip:AddLine(" ")
                tooltip:AddLine(string.format(L["CONTEXT_BADGE"], BNB._contextNoteCount), 1, 0.82, 0)
            end
        end,
    })
    BNB.ldbObject = ldbObject
end

--------------------------------------------------------------------------------
-- Init (called from Core/Initialize.lua)
--------------------------------------------------------------------------------
function BNB.InitMinimapButton()
    if not BigNoteBoxDB.minimapIcon then
        BigNoteBoxDB.minimapIcon = {
            hide = false,
            minimapPos = 220,
        }
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

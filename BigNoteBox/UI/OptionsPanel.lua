-- BigNoteBox UI/OptionsPanel.lua — ESC → Options → Addons entry
--
-- Matches BCB's Config/ConfigMinimal.lua pattern exactly.
-- Shows logo, addon name, version, "by Dukul", and an "Open Settings" button.
-- Registered via Settings.RegisterCanvasLayoutCategory.
--
-- Loaded on ADDON_LOADED so the panel exists before the player opens Options.

local ADDON_NAME = "BigNoteBox"
local BNB        = BigNoteBox
local L          = BNB.L

local function CreateOptionsPanel()
    local panel   = CreateFrame("Frame", "BigNoteBoxOptionsPanel", UIParent)
    panel.name    = "BigNoteBox"

    local logo = panel:CreateTexture(nil, "ARTWORK")
    logo:SetSize(128, 128)
    logo:SetPoint("CENTER", panel, "CENTER", 0, 80)
    logo:SetTexture("Interface\\AddOns\\BigNoteBox\\Assets\\logo-256")

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge3")
    title:SetPoint("TOP", logo, "BOTTOM", 0, -8)
    title:SetText(L["OPT_TITLE"])

    local version = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    version:SetPoint("TOP", title, "BOTTOM", 0, -4)
    version:SetText(string.format(L["OPT_VERSION_FMT"], BNB.ADDON_VERSION or "1.0.0"))
    version:SetTextColor(0.7, 0.7, 0.7)

    local author = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    author:SetPoint("TOP", version, "BOTTOM", 0, -2)
    author:SetText(L["AUTHOR"])
    author:SetTextColor(0.55, 0.55, 0.55)

    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    hint:SetPoint("TOP", author, "BOTTOM", 0, -10)
    hint:SetText(L["OPT_HINT"])

    -- Button: try modern template first, fall back gracefully
    local tpl = "SharedButtonLargeTemplate"
    if not (C_XMLUtil and C_XMLUtil.GetTemplateInfo
            and C_XMLUtil.GetTemplateInfo(tpl)) then
        tpl = "UIPanelDynamicResizeButtonTemplate"
    end
    if not (C_XMLUtil and C_XMLUtil.GetTemplateInfo
            and C_XMLUtil.GetTemplateInfo(tpl)) then
        tpl = "UIPanelButtonTemplate"
    end

    local btn = CreateFrame("Button", nil, panel, tpl)
    btn:SetSize(300, 60)
    btn:SetPoint("TOP", hint, "BOTTOM", 0, -16)
    btn:SetText(L["OPT_OPEN_SETTINGS_BTN"])
    pcall(function() DynamicResizeButton_Resize(btn) end)
    local bfs = btn:GetFontString()
    if bfs then pcall(function() bfs:SetFont(BNB.GetLocaleFont(), 20, "") end) end
    btn:SetScript("OnClick", function()
        if BNB.OpenConfig then BNB.OpenConfig() end
    end)

    -- Register with the Settings API
    local cat = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(cat)
    BNB.settingsCategory = cat

    BNB.optionsPanel = panel
end

-- Defer to ADDON_LOADED so the Settings API is ready
local _f = CreateFrame("Frame")
_f:RegisterEvent("ADDON_LOADED")
_f:SetScript("OnEvent", function(self, _, addon)
    if addon == ADDON_NAME then
        CreateOptionsPanel()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

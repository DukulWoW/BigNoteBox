-- BigNoteBox UI/Config/Templates.lua - Settings > Notes > Templates (ALL-68 S2)
-- The player's own templates, then the 12 built-ins (Dukul, 2026-10-17). A
-- click on a row opens the template menu (BNB.TemplateMenu, UI/TemplateSave.lua:
-- the same menu as the New Note dialog's More page).
-- Rows are rebuilt on TemplatesChanged and whenever the page shows.
-- Built by UI/Config/Notes.lua through K.BuildTemplatesPage; the templates
-- themselves are Features/NoteTemplates.lua.

local BNB = BigNoteBox
local L   = BNB.L

local K = BNB._ConfigKit
local CONTENT_W = K.CONTENT_W

local ROW_H   = 34
local ROW_GAP = 2
local NO_ICON = "Interface\\Icons\\INV_Misc_Note_01"

-- The window this page sits in, for the icon picker (Change icon)
local function TopWindow(f)
    while f:GetParent() and f:GetParent() ~= UIParent do f = f:GetParent() end
    return f
end

-- Use: the New Note dialog with this template picked
local function UseTemplate(key)
    local NND = BNB.NewNoteDialog
    if NND and NND.OpenWithTemplate then NND.OpenWithTemplate(key) end
end

-- The row menu is shared with the New Note dialog's More page
-- (BNB.TemplateMenu, UI/TemplateSave.lua)
local function OpenRowMenu(row)
    BNB.ContextMenu.Open(row, function(root)
        BNB.TemplateMenu(root, row.key, { row = row, window = TopWindow(row), onUse = UseTemplate })
    end)
end

function K.BuildTemplatesPage(sf, ct, y)
    local desc = ct:CreateFontString(nil, "OVERLAY", "BNBFontHighlightSmall")
    desc:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    desc:SetWidth(CONTENT_W); desc:SetJustifyH("LEFT"); desc:SetWordWrap(true)
    desc:SetTextColor(0.8, 0.8, 0.8)
    desc:SetText(L["CFG_TPL_PAGE_DESC"])
    local top = y - math.ceil(desc:GetStringHeight()) - 12

    local userHdr = BNB.CreateSectionHeader(ct, L["CFG_TPL_HDR_USER"], 0, CONTENT_W)
    local empty = BNB.CreateSmallLabel(ct, L["CFG_TPL_NONE"], 0, CONTENT_W)
    empty:SetWordWrap(true)
    local builtHdr = BNB.CreateSectionHeader(ct, L["CFG_TPL_HDR_BUILTIN"], 0, CONTENT_W)

    local pool = {}
    local function Row(i)
        if pool[i] then return pool[i] end
        local row = BNB.CreateBackdropFrame("Button", nil, ct)
        BNB.SetBackdrop(row, 0.06, 0.06, 0.08, 0.95, 0.28, 0.28, 0.30, 1)
        row:SetHeight(ROW_H)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(ROW_H - 8, ROW_H - 8)
        icon:SetPoint("LEFT", row, "LEFT", 4, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local name = row:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
        name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -1)
        name:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        name:SetJustifyH("LEFT"); name:SetWordWrap(false)
        local d = row:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
        d:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 8, 1)
        d:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        d:SetJustifyH("LEFT"); d:SetWordWrap(false)
        d:SetTextColor(0.65, 0.65, 0.65, 1)
        row.icon, row.nameLbl, row.descLbl = icon, name, d
        row:SetScript("OnClick", OpenRowMenu)
        row:SetScript("OnEnter", function(self)
            BNB.PaintSelectCard(self, "hover", self.nameLbl)
            local tip = L["CFG_TPL_ROW_TIP_BUILTIN"]
            if self._user then tip = L["CFG_TPL_ROW_TIP_USER"] end
            BNB.TemplateTooltip(self, BNB.Templates.Get(self.key), tip)
        end)
        row:SetScript("OnLeave", function(self)
            BNB.PaintSelectCard(self, nil, self.nameLbl)
            GameTooltip:Hide()
        end)
        pool[i] = row
        return row
    end

    local function Place(fs, yy)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, yy)
    end

    local function Layout()
        local TP = BNB.Templates
        local yy, n = top, 0
        local function Add(tpl)
            n = n + 1
            local row = Row(n)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT",  ct, "TOPLEFT",  0, yy)
            row:SetPoint("TOPRIGHT", ct, "TOPRIGHT", 0, yy)
            row.key, row._user = tpl.key, tpl.user == true
            row.icon:SetTexture(tpl.icon or NO_ICON)
            row.nameLbl:SetText(TP.Name(tpl))
            row.descLbl:SetText(TP.Desc(tpl))
            BNB.PaintSelectCard(row, nil, row.nameLbl)
            row:Show()
            yy = yy - ROW_H - ROW_GAP
        end
        Place(userHdr, yy); yy = yy - 22
        local user = TP.User()
        if #user == 0 then
            Place(empty, yy); empty:Show()
            yy = yy - math.ceil(empty:GetStringHeight()) - 6
        else
            empty:Hide()
            for _, tpl in ipairs(user) do Add(tpl) end
        end
        yy = yy - 12
        Place(builtHdr, yy); yy = yy - 22
        for _, tpl in ipairs(TP.All()) do Add(tpl) end
        for i = n + 1, #pool do pool[i]:Hide() end
        sf:FinaliseHeight(-yy + 8)
    end

    Layout()
    sf:HookScript("OnShow", Layout)
    -- A row's Change icon picker goes with the page
    sf:HookScript("OnHide", function() BNB.IconPicker.Close("templateIcon") end)
    BNB.RegisterMessage("ConfigTemplates", "TemplatesChanged", function()
        if sf:IsVisible() then Layout() end
    end)
end

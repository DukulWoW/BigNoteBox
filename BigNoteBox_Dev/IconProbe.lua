-- IconProbe.lua
-- ALL-238 (2026-10-04): which bundled note icons (BigNoteBox/Assets/Icons) the
-- game already has. /bnbicons toggles the window. Dev only, never packaged.
--
-- Every icon in BigNoteBox.ICON_MANIFEST is looked up as Interface\Icons\<name>
-- with GetFileIDFromPath. Each cell shows the bundled TGA (left) beside the
-- game file (right); a red cell has no game file. The results are saved per
-- client in BigNoteBoxDevDB.iconProbe so they can be read outside the game.

local CELL, GAP, PAD, TOP = 32, 10, 12, 58
local COLS = 8

local f, content, header
local cells = {}
local missingOnly = false
-- BNB trims 8% off each edge of every note icon (SetTexCoord 0.08..0.92):
-- on by default, so the cells show what a player sees
local trim = true
local results  -- { { cat, name, path, id }, ... }

local function ClientKey()
    local _, _, _, iface = GetBuildInfo()
    if iface and iface >= 16000 and iface < 20000 then return "forever" end
    return "retail"
end

local function Probe()
    results = {}
    local missing, ids = {}, {}
    for _, path in ipairs(BigNoteBox and BigNoteBox.ICON_MANIFEST or {}) do
        local cat, name = path:match("Icons\\([^\\]+)\\([^\\]+)$")
        if name then
            local id = GetFileIDFromPath("Interface\\Icons\\" .. name)
            results[#results + 1] = { cat = cat, name = name, path = path, id = id }
            if id then ids[name] = id else missing[#missing + 1] = cat .. "/" .. name end
        end
    end
    BigNoteBoxDevDB = BigNoteBoxDevDB or {}
    BigNoteBoxDevDB.iconProbe = BigNoteBoxDevDB.iconProbe or {}
    local version, build = GetBuildInfo()
    BigNoteBoxDevDB.iconProbe[ClientKey()] = {
        time = time(), build = version .. "." .. build,
        total = #results, missing = missing, ids = ids,
    }
    return #results, #missing
end

local function MakeCell(i)
    local c = CreateFrame("Frame", nil, content, "BackdropTemplate")
    c:SetSize(CELL * 2 + 6, CELL + 4)
    c:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    c.own = c:CreateTexture(nil, "ARTWORK")
    c.own:SetSize(CELL, CELL); c.own:SetPoint("LEFT", 2, 0)
    c.game = c:CreateTexture(nil, "ARTWORK")
    c.game:SetSize(CELL, CELL); c.game:SetPoint("RIGHT", -2, 0)
    c:EnableMouse(true)
    c:SetScript("OnEnter", function(self)
        local r = self._r
        if not r then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(r.name, 1, 1, 1)
        GameTooltip:AddLine(r.cat, 0.7, 0.7, 0.7)
        if r.id then
            GameTooltip:AddLine("Game file id " .. r.id, 0.4, 0.85, 0.4)
        else
            GameTooltip:AddLine("Not in the game", 1, 0.35, 0.35)
        end
        GameTooltip:AddLine("Left: bundled TGA   Right: game icon", 0.6, 0.6, 0.6)
        GameTooltip:AddLine("Click: copy the name", 0.4, 0.75, 1)
        GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Click opens BNB's copy box with the icon name selected, ready for Ctrl+C
    c:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" or not self._r then return end
        if BigNoteBox and BigNoteBox.ShowClipboardHint then
            BigNoteBox.ShowClipboardHint(self._r.name, self, true)
        end
    end)
    cells[i] = c
    return c
end

local function Layout()
    local shown, n = 0, 0
    for _, c in ipairs(cells) do c:Hide() end
    local cellW = CELL * 2 + 6
    for _, r in ipairs(results) do
        if not missingOnly or not r.id then
            shown = shown + 1
            local c = cells[shown] or MakeCell(shown)
            c._r = r
            local a, b = trim and 0.08 or 0, trim and 0.92 or 1
            c.own:SetTexture(r.path)
            c.own:SetTexCoord(a, b, a, b)
            c.game:SetTexCoord(a, b, a, b)
            if r.id then
                c.game:SetTexture(r.id)
                c:SetBackdropColor(0.08, 0.08, 0.08, 0.9)
                c:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
            else
                c.game:SetColorTexture(0.25, 0, 0, 1)
                c:SetBackdropColor(0.3, 0.02, 0.02, 0.9)
                c:SetBackdropBorderColor(1, 0.2, 0.2, 1)
                n = n + 1
            end
            local col, row = (shown - 1) % COLS, math.floor((shown - 1) / COLS)
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", content, "TOPLEFT", col * (cellW + GAP), -row * (CELL + 4 + GAP))
            c:Show()
        end
    end
    local rows = math.max(1, math.ceil(shown / COLS))
    content:SetHeight(rows * (CELL + 4 + GAP))
end

local function Refresh()
    local total, missing = Probe()
    header:SetText(("%s  |  %d bundled icons  |  |cff66dd66%d in the game|r  |  |cffff5555%d missing|r  |  saved to BigNoteBoxDevDB.iconProbe.%s")
        :format(ClientKey() == "forever" and "WoW Forever" or "Retail", total, total - missing, missing, ClientKey()))
    Layout()
end

local function Build()
    local cellW = CELL * 2 + 6
    local w = PAD * 2 + COLS * cellW + (COLS - 1) * GAP + 24
    f = CreateFrame("Frame", "BNBDevIconProbe", UIParent, "BackdropTemplate")
    f:SetSize(w, 640)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    f:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    f:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    tinsert(UISpecialFrames, "BNBDevIconProbe")

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", PAD, -PAD)
    title:SetText("Icon probe (ALL-238)")
    header = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    header:SetPoint("TOPLEFT", PAD, -PAD - 22)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    local filter = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    filter:SetSize(110, 22)
    filter:SetPoint("TOPRIGHT", -30, -PAD + 2)
    filter:SetText("Missing only")
    filter:SetScript("OnClick", function(self)
        missingOnly = not missingOnly
        self:SetText(missingOnly and "Show all" or "Missing only")
        Layout()
    end)

    local trimBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    trimBtn:SetSize(110, 22)
    trimBtn:SetPoint("RIGHT", filter, "LEFT", -6, 0)
    trimBtn:SetText("Trim: BNB")
    trimBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Edge trim", 1, 1, 1)
        GameTooltip:AddLine("BNB: 8% off each edge, as every BNB window draws a note icon.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Full: the whole file, built-in border and all.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    trimBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    trimBtn:SetScript("OnClick", function(self)
        trim = not trim
        self:SetText(trim and "Trim: BNB" or "Trim: full")
        Layout()
    end)

    local sf = CreateFrame("ScrollFrame", nil, f, "ScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", PAD, -TOP)
    sf:SetPoint("BOTTOMRIGHT", -PAD - 20, PAD)
    content = CreateFrame("Frame", nil, sf)
    content:SetSize(w - PAD * 2 - 24, 10)
    sf:SetScrollChild(content)
end

SLASH_BNBICONPROBE1 = "/bnbicons"
SlashCmdList.BNBICONPROBE = function()
    if not f then Build() elseif f:IsShown() then f:Hide(); return end
    Refresh()
    f:Show()
end

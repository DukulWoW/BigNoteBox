-- BigNoteBox Features/ZonePicker.lua
--
-- Zone & instance browse picker and autocomplete for the Situation tab.
-- Powered by LibTourist-3.0 (lazy-loaded on first use).
--
-- Public API:
--   BNB.ZonePicker.Open(anchorFrame, onSelect, filterType)
--     Opens the picker window anchored below anchorFrame.
--     filterType: "zone" | "instance" | nil (both)
--     onSelect(name, kind) called when player picks an entry.
--
--   BNB.ZonePicker.Close()
--
--   BNB.ZonePicker.GetMatches(text, kind, maxResults)
--     Returns a list of {name, continent, kind} tables matching text.
--     kind: "zone" | "instance" | "player"
--     Used by the autocomplete dropdown in NoteConfig.

local BNB = BigNoteBox
BNB.ZonePicker = BNB.ZonePicker or {}
local ZP = BNB.ZonePicker

local ASSETS = "Interface\\AddOns\\BigNoteBox\\Assets\\"

-- ── LibTourist access (guarded — nil if not loaded) ──────────────────────────
local function GetTourist()
    return LibStub and LibStub("LibTourist-3.0", true)
end

-- ── Continent display order ───────────────────────────────────────────────────
-- Ordered newest-first so Midnight/TWW content is easy to find.
local CONTINENT_ORDER = {
    "Quel'Thalas",
    "Khaz Algar",
    "Dragon Isles",
    "The Shadowlands",
    "Kul Tiras",
    "Zandalar",
    "Argus",
    "Broken Isles",
    "Draenor",
    "Pandaria",
    "The Maelstrom",
    "Northrend",
    "Outland",
    "Eastern Kingdoms",
    "Kalimdor",
}

-- ── Data cache ────────────────────────────────────────────────────────────────
-- Built once per session on first Open() or GetMatches() call.
-- _cache = { zones = {name, continent}[], instances = {name, continent}[] }
-- Each list is sorted A-Z; continent is the display string from Tourist:GetContinent.
local _cache = nil

local function BuildCache()
    if _cache then return end
    local Tourist = GetTourist()
    _cache = { zones = {}, instances = {} }
    if not Tourist then return end

    local seen = {}

    for zone in Tourist:IterateZones() do
        if not seen[zone] then
            seen[zone] = true
            local continent = Tourist:GetContinent(zone) or "?"
            _cache.zones[#_cache.zones + 1] = { name = zone, continent = continent }
        end
    end

    for inst in Tourist:IterateInstances() do
        if not seen[inst] then
            seen[inst] = true
            local continent = Tourist:GetContinent(inst) or "?"
            _cache.instances[#_cache.instances + 1] = { name = inst, continent = continent }
        end
    end

    table.sort(_cache.zones,     function(a, b) return a.name < b.name end)
    table.sort(_cache.instances, function(a, b) return a.name < b.name end)
end

-- ── Public: GetMatches ────────────────────────────────────────────────────────
-- Returns up to maxResults entries matching text for the given kind.
-- kind = "zone" | "instance" | "player"
function ZP.GetMatches(text, kind, maxResults)
    maxResults = maxResults or 8
    local results = {}
    if not text or text == "" then return results end
    local lower = text:lower()

    if kind == "player" then
        -- Friend list
        local numFriends = C_FriendList and C_FriendList.GetNumFriends
            and C_FriendList.GetNumFriends() or 0
        for i = 1, numFriends do
            if #results >= maxResults then break end
            local info = C_FriendList.GetFriendInfoByIndex(i)
            if info and info.name and info.name:lower():find(lower, 1, true) == 1 then
                results[#results + 1] = { name = info.name, continent = "Friend", kind = "player" }
            end
        end
        -- Guild roster
        local numGuild = GetNumGuildMembers and GetNumGuildMembers() or 0
        for i = 1, numGuild do
            if #results >= maxResults then break end
            local name = GetGuildRosterInfo(i)
            if name then
                -- Strip realm suffix if present
                local shortName = name:match("^([^%-]+)") or name
                if shortName:lower():find(lower, 1, true) == 1 then
                    -- Avoid duplicates with friends list
                    local dup = false
                    for _, r in ipairs(results) do
                        if r.name == shortName then dup = true; break end
                    end
                    if not dup then
                        results[#results + 1] = {
                            name = shortName, continent = "Guild", kind = "player"
                        }
                    end
                end
            end
        end
        return results
    end

    -- Zone or instance — needs cache
    BuildCache()
    local list = (kind == "instance") and _cache.instances or _cache.zones
    for _, entry in ipairs(list) do
        if #results >= maxResults then break end
        if entry.name:lower():find(lower, 1, true) then
            results[#results + 1] = {
                name      = entry.name,
                continent = entry.continent,
                kind      = kind or "zone",
            }
        end
    end
    return results
end

-- ── Picker window ─────────────────────────────────────────────────────────────
local _picker      = nil
local _onSelect    = nil
local _activeKind  = "zone"   -- "zone" or "instance", drives the list shown

local ROW_H     = 22
local HEADER_H  = 26
local SEARCH_H  = 24
local TAB_H     = 26
local PAD       = 6
local SCROLL_PAD = 18

-- Rows are pooled — built once, reused on each populate pass.
local _rows = {}

local function GetTouristSafe()
    local ok, t = pcall(GetTourist)
    return ok and t or nil
end

local function BuildPicker()
    local f = BNB.CreateBackdropFrame("Frame", "BNBZonePickerFrame", UIParent)
    BNB.SetBackdrop(f, 0.06, 0.06, 0.08, 0.98, 0.35, 0.35, 0.38, 1)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(150)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:EnableKeyboard(true)
    f:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            ZP.Close()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    -- ── Tab bar: Zones | Instances ────────────────────────────────────────────
    local tabZone = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    tabZone:SetSize(90, TAB_H)
    tabZone:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -PAD)
    tabZone:SetText("Zones")

    local tabInst = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    tabInst:SetSize(90, TAB_H)
    tabInst:SetPoint("LEFT", tabZone, "RIGHT", 4, 0)
    tabInst:SetText("Instances")

    -- ── Search box ────────────────────────────────────────────────────────────
    local searchFrame = BNB.CreateBackdropFrame("Frame", nil, f)
    BNB.SetBackdropDark(searchFrame)
    searchFrame:SetHeight(SEARCH_H)
    searchFrame:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, -(PAD + TAB_H + 4))
    searchFrame:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -(PAD + TAB_H + 4))

    local searchEb = CreateFrame("EditBox", nil, searchFrame)
    searchEb:SetAllPoints()
    searchEb:SetFontObject("GameFontNormal")
    searchEb:SetAutoFocus(false)
    searchEb:SetMaxLetters(64)
    searchEb:SetTextInsets(6, 6, 0, 0)
    searchEb:SetTextColor(1, 1, 1)
    BNB.AddPlaceholder(searchEb, "Filter...", 0.40, 0.40, 0.40)
    searchEb:SetScript("OnEscapePressed", function() ZP.Close() end)

    -- ── Column headers ────────────────────────────────────────────────────────
    local colHdrZone = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colHdrZone:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD + 4, -(PAD + TAB_H + 4 + SEARCH_H + 4))
    colHdrZone:SetTextColor(0.55, 0.55, 0.55)
    colHdrZone:SetText("Name")

    local colHdrCont = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colHdrCont:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(PAD + SCROLL_PAD + 4), -(PAD + TAB_H + 4 + SEARCH_H + 4))
    colHdrCont:SetTextColor(0.55, 0.55, 0.55)
    colHdrCont:SetJustifyH("RIGHT")
    colHdrCont:SetText("Area")

    local colDiv = f:CreateTexture(nil, "ARTWORK")
    colDiv:SetHeight(1)
    colDiv:SetColorTexture(0.22, 0.22, 0.25, 1)
    colDiv:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD,  -(PAD + TAB_H + 4 + SEARCH_H + 14))
    colDiv:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -(PAD + TAB_H + 4 + SEARCH_H + 14))

    local LIST_TOP_OFFSET = PAD + TAB_H + 4 + SEARCH_H + 16

    -- ── Scroll frame ──────────────────────────────────────────────────────────
    local sf = CreateFrame("ScrollFrame", nil, f, "ScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     f, "TOPLEFT",    PAD,          -LIST_TOP_OFFSET)
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(PAD + SCROLL_PAD - 2), PAD)

    local sc = CreateFrame("Frame", nil, sf)
    sc:SetWidth(sf:GetWidth())
    sc:SetHeight(1)
    sf:SetScrollChild(sc)
    sf:SetScript("OnSizeChanged", function(self) sc:SetWidth(self:GetWidth()) end)

    -- Fade scrollbar when not needed
    if sf.ScrollBar then
        sf.ScrollBar:SetAlpha(0)
        sf:HookScript("OnScrollRangeChanged", function(_, _, yr)
            sf.ScrollBar:SetAlpha((yr or 0) > 1 and 1.0 or 0)
        end)
    end

    f._sf = sf; f._sc = sc
    f._searchEb = searchEb
    f._tabZone  = tabZone
    f._tabInst  = tabInst

    -- ── Populate list ─────────────────────────────────────────────────────────
    local function Populate(filterText)
        BuildCache()
        local Tourist = GetTouristSafe()
        local list = (_activeKind == "instance") and _cache.instances or _cache.zones
        local lower = filterText and filterText:lower() or nil

        -- Filter
        local filtered = {}
        for _, entry in ipairs(list) do
            if not lower or entry.name:lower():find(lower, 1, true) then
                filtered[#filtered + 1] = entry
            end
        end

        -- Build rows (pool pattern — reuse or create)
        local CONT_W   = 110   -- right column width for continent name
        local NAME_PAD = 4

        for i, entry in ipairs(filtered) do
            if not _rows[i] then
                local row = CreateFrame("Button", nil, sc)
                row:SetHeight(ROW_H)

                local hi = row:CreateTexture(nil, "HIGHLIGHT")
                hi:SetAllPoints()
                hi:SetColorTexture(1, 1, 1, 0.06)

                local sel = row:CreateTexture(nil, "BACKGROUND")
                sel:SetAllPoints()
                sel:SetColorTexture(0.20, 0.40, 0.20, 0.25)
                sel:Hide()
                row._selTex = sel

                -- Normal name label (truncated by column width)
                local nameLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                nameLbl:SetPoint("LEFT",  row, "LEFT",  NAME_PAD, 0)
                nameLbl:SetPoint("RIGHT", row, "RIGHT", -(CONT_W + NAME_PAD), 0)
                nameLbl:SetJustifyH("LEFT")
                nameLbl:SetMaxLines(1)
                row._nameLbl = nameLbl

                -- Continent label (right-aligned)
                local contLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                contLbl:SetPoint("RIGHT", row, "RIGHT", -NAME_PAD, 0)
                contLbl:SetWidth(CONT_W)
                contLbl:SetJustifyH("RIGHT")
                contLbl:SetTextColor(0.50, 0.50, 0.50)
                contLbl:SetMaxLines(1)
                row._contLbl = contLbl

                -- Divider line between rows
                local div = row:CreateTexture(nil, "BORDER")
                div:SetHeight(1)
                div:SetPoint("BOTTOMLEFT",  row, "BOTTOMLEFT",  0, 0)
                div:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
                div:SetColorTexture(0.14, 0.14, 0.16, 1)

                _rows[i] = row
            end

            local row = _rows[i]
            row._nameLbl:SetText(entry.name)
            row._nameLbl:SetMaxLines(1)
            row._nameLbl:ClearAllPoints()
            row._nameLbl:SetPoint("LEFT",  row, "LEFT",  NAME_PAD, 0)
            row._nameLbl:SetPoint("RIGHT", row, "RIGHT", -(CONT_W + NAME_PAD), 0)
            row._nameLbl:SetTextColor(1, 1, 1)
            row._contLbl:SetText(entry.continent)
            row._contLbl:Show()
            row._selTex:Hide()
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT",  sc, "TOPLEFT",  0, -(i - 1) * ROW_H)
            row:SetPoint("TOPRIGHT", sc, "TOPRIGHT", 0, -(i - 1) * ROW_H)
            local capturedEntry = entry
            row:SetScript("OnClick", function()
                if _onSelect then
                    _onSelect(capturedEntry.name, _activeKind)
                end
                ZP.Close()
            end)
            row:SetScript("OnEnter", function(self)
                self._selTex:Show()
                -- Expand nameLbl to full row width and remove line limit
                -- so the complete name is visible over the continent column.
                self._contLbl:Hide()
                self._nameLbl:ClearAllPoints()
                self._nameLbl:SetPoint("LEFT",  self, "LEFT",  NAME_PAD, 0)
                self._nameLbl:SetPoint("RIGHT", self, "RIGHT", -NAME_PAD, 0)
                self._nameLbl:SetMaxLines(0)
                self._nameLbl:SetTextColor(1, 0.9, 0.6)
            end)
            row:SetScript("OnLeave", function(self)
                self._selTex:Hide()
                -- Restore nameLbl to truncated column width
                self._nameLbl:ClearAllPoints()
                self._nameLbl:SetPoint("LEFT",  self, "LEFT",  NAME_PAD, 0)
                self._nameLbl:SetPoint("RIGHT", self, "RIGHT", -(CONT_W + NAME_PAD), 0)
                self._nameLbl:SetMaxLines(1)
                self._nameLbl:SetTextColor(1, 1, 1)
                self._contLbl:Show()
            end)
            row:Show()
        end

        -- Hide unused rows
        for i = #filtered + 1, #_rows do _rows[i]:Hide() end

        sc:SetHeight(math.max(#filtered * ROW_H, 1))
        sf:SetVerticalScroll(0)
    end
    f._populate = Populate

    -- Search handler
    searchEb:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local text = self._showingPlaceholder and "" or (self:GetText() or "")
        Populate(text ~= "" and text or nil)
    end)

    -- ── Tab highlight helper ───────────────────────────────────────────────────
    local function UpdateTabs()
        if _activeKind == "zone" then
            tabZone:SetAlpha(1.0)
            tabInst:SetAlpha(0.5)
        else
            tabZone:SetAlpha(0.5)
            tabInst:SetAlpha(1.0)
        end
    end
    f._updateTabs = UpdateTabs

    tabZone:SetScript("OnClick", function()
        _activeKind = "zone"
        UpdateTabs()
        local text = searchEb._showingPlaceholder and "" or (searchEb:GetText() or "")
        Populate(text ~= "" and text or nil)
    end)

    tabInst:SetScript("OnClick", function()
        _activeKind = "instance"
        UpdateTabs()
        local text = searchEb._showingPlaceholder and "" or (searchEb:GetText() or "")
        Populate(text ~= "" and text or nil)
    end)

    -- ── Close button (top-right, matches NoteConfig × style) ─────────────────
    local closeBtn = CreateFrame("Button", nil, f)
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
    local closeLbl = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    closeLbl:SetAllPoints(); closeLbl:SetText("|cffaaaaaa×|r")
    closeBtn:SetScript("OnClick", function() ZP.Close() end)
    closeBtn:SetScript("OnEnter", function() closeLbl:SetText("|cffff4444×|r") end)
    closeBtn:SetScript("OnLeave", function() closeLbl:SetText("|cffaaaaaa×|r") end)

    f:Hide()
    return f
end

-- ── Public: Open ──────────────────────────────────────────────────────────────
-- anchorFrame: the valueRow frame in NoteConfig (used for positioning)
-- onSelect(name, kind): callback when player picks an entry
-- filterType: "zone" | "instance" | nil
--   When "zone" is passed, the picker opens on the Zones tab.
--   When "instance", opens on Instances tab.
--   nil defaults to Zones.
function ZP.Open(anchorFrame, onSelect, filterType)
    BuildCache()
    if not _picker then _picker = BuildPicker() end

    _onSelect   = onSelect
    _activeKind = filterType == "instance" and "instance" or "zone"

    local ncFrame = _G["BigNoteBoxNoteConfigFrame"]

    -- Height: from bottom of anchorFrame down to bottom of ncFrame
    local anchorBottom = anchorFrame:GetBottom() or 0
    local ncBottom     = (ncFrame and ncFrame:GetBottom()) or (anchorBottom - 300)
    local targetH      = math.max(anchorBottom - ncBottom - 4, 200)

    -- Width + horizontal position: span the full ncFrame width by anchoring
    -- TOPLEFT and TOPRIGHT to ncFrame directly. This avoids any panel/pad offset
    -- mismatch — the picker sits flush with the NoteConfig window edges.
    local anchorY = anchorBottom - (ncFrame and ncFrame:GetTop() or anchorBottom)

    _picker:SetHeight(targetH)
    _picker:ClearAllPoints()
    if ncFrame then
        -- Match the chrome inset of ButtonFrameTemplate (~8px each side) so the picker
        -- spans the full visible inner width of the NoteConfig window.
        _picker:SetPoint("TOPLEFT",  ncFrame, "TOPLEFT",   4, anchorY - 2)
        _picker:SetPoint("TOPRIGHT", ncFrame, "TOPRIGHT",  1, anchorY - 2)
    else
        _picker:SetWidth(anchorFrame:GetWidth())
        _picker:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -2)
    end

    -- Reset search
    local eb = _picker._searchEb
    if eb then
        eb:SetText("")
        BNB.AddPlaceholder(eb, "Filter...", 0.40, 0.40, 0.40)
    end

    _picker._updateTabs()
    _picker._populate(nil)
    _picker:Show()
    _picker:Raise()
end

-- ── Public: Close ─────────────────────────────────────────────────────────────
function ZP.Close()
    if _picker then _picker:Hide() end
    _onSelect = nil
end

-- ── Public: IsShown ───────────────────────────────────────────────────────────
function ZP.IsShown()
    return _picker and _picker:IsShown()
end

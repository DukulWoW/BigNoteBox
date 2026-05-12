-- BigNoteBox UI/IconsAC.lua
--
-- Blizzard icon autocomplete dropdown.
-- Driven by BNB.BlizzardIconList (populated from BlizzardIconList.lua only when
-- db.blizzardIconComplete is true).  If the list is nil the AC silently does nothing.
--
-- Public API:
--   BNB.AttachIconAutocomplete(eb, onSelect)
--     Attaches the shared icon AC popup to an EditBox.
--     onSelect(iconName) is called when the user picks a suggestion.
--     iconName is a bare name, e.g. "INV_Sword_01" (no path prefix).
--
-- Behaviour:
--   - Debounce: search fires 150 ms after the last keystroke.
--   - Minimum 2 characters before searching.
--   - Lossy match: strips _ and - from both query and icon name, lowercase both,
--     then does a substring search (string.find).
--   - Collects up to MAX_MATCH results; displays MAX_ROWS at a time.
--   - Up/Down arrows scroll through results when list exceeds MAX_ROWS.
--   - Each row shows a 25x25 icon preview on the left + bare name on the right.
--   - Dropdown opens downward below the editbox, width matches the editbox.
--   - Calls Raise() on show and focus so it stays above toplevel parent frames
--     (e.g. NoteConfig uses ButtonFrameTemplate with SetToplevel(true)).
--   - Enter or click commits; Escape dismisses.
--   - Dismisses automatically when the editbox loses focus.

local BNB = BigNoteBox

local MAX_ROWS  = 6    -- rows visible at once
local MAX_MATCH = 50   -- max results collected per search
local ROW_H     = 31   -- 25px icon + 3px padding top + 3px padding bottom
local ICO_SZ    = 25

-- Single shared popup (built once, reused for both NoteConfig and NoteEditor).
local _iconAC

local function BuildIconAC()
    if _iconAC then return _iconAC end

    local popup = CreateFrame("Frame", "BNBIconAC", UIParent, "BackdropTemplate")
    popup:SetBackdrop({
        bgFile   = "Interface\\Buttons\\White8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    popup:SetBackdropColor(0.05, 0.05, 0.08, 0.97)
    popup:SetBackdropBorderColor(0.4, 0.4, 0.5, 1)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetFrameLevel(500)
    popup:SetClampedToScreen(true)
    popup:Hide()
    popup:EnableMouse(true)
    popup:EnableMouseWheel(true)
    popup:SetScript("OnMouseWheel", function(self, delta)
        -- delta: 1 = scroll up, -1 = scroll down
        self:MoveSelection(-delta)
    end)

    popup.rows      = {}
    popup.matches   = {}
    popup.selIdx    = 1
    popup._offset   = 0
    popup._eb       = nil
    popup._onSelect = nil
    popup._seq      = 0

    -- Build rows
    for i = 1, MAX_ROWS do
        local row = CreateFrame("Button", nil, popup)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT",  popup, "TOPLEFT",   4, -4 - (i - 1) * ROW_H)
        row:SetPoint("TOPRIGHT", popup, "TOPRIGHT",  -4, -4 - (i - 1) * ROW_H)

        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(0.3, 0.5, 0.8, 0.3)

        local sel = row:CreateTexture(nil, "BACKGROUND")
        sel:SetAllPoints()
        sel:SetColorTexture(0.2, 0.4, 0.7, 0.5)
        sel:Hide()
        row.selTex = sel

        local ico = row:CreateTexture(nil, "ARTWORK")
        ico:SetSize(ICO_SZ, ICO_SZ)
        ico:SetPoint("LEFT", row, "LEFT", 4, 0)
        ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.ico = ico

        local lbl = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT",  row, "LEFT",  ICO_SZ + 10, 0)
        lbl:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        lbl:SetJustifyH("LEFT")
        lbl:SetWordWrap(false)
        row.lbl = lbl

        local idx = i
        row:SetScript("OnClick", function()
            popup:Commit(idx)
        end)
        row:SetScript("OnEnter", function()
            popup.selIdx = idx
            popup:UpdateSel()
        end)

        popup.rows[i] = row
    end

    function popup:UpdateSel()
        for i, r in ipairs(self.rows) do
            r.selTex[i == self.selIdx and "Show" or "Hide"](r.selTex)
        end
    end

    function popup:Commit(idx)
        local name = self.matches[(self._offset or 0) + idx]
        if not name or not self._eb then return end
        self._selecting = true
        local eb = self._eb
        if eb.SetRealText then eb:SetRealText(name)
        else eb:SetText(name) end
        self:Hide()
        eb:SetFocus()
        if self._onSelect then self._onSelect(name) end
        self._selecting = false
    end

    function popup:ShowMatches(matches, anchorEb)
        self.matches = matches
        local total  = #matches
        if total == 0 then self:Hide(); return end

        local offset = self._offset or 0
        local count  = math.min(MAX_ROWS, total - offset)

        self.selIdx = 1
        for i = 1, MAX_ROWS do
            local matchIdx = offset + i
            if i <= count and matchIdx <= total then
                local name = matches[matchIdx]
                self.rows[i].lbl:SetText(name)
                self.rows[i].ico:SetTexture("Interface\\Icons\\" .. name)
                self.rows[i]:Show()
            else
                self.rows[i]:Hide()
            end
        end

        -- Overwrite last row with a scroll hint when more results exist below
        if total > offset + MAX_ROWS then
            local remaining = total - offset - MAX_ROWS
            self.rows[MAX_ROWS].lbl:SetText(
                "|cff888888... " .. remaining .. " more (Down arrow)|r")
            self.rows[MAX_ROWS].ico:SetTexture(nil)
        end

        self:SetHeight(count * ROW_H + 8)
        self:SetWidth(math.max(anchorEb:GetWidth(), 180))
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", anchorEb, "BOTTOMLEFT", 0, -2)
        self:Raise()
        self:Show()
        self:UpdateSel()
    end

    function popup:MoveSelection(delta)
        local total = #self.matches
        if total == 0 then return end
        local offset  = self._offset or 0
        local visible = math.min(MAX_ROWS, total - offset)

        self.selIdx = self.selIdx + delta

        if self.selIdx < 1 then
            if offset > 0 then
                self._offset = offset - 1
                self.selIdx  = 1
                self:ShowMatches(self.matches, self._eb)
            else
                self.selIdx = 1
            end
        elseif self.selIdx > visible then
            if offset + MAX_ROWS < total then
                self._offset = offset + 1
                self.selIdx  = MAX_ROWS
                self:ShowMatches(self.matches, self._eb)
            else
                self.selIdx = visible
            end
        end

        self:UpdateSel()
    end

    local function Strip(s)
        return (s:lower():gsub("[_%-]", ""))
    end

    function popup:Search(raw)
        local list = BNB.BlizzardIconList
        if not list then self:Hide(); return end

        -- Split query on spaces; each word must match somewhere in the stripped name
        local words = {}
        for w in raw:lower():gmatch("%S+") do
            local stripped = w:gsub("[_%-]", "")
            if #stripped > 0 then
                words[#words + 1] = stripped
            end
        end
        if #words == 0 or (#words == 1 and #words[1] < 2) then self:Hide(); return end

        local found = {}
        for _, name in ipairs(list) do
            local stripped = Strip(name)
            local allMatch = true
            for _, w in ipairs(words) do
                if not stripped:find(w, 1, true) then
                    allMatch = false
                    break
                end
            end
            if allMatch then
                found[#found + 1] = name
                if #found >= MAX_MATCH then break end
            end
        end

        if #found == 0 then self:Hide(); return end
        self._offset = 0
        self:ShowMatches(found, self._eb)
    end

    _iconAC = popup
    return popup
end

function BNB.AttachIconAutocomplete(eb, onSelect)
    local ac = BuildIconAC()

    eb:HookScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        if not BNB.BlizzardIconList then return end

        local raw = self._showingPlaceholder and "" or (self:GetText() or "")
        raw = raw:match("^%s*(.-)%s*$") or ""

        if #raw < 2 then ac:Hide(); return end

        ac._eb       = self
        ac._onSelect = onSelect
        local seq    = ac._seq + 1
        ac._seq      = seq

        C_Timer.After(0.15, function()
            if ac._seq ~= seq then return end
            if not ac._eb or ac._eb ~= self then return end
            ac:Search(raw)
        end)
    end)

    eb:HookScript("OnEditFocusLost", function()
        C_Timer.After(0.15, function()
            if ac._selecting then return end
            if ac._eb == eb then
                ac:Hide()
                ac._eb = nil
            end
        end)
    end)

    eb:HookScript("OnEditFocusGained", function()
        ac._eb       = eb
        ac._onSelect = onSelect
        -- Raise above toplevel parent frames (NoteConfig is ButtonFrameTemplate + SetToplevel)
        if ac:IsShown() then ac:Raise() end
    end)

    eb:HookScript("OnKeyDown", function(self, key)
        if not ac:IsShown() or ac._eb ~= self then return end
        if key == "UP" then
            ac:MoveSelection(-1)
            self:SetPropagateKeyboardInput(false)
        elseif key == "DOWN" then
            ac:MoveSelection(1)
            self:SetPropagateKeyboardInput(false)
        elseif key == "ESCAPE" then
            ac:Hide()
            self:SetPropagateKeyboardInput(false)
        elseif key == "ENTER" or key == "NUMPADENTER" then
            if #ac.matches > 0 then
                ac:Commit(ac.selIdx)
                self:SetPropagateKeyboardInput(false)
            end
        end
    end)

    eb:HookScript("OnEscapePressed", function()
        if ac:IsShown() and ac._eb == eb then
            ac:Hide()
        end
    end)
end

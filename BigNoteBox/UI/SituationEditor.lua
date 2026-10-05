-- BigNoteBox UI/SituationEditor.lua
-- The Situation editor (CMP-03): binds a note to a zone, sub-zone, instance or
-- player, picks how it shows (popup / sticky / both) and what happens on
-- leaving, and holds the note's waypoint. One builder for the two places that
-- show it, Note Settings' Situation tab (UI/NoteConfig.lua) and sticky
-- settings' Situation tab (UI/StickySettings.lua); until 2026-10-03 each had
-- its own copy, and the copies had drifted (sticky saved contextLeave
-- "bt-minimize", which nothing reads).
--
-- Stored as: note.situations = { "zone:Elwynn Forest" / "subzone:..." /
-- "instance:Molten Core" / "player:Thrall" / "npc:..." / "guild:..." /
-- "itype:dungeon" / "open:vendor" / "state:rested", ... } or nil (ALL-232), plus
-- contextDisplay, contextLeave, contextTrigger, contextFreq (ALL-232 S2),
-- waypoints (ALL-282), wpCreatedOn, wpClearOnLeave, wpNoTrack (SUG-10). The editor lists every situation (one row each,
-- X removes it) above one add row (ALL-232 S3, Dukul's layout A,
-- 2026-10-04); fixing a typo is X and add again.
--
-- Public API:
--   BNB.CreateSituationEditor(panel, opts) -> ed   build once per window
--     opts.padL, opts.padR  panel edge to the content
--     opts.ddR              right inset of the dropdowns
--     opts.top              y of the header
--     opts.bottom           panel bottom to the waypoint line
--     opts.host             the window: the waypoint info popup opens beside it
--                           and closes when it hides
--   ed:Load(noteID)         show a note's saved situation (open, note switch)
--   ed.noteID
-- A change saved in one editor reloads every other editor showing that note,
-- so the two windows stay in step.
--------------------------------------------------------------------------------

local BNB = BigNoteBox
local L   = BNB.L

local ASSETS = "Interface\\AddOns\\BigNoteBox\\Assets\\"
local ROW_H  = 24
local LIST_ROWS, LIST_ROW_H = 4, 20   -- the list box is always 4 rows; the wheel scrolls past that
local TYPE_W = 110                    -- the add row's type dropdown ("Instance type" fits)

-- "npc" matches exactly like "player" (target or group); its own kind so the
-- list says what the note is about (Dukul, 2026-10-04). "guild" matches a
-- target or group member in that guild, never yourself. "itype" / "open" /
-- "state" are picked from fixed keys instead of typed (ALL-232 S4, the lists
-- are BNB.SITUATION_CHOICES in Features/ContextNotes.lua)
local TYPES        = { "zone", "subzone", "instance", "player", "npc", "guild", "itype", "open", "state" }
-- Kinds whose value is a key from a list, not a typed name
local KEY_KINDS    = { itype = true, open = true, state = true }
local PLAYER_KINDS = { player = true, npc = true, guild = true }
local DISPLAY_KEYS = { "popup", "sticky", "both" }
local LEAVE_KEYS   = { "keep", "minimize", "hide" }
-- contextTrigger / contextFreq; the first key of each is saved as nil
local TRIGGER_KEYS = { "arrive", "leave", "both" }
local FREQ_KEYS    = { "always", "session", "day", "daily", "weekly", "once" }

local _editors = {}   -- every editor built, for the cross-window reload
local _popup          -- the waypoint info popup, shared
local _popupOwner     -- the editor that opened it

local function HasWPAddon()   return TomTom and TomTom.AddWaypoint end
local function HasRetailPin() return C_Map and C_Map.SetUserWaypoint end
local function WPAvailable()  return HasWPAddon() or HasRetailPin() end

-- Divider line in the skin border colour (skin mode) or grey
local function Divider(panel)
    local t = panel:CreateTexture(nil, "ARTWORK")
    t:SetHeight(1)
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset then
        local br, bg_, bb = BNB.SkinBorderOf(BNB.GetSkinPreset())
        t:SetColorTexture(br, bg_, bb, 0.8)
        BNB.RegisterSkinRule(t, 0.8)
    else
        t:SetColorTexture(0.28, 0.28, 0.30, 0.8)
    end
    return t
end

local function Tip(btn, title, body, wrap)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(title, 1, 1, 1)
        if body then GameTooltip:AddLine(body, 0.78, 0.78, 0.78, wrap) end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- A value picker on a WowStyle1 dropdown. onPick(key) runs on a player's choice;
-- c:Set(key) only shows it;
-- c:SetLabels(labels) swaps the wording (player situations, ALL-232).
local function NewChoice(panel, keys, labels, onPick)
    local c = { value = keys[1], labels = labels, keys = keys }
    local function LabelOf(k)
        for i, kk in ipairs(c.keys) do if kk == k then return c.labels[i] end end
        return c.labels[1]
    end
    local dd = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
    dd:SetHeight(24)
    dd:SetupMenu(function(_, root)
        for i, label in ipairs(c.labels) do
            local key = c.keys[i]
            root:CreateRadio(label,
                function() return c.value == key end,
                function()
                    c.value = key
                    dd:GenerateMenu()
                    onPick(key)
                end)
        end
    end)
    c.frame = dd
    function c:Set(k)
        self.value = k
        if dd.Text then dd.Text:SetText(LabelOf(k)) end
        dd:GenerateMenu()
    end
    function c:SetLabels(l) self.labels = l; self:Set(self.value) end
    -- Other choices altogether (the add row's value picker); shows the first
    function c:SetChoices(k, l) self.keys = k; self.labels = l; self:Set(k[1]) end
    return c
end

--------------------------------------------------------------------------------
-- WAYPOINT INFO POPUP (shared, opened beside the editor's window)
--------------------------------------------------------------------------------
local function LinkButton(f, text, url)
    local b = BNB.CreateButton(nil, f, text, 200, 22)
    b:SetScript("OnClick", function() BNB.ShowClipboardHint(url, b) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["NC_WP_COPY_URL_TIP"], 0.55, 0.85, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function BuildPopup()
    local f = BNB.CreateBackdropFrame("Frame", "BNBWaypointInfoPopup", UIParent)
    f:SetSize(310, 230)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true); f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    BNB.SetBackdrop(f, 0.08, 0.08, 0.11, 0.96, 0.35, 0.35, 0.38, 1)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -12)
    title:SetTextColor(1, 0.82, 0)
    title:SetText(L["STICKY_WP_SUPPORT_TITLE"])

    local closeBtn = CreateFrame("Button", nil, f)
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
    local closeLbl = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    closeLbl:SetAllPoints(); closeLbl:SetText("|cffaaaaaax|r")
    closeBtn:SetScript("OnClick", function() f:Hide() end)
    closeBtn:SetScript("OnEnter", function() closeLbl:SetText("|cffff4444x|r") end)
    closeBtn:SetScript("OnLeave", function() closeLbl:SetText("|cffaaaaaax|r") end)

    f._statusLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f._statusLbl:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    f._statusLbl:SetWidth(280); f._statusLbl:SetJustifyH("LEFT")

    f._descLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f._descLbl:SetPoint("TOPLEFT", f._statusLbl, "BOTTOMLEFT", 0, -6)
    f._descLbl:SetWidth(280); f._descLbl:SetJustifyH("LEFT"); f._descLbl:SetWordWrap(true)
    f._descLbl:SetTextColor(0.78, 0.78, 0.78)

    local linksHdr = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    linksHdr:SetPoint("TOPLEFT", f._descLbl, "BOTTOMLEFT", 0, -14)
    linksHdr:SetText(L["STICKY_WP_RECOMMENDED_ADDONS"])
    linksHdr:SetTextColor(1, 1, 1)

    local wpuiBtn = LinkButton(f, L["STICKY_WP_BTN_WAYPOINTUI"], "https://www.curseforge.com/wow/addons/waypointui")
    wpuiBtn:SetPoint("TOPLEFT", linksHdr, "BOTTOMLEFT", 0, -6)
    local ttBtn = LinkButton(f, L["STICKY_WP_BTN_TOMTOM"], "https://www.curseforge.com/wow/addons/tomtom")
    ttBtn:SetPoint("TOPLEFT", wpuiBtn, "BOTTOMLEFT", 0, -4)

    -- ESC closes one window at a time: copy box, then this popup, then the
    -- window behind it (ALL-21). A keyboard-enabled frame gets keys before the
    -- copy box's focused editbox, so close the box here first, the same way
    -- MainWindow's ESC chain does
    BNB.AttachEscClose(f, function(self)
        local ch = BNB._clipboardHint
        if ch and ch:IsShown() and ch._dismiss then
            ch._dismiss()
        else
            self:Hide()
        end
    end)
    return f
end

local function TogglePopup(ed)
    if _popup and _popup:IsShown() and _popupOwner == ed then _popup:Hide(); return end
    _popup = _popup or BuildPopup()
    _popupOwner = ed
    local f = _popup
    if HasWPAddon() then
        f._statusLbl:SetText("|cff66ff66" .. L["STICKY_WP_STATUS_ADDON"] .. "|r")
        f._descLbl:SetText(L["NC_WP_FULL_SUPPORT_DETAIL"])
    elseif HasRetailPin() then
        f._statusLbl:SetText("|cffffaa00" .. L["STICKY_WP_STATUS_BASIC"] .. "|r")
        f._descLbl:SetText(L["NC_WP_BASIC_PIN_DETAIL"])
    else
        f._statusLbl:SetText("|cffff5555" .. L["STICKY_WP_STATUS_NONE"] .. "|r")
        f._descLbl:SetText(L["NC_WP_NO_SUPPORT_DETAIL"])
    end
    f:ClearAllPoints()
    if ed.host then
        f:SetPoint("TOPLEFT", ed.host, "TOPRIGHT", 4, 0)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    end
    f:Show()
    f:Raise()   -- Note Settings is DIALOG too since 2026-10-04: stay above it
end

--------------------------------------------------------------------------------
-- THE EDITOR
--------------------------------------------------------------------------------
function BNB.CreateSituationEditor(panel, opts)
    local padL, padR, ddR = opts.padL or 0, opts.padR or 0, opts.ddR or 0
    local ed = { panel = panel, host = opts.host }
    _editors[#_editors + 1] = ed

    -- Reload every other open editor that shows this note (a closed window
    -- loads the note itself when it opens)
    local function Sync(id)
        for _, other in ipairs(_editors) do
            if other ~= ed and other.noteID == id and other.host and other.host:IsShown() then
                other:Load(id)
            end
        end
    end
    local function NoteID() return ed.noteID end

    local KIND_LABELS = { zone = L["STICKY_KIND_ZONE"], subzone = L["STICKY_KIND_SUBZONE"],
                          instance = L["STICKY_KIND_INSTANCE"], player = L["STICKY_KIND_PLAYER"],
                          npc = L["STICKY_KIND_NPC"], guild = L["STICKY_KIND_GUILD"],
                          itype = L["SIT_ROWKIND_ITYPE"], open = L["SIT_ROWKIND_OPEN"],
                          state = L["SIT_KIND_RESTED"] }

    local y = opts.top or -8
    local hdr = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hdr:SetPoint("TOPLEFT", panel, "TOPLEFT", padL, y)
    hdr:SetTextColor(1, 0.82, 0, 1)
    hdr:SetText(L["SIT_LIST_HDR"])
    y = y - 18

    local desc = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    desc:SetPoint("TOPLEFT",  panel, "TOPLEFT",  padL, y)
    desc:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -padR, y)
    desc:SetTextColor(0.60, 0.60, 0.60)
    desc:SetText(L["SIT_LIST_DESC"])
    desc:SetJustifyH("LEFT")
    desc:SetWordWrap(false)
    y = y - 16

    local SelectType, RemoveAt, RefreshList   -- below

    -- ── The list: one row per situation, always 4 rows tall ──────────────────
    -- Nothing below it moves with the count; past 4 the mouse wheel scrolls
    -- and a thin bar on the right shows where (Dukul, 2026-10-04)
    local LIST_H = LIST_ROWS * LIST_ROW_H + 4
    local list = BNB.CreateBackdropFrame("Frame", nil, panel)
    BNB.SetBackdropDark(list)
    list:SetPoint("TOPLEFT",  panel, "TOPLEFT",  padL, y)
    list:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -padR, y)
    list:SetHeight(LIST_H)
    y = y - LIST_H - 6

    local emptyLbl = list:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    emptyLbl:SetPoint("LEFT",  list, "LEFT",  8, 0)
    emptyLbl:SetPoint("RIGHT", list, "RIGHT", -8, 0)
    emptyLbl:SetJustifyH("CENTER")
    emptyLbl:SetTextColor(0.45, 0.45, 0.45)
    emptyLbl:SetText(L["SIT_LIST_EMPTY"])

    local thumb = list:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(3)
    thumb:SetColorTexture(0.6, 0.6, 0.6, 0.6)
    thumb:Hide()

    local listOffset = 0   -- situations scrolled past the top
    local rows = {}
    for i = 1, LIST_ROWS do
        local row = CreateFrame("Frame", nil, list)
        row:SetHeight(LIST_ROW_H)
        row:SetPoint("TOPLEFT",  list, "TOPLEFT",  2, -2 - (i - 1) * LIST_ROW_H)
        row:SetPoint("TOPRIGHT", list, "TOPRIGHT", -7, -2 - (i - 1) * LIST_ROW_H)
        row:EnableMouse(true)
        local hi = row:CreateTexture(nil, "BACKGROUND")
        hi:SetAllPoints(); hi:SetColorTexture(1, 1, 1, 0.06); hi:Hide()
        row._kind = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row._kind:SetPoint("LEFT", row, "LEFT", 6, 0)
        row._kind:SetWidth(62)
        row._kind:SetJustifyH("LEFT"); row._kind:SetWordWrap(false)
        row._kind:SetTextColor(0.60, 0.60, 0.60)
        -- No confirm, like a task row's X, and shown only while the pointer
        -- is over the row (Dukul, 2026-10-04)
        row._del = BNB.CreateIconButton(row, 16, "close",
            { tip = L["SIT_REMOVE_TIP"], tipAnchor = "ANCHOR_TOP" })
        row._del:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row._del:SetScript("OnClick", function() GameTooltip:Hide(); RemoveAt(row._index) end)
        row._del:Hide()
        local function HoverOff()
            if row:IsMouseOver() then return end   -- moved between the row and its X
            hi:Hide(); row._del:Hide()
        end
        row._del:HookScript("OnEnter", function() hi:Show() end)
        row._del:HookScript("OnLeave", HoverOff)
        row._value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row._value:SetPoint("LEFT",  row._kind, "RIGHT", 4, 0)
        row._value:SetPoint("RIGHT", row._del,  "LEFT", -4, 0)
        row._value:SetJustifyH("LEFT"); row._value:SetWordWrap(false)
        -- The whole name in a tooltip when it does not fit
        row:SetScript("OnEnter", function(self)
            hi:Show(); self._del:Show()
            if self._value:IsTruncated() then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(self._kind:GetText() or "", 0.78, 0.78, 0.78)
                GameTooltip:AddLine(self._value:GetText() or "", 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide(); HoverOff() end)
        row:Hide()
        rows[i] = row
    end
    list:SetScript("OnMouseWheel", function(_, delta)
        listOffset = listOffset - delta
        RefreshList()
    end)

    -- ── Add row: [type v] [name] [browse] ────────────────────────────────────
    local TYPE_LABELS = { L["STICKY_KIND_ZONE"], L["STICKY_KIND_SUBZONE"],
                          L["STICKY_KIND_INSTANCE"], L["STICKY_KIND_PLAYER"], L["STICKY_KIND_NPC"],
                          L["STICKY_KIND_GUILD"], L["SIT_KIND_ITYPE"], L["SIT_KIND_OPEN"],
                          L["SIT_KIND_RESTED"] }
    local typ = NewChoice(panel, TYPES, TYPE_LABELS, function(k) SelectType(k) end)
    typ.frame:SetPoint("TOPLEFT", panel, "TOPLEFT", padL, y)
    typ.frame:SetWidth(TYPE_W)

    -- Spans the whole row: the autocomplete and the zone picker hang from it
    local valueRow = CreateFrame("Frame", nil, panel)
    valueRow:SetPoint("TOPLEFT",  panel, "TOPLEFT",  padL, y)
    valueRow:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -padR, y)
    valueRow:SetHeight(ROW_H)

    local valueEb = CreateFrame("EditBox", nil, valueRow, "BackdropTemplate")
    BNB.EnsureBackdrop(valueEb)
    valueEb:SetHeight(20)
    valueEb:SetFontObject("GameFontNormal")
    valueEb:SetAutoFocus(false)
    valueEb:SetMaxLetters(128)
    valueEb:SetTextInsets(4, 4, 0, 0)
    valueEb:SetTextColor(1, 1, 1)
    BNB.SetBackdropDark(valueEb)
    valueEb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Browse button (zone / instance only): the full zone picker
    local browseBtn = CreateFrame("Button", nil, valueRow)
    browseBtn:SetSize(20, 20)
    browseBtn:SetPoint("RIGHT", valueRow, "RIGHT", 0, 0)
    local browseTx = browseBtn:CreateTexture(nil, "ARTWORK")
    browseTx:SetAllPoints()
    browseTx:SetTexture(ASSETS .. "Overlay\\ov-situation")
    browseBtn:SetScript("OnEnter", function(self)
        self:SetAlpha(1.0)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["STICKY_SIT_BROWSE_TIP_TITLE"], 1, 1, 1)
        GameTooltip:AddLine(L["STICKY_SIT_BROWSE_TIP_BODY"], 0.78, 0.78, 0.78)
        GameTooltip:Show()
    end)
    browseBtn:SetScript("OnLeave", function(self)
        self:SetAlpha(0.7)
        GameTooltip:Hide()
    end)
    browseBtn:SetAlpha(0.7)
    browseBtn:Hide()

    -- The name box ends at the browse button while it shows
    local function PlaceValueBox(withBrowse)
        valueEb:ClearAllPoints()
        valueEb:SetPoint("LEFT",  valueRow, "LEFT",  TYPE_W + 6, 0)
        valueEb:SetPoint("RIGHT", valueRow, "RIGHT", withBrowse and -26 or 0, 0)
    end
    PlaceValueBox(false)

    -- Instance type and window are picked, not typed: this dropdown takes the
    -- name box's place for them; Rested has nothing to pick (ALL-232 S4)
    local function ChoiceLabels(kind)
        local labels = {}
        for i, k in ipairs(BNB.SITUATION_CHOICES[kind]) do labels[i] = BNB.SituationValueLabel(kind, k) end
        return labels
    end
    local pick = NewChoice(valueRow, BNB.SITUATION_CHOICES.itype, ChoiceLabels("itype"), function() end)
    pick.frame:SetPoint("LEFT",  valueRow, "LEFT",  TYPE_W + 6, 0)
    pick.frame:SetPoint("RIGHT", valueRow, "RIGHT", 0, 0)
    pick.frame:Hide()

    -- ── Use current / Add / Clear all ────────────────────────────────────────
    local useCurrentBtn = BNB.CreateButton(nil, panel, L["STICKY_SIT_USE_CURRENT_BTN"], 90, 22)
    useCurrentBtn:SetPoint("TOPLEFT", valueRow, "BOTTOMLEFT", 0, -4)

    local addBtn = BNB.CreateButton(nil, panel, L["SIT_ADD_BTN"], 60, 22)
    addBtn:SetPoint("LEFT", useCurrentBtn, "RIGHT", 6, 0)
    addBtn:SetEnabled(false)

    local clearBtn = BNB.CreateButton(nil, panel, L["SIT_CLEAR_ALL"], 72, 22)
    clearBtn:SetPoint("TOPRIGHT", valueRow, "BOTTOMRIGHT", 0, -4)
    clearBtn:SetEnabled(false)

    -- ── Autocomplete under the add row (2+ characters typed) ─────────────────
    local acFrame = BNB.CreateBackdropFrame("Frame", nil, panel)
    BNB.SetBackdrop(acFrame, 0.08, 0.08, 0.10, 0.97, 0.35, 0.35, 0.38, 1)
    acFrame:SetPoint("TOPLEFT",  valueRow, "BOTTOMLEFT",  0, -2)
    acFrame:SetPoint("TOPRIGHT", valueRow, "BOTTOMRIGHT", 0, -2)
    acFrame:SetFrameLevel(panel:GetFrameLevel() + 30)
    acFrame:Hide()

    local acRows, acTimer = {}, nil
    local AC_ROW_H = 22

    local function HideAC()
        acFrame:Hide()
        if acTimer then acTimer:Cancel(); acTimer = nil end
    end

    local function ShowAC(matches)
        if #matches == 0 then HideAC(); return end
        local n = math.min(#matches, 7)
        acFrame:SetHeight(n * AC_ROW_H + 4)
        for i = 1, n do
            local row = acRows[i]
            if not row then
                row = CreateFrame("Button", nil, acFrame)
                row:SetHeight(AC_ROW_H)
                local hi = row:CreateTexture(nil, "HIGHLIGHT")
                hi:SetAllPoints(); hi:SetColorTexture(1, 1, 1, 0.08)
                row._nameLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                row._nameLbl:SetPoint("LEFT",  row, "LEFT",  4, 0)
                row._nameLbl:SetPoint("RIGHT", row, "RIGHT", -80, 0)
                row._nameLbl:SetJustifyH("LEFT"); row._nameLbl:SetMaxLines(1)
                row._nameLbl:SetTextColor(1, 1, 1)
                row._contLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                row._contLbl:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                row._contLbl:SetWidth(76); row._contLbl:SetJustifyH("RIGHT"); row._contLbl:SetMaxLines(1)
                row._contLbl:SetTextColor(0.50, 0.50, 0.50)
                row:SetScript("OnClick", function(self)
                    valueEb:SetText(self._name)
                    HideAC()
                    valueEb:SetFocus()
                end)
                acRows[i] = row
            end
            local m = matches[i]
            row._name = m.name
            row._nameLbl:SetText(m.name)
            row._contLbl:SetText(m.continent or "")
            row:SetPoint("TOPLEFT",  acFrame, "TOPLEFT",  4, -2 - (i - 1) * AC_ROW_H)
            row:SetPoint("TOPRIGHT", acFrame, "TOPRIGHT", -4, -2 - (i - 1) * AC_ROW_H)
            row:Show()
        end
        for i = n + 1, #acRows do acRows[i]:Hide() end
        acFrame:Show()
    end

    valueEb:SetScript("OnTextChanged", function(self, userInput)
        local text = self:GetText() or ""
        -- A picked kind can always be added (the box is hidden, but a note
        -- switch still empties it)
        if KEY_KINDS[typ.value] then HideAC(); return end
        addBtn:SetEnabled(text:find("%S") ~= nil)
        if not userInput then return end
        -- No list of NPC or guild names to offer (GetMatches would answer with zones)
        if #text < 2 or typ.value == "npc" or typ.value == "guild" then HideAC(); return end
        -- The autocomplete takes over from an open full picker
        if BNB.ZonePicker and BNB.ZonePicker.IsShown and BNB.ZonePicker.IsShown() then
            BNB.ZonePicker.Close()
        end
        if acTimer then acTimer:Cancel() end
        acTimer = C_Timer.NewTimer(0.15, function()
            acTimer = nil
            if BNB.ZonePicker and BNB.ZonePicker.GetMatches then
                ShowAC(BNB.ZonePicker.GetMatches(text, typ.value, 7))
            end
        end)
    end)
    valueEb:HookScript("OnEditFocusLost", function()
        -- Tiny delay so row clicks register before hide
        C_Timer.After(0.2, function()
            if not acFrame:IsMouseOver() then HideAC() end
        end)
    end)

    browseBtn:SetScript("OnClick", function()
        HideAC()
        if not BNB.ZonePicker then return end
        if BNB.ZonePicker.IsShown and BNB.ZonePicker.IsShown() then
            BNB.ZonePicker.Close()
        else
            BNB.ZonePicker.Open(valueRow, function(name) valueEb:SetText(name) end, typ.value)
        end
    end)

    -- ── Show as / Trigger / How often / On leaving ───────────────────────────
    -- Label above a full-width dropdown, as everywhere else (Dukul,
    -- 2026-10-03; label-left rows ran past the window's right edge). The gaps
    -- are tighter than the old two blocks so four fit above the waypoint
    local dispDiv = Divider(panel)
    dispDiv:SetPoint("TOPLEFT",  useCurrentBtn, "BOTTOMLEFT", 0, -14)
    dispDiv:SetPoint("TOPRIGHT", panel,         "TOPRIGHT",  -padR, 0)

    local OPT_PITCH = 44   -- label 12 + 3 + dropdown 24 + gap
    -- Places row n (1-based) of the option block: its label and, under it,
    -- its picker from the left edge to the right inset of the type dropdown
    local function OptionRow(n, labelKey, c)
        local y = -6 - (n - 1) * OPT_PITCH
        local lbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", dispDiv, "BOTTOMLEFT", 0, y)
        lbl:SetText(L[labelKey])
        lbl:SetTextColor(0.78, 0.78, 0.78)
        c.frame:SetPoint("TOPLEFT", dispDiv, "BOTTOMLEFT", 0, y - 15)
        -- dispDiv ends padR from the panel edge; the dropdowns end ddR from it
        c.frame:SetPoint("TOPRIGHT", dispDiv, "BOTTOMRIGHT", padR - ddR, y - 15)
        return lbl
    end

    local disp = NewChoice(panel, DISPLAY_KEYS,
        { L["STICKY_DISP_POPUP"], L["STICKY_DISP_STICKY"], L["STICKY_DISP_BOTH"] },
        function(mode)
            local id = NoteID(); if not id then return end
            if mode == "sticky" or mode == "both" then
                BNB.UpdateNote(id, { contextDisplay = mode })
            else
                BNB.UpdateNote(id, { _clear = { "contextDisplay" } })
            end
            Sync(id)
        end)
    local dispLabel = OptionRow(1, "SIT_ROW_SHOW_AS", disp)

    local trig   -- the trigger picker, built below; RefreshLeaveRow reads it

    -- What happens to the open sticky when you leave the bound area: only for
    -- a note that shows on arriving alone. One that shows on leaving has just
    -- been shown then, so the row hides (ALL-232, "Agreed")
    local leave = NewChoice(panel, LEAVE_KEYS,
        { L["STICKY_LEAVE_KEEP"], L["STICKY_LEAVE_MINIMIZE"], L["STICKY_LEAVE_HIDE"] },
        function(mode)
            local id = NoteID(); if not id then return end
            if mode == "keep" then
                BNB.UpdateNote(id, { _clear = { "contextLeave" } })
            else
                BNB.UpdateNote(id, { contextLeave = mode })
            end
            Sync(id)
        end)
    local leaveLabel = OptionRow(4, "SIT_ROW_LEAVE", leave)

    local function RefreshLeaveRow(show)
        if show == nil then show = dispDiv:IsShown() end
        if show and trig.value ~= "arrive" then show = false end
        if show then leaveLabel:Show(); leave.frame:Show()
        else         leaveLabel:Hide(); leave.frame:Hide() end
    end

    -- A changed trigger or how-often starts counting afresh: a note set to
    -- "Only once" and back again shows again
    local function ResetSeen(id)
        local note = BNB.GetNote(id)
        if note then note.contextSeen = nil end
    end

    -- When it shows: arriving (nil), leaving, or both. A player situation is
    -- no place: it matches while that player is your target or in your
    -- group, so its words are "meet" and "gone" (Dukul, 2026-10-03). A note
    -- with places and players gets neutral words (agreed 2026-10-03)
    local PLACE_TRIG   = { L["SIT_TRIGGER_ARRIVE"], L["SIT_TRIGGER_LEAVE"], L["SIT_TRIGGER_BOTH"] }
    local PLAYER_TRIG  = { L["SIT_TRIGGER_MEET"], L["SIT_TRIGGER_GONE"], L["SIT_TRIGGER_BOTH_PLAYER"] }
    local NEUTRAL_TRIG = { L["SIT_TRIGGER_START"], L["SIT_TRIGGER_END"], L["SIT_TRIGGER_BOTH_ANY"] }
    -- A window is opened and closed (ALL-232 S4)
    local WINDOW_TRIG  = { L["SIT_TRIGGER_OPEN"], L["SIT_TRIGGER_CLOSE"], L["SIT_TRIGGER_BOTH_WINDOW"] }
    trig = NewChoice(panel, TRIGGER_KEYS, PLACE_TRIG,
        function(mode)
            local id = NoteID(); if not id then return end
            if mode == "arrive" then
                BNB.UpdateNote(id, { _clear = { "contextTrigger" } })
            else
                BNB.UpdateNote(id, { contextTrigger = mode })
            end
            ResetSeen(id)
            RefreshLeaveRow()
            Sync(id)
        end)
    local trigLabel = OptionRow(2, "SIT_ROW_TRIGGER", trig)
    local hasPlayer = false   -- a player is among the note's situations
    trig.frame:HookScript("OnEnter", function(self)
        if not hasPlayer then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["SIT_ROW_TRIGGER"], 1, 1, 1)
        GameTooltip:AddLine(L["SIT_TRIGGER_PLAYER_TIP"], 0.78, 0.78, 0.78, true)
        GameTooltip:Show()
    end)
    trig.frame:HookScript("OnLeave", function() GameTooltip:Hide() end)

    -- Called by RefreshList: the trigger and leave rows speak of places, of
    -- players, of windows, or neutrally of a mix, after the note's situations
    -- (mode "place" / "player" / "window" / "mixed"); withPlayer = a player
    -- kind is among them (the trigger's tooltip explains meeting)
    local function ApplyKindWords(mode, withPlayer)
        hasPlayer = withPlayer
        local words, leaveKey = PLACE_TRIG, "SIT_ROW_LEAVE"
        if mode == "player" then words, leaveKey = PLAYER_TRIG, "SIT_ROW_GONE"
        elseif mode == "window" then words, leaveKey = WINDOW_TRIG, "SIT_ROW_CLOSED"
        elseif mode == "mixed" then words, leaveKey = NEUTRAL_TRIG, "SIT_ROW_END" end
        trig:SetLabels(words)
        leaveLabel:SetText(L[leaveKey])
    end

    -- How often, per character
    local freq = NewChoice(panel, FREQ_KEYS,
        { L["SIT_FREQ_ALWAYS"], L["SIT_FREQ_SESSION"], L["SIT_FREQ_DAY"],
          L["SIT_FREQ_DAILY"], L["SIT_FREQ_WEEKLY"], L["SIT_FREQ_ONCE"] },
        function(mode)
            local id = NoteID(); if not id then return end
            if mode == "always" then
                BNB.UpdateNote(id, { _clear = { "contextFreq" } })
            else
                BNB.UpdateNote(id, { contextFreq = mode })
            end
            ResetSeen(id)
            Sync(id)
        end)
    local freqLabel = OptionRow(3, "SIT_ROW_FREQ", freq)
    freq.frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["SIT_ROW_FREQ"], 1, 1, 1)
        GameTooltip:AddLine(L["SIT_FREQ_TIP"], 0.78, 0.78, 0.78, true)
        GameTooltip:Show()
    end)
    freq.frame:HookScript("OnLeave", function() GameTooltip:Hide() end)

    -- ── Waypoint ─────────────────────────────────────────────────────────────
    -- note.waypoints = { { mapID, x, y, label, name, on }, ... } (ALL-282,
    -- Core/NoteFields.lua). TomTom (TomTom:AddWaypoint)
    -- and the built-in map pin (C_Map.SetUserWaypoint) are both used if present.
    local wpDiv = Divider(panel)
    wpDiv:SetPoint("TOPLEFT",  dispDiv, "TOPLEFT",  0, -(6 + 4 * OPT_PITCH + 4))
    wpDiv:SetPoint("TOPRIGHT", panel,    "TOPRIGHT", -padR, 0)

    local wpHdr = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    wpHdr:SetPoint("TOPLEFT", wpDiv, "BOTTOMLEFT", 0, -6)
    wpHdr:SetTextColor(1, 0.82, 0, 1)
    wpHdr:SetText(L["STICKY_WP_HEADER"])

    -- "(Addon installed)" / "(Enhanced)" / "(Basic)" / "(Addon required)"
    local wpStatusTag = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    wpStatusTag:SetPoint("LEFT", wpHdr, "RIGHT", 6, 0)

    local function RefreshWPStatusTag()
        if HasWPAddon() then
            wpStatusTag:SetText(HasRetailPin() and L["STICKY_WP_TAG_ENHANCED"] or L["STICKY_WP_TAG_ADDON"])
            wpStatusTag:SetTextColor(0.4, 1, 0.4)
        elseif HasRetailPin() then
            wpStatusTag:SetText(L["STICKY_WP_TAG_BASIC"])
            wpStatusTag:SetTextColor(0.85, 0.70, 0.2)
        else
            wpStatusTag:SetText(L["STICKY_WP_TAG_REQUIRED"])
            wpStatusTag:SetTextColor(0.85, 0.30, 0.25)
        end
    end

    -- "?" label (visual only; the hit frame below takes the click)
    local wpInfoLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    wpInfoLbl:SetPoint("LEFT", wpStatusTag, "RIGHT", 4, 0)
    wpInfoLbl:SetText("|cff88bbff?|r")

    local wpInfoHit = CreateFrame("Button", nil, panel)
    wpInfoHit:SetPoint("LEFT",  wpStatusTag, "LEFT",  -2, 0)
    wpInfoHit:SetPoint("RIGHT", wpInfoLbl,   "RIGHT",  4, 0)
    wpInfoHit:SetHeight(18)
    wpInfoHit:SetScript("OnClick", function() TogglePopup(ed) end)
    wpInfoHit:SetScript("OnEnter", function(self)
        wpInfoLbl:SetText("|cffbbddff?|r")
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["STICKY_WP_INFO_TIP"], 0.55, 0.85, 1)
        GameTooltip:Show()
    end)
    wpInfoHit:SetScript("OnLeave", function()
        wpInfoLbl:SetText("|cff88bbff?|r")
        GameTooltip:Hide()
    end)

    local wpDesc = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    wpDesc:SetPoint("TOPLEFT",  wpHdr, "BOTTOMLEFT", 0, -4)
    wpDesc:SetPoint("TOPRIGHT", panel, "TOPRIGHT",  -padR, 0)
    wpDesc:SetJustifyH("LEFT"); wpDesc:SetWordWrap(true)

    -- [Pin here] [Navigate] [Clear WP] / [Manual] beside a column of two
    -- checkboxes (Dukul, 2026-10-03: one row less than the old 2x2 grid with
    -- the checkbox under it; the room went to the Situation options above)
    local BTN_W, BTN_H, BTN_GAP = 72, 22, 6
    local wpPinBtn = BNB.CreateButton(nil, panel, L["STICKY_WP_BTN_PIN_HERE"], BTN_W, BTN_H)
    wpPinBtn:SetPoint("TOPLEFT", wpDesc, "BOTTOMLEFT", 0, -6)
    local wpNavBtn = BNB.CreateButton(nil, panel, L["STICKY_WP_BTN_NAVIGATE"], BTN_W, BTN_H)
    wpNavBtn:SetPoint("LEFT", wpPinBtn, "RIGHT", BTN_GAP, 0)
    local wpClearBtn = BNB.CreateButton(nil, panel, L["STICKY_WP_BTN_CLEAR"], BTN_W, BTN_H)
    wpClearBtn:SetPoint("LEFT", wpNavBtn, "RIGHT", BTN_GAP, 0)
    local wpManualBtn = BNB.CreateButton(nil, panel, L["STICKY_WP_BTN_MANUAL"], BTN_W, BTN_H)

    -- The two checkboxes in one column right of Manual, Manual centred on the
    -- pair (Dukul, 2026-10-05: "Don't track it" alone on a row looked lost).
    -- One line each; a long translation is cut at the panel edge, the
    -- tooltips carry the full text.
    local CHK_PITCH = 22
    local function WpCheck(labelKey, tipKey, field)
        local chk = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        chk:SetSize(24, 24)
        local lbl = chk:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("LEFT", chk, "RIGHT", 2, 0)
        lbl:SetPoint("RIGHT", panel, "RIGHT", -padR, 0)
        lbl:SetJustifyH("LEFT")
        lbl:SetWordWrap(false)
        lbl:SetText(L[labelKey])
        lbl:SetTextColor(0.78, 0.78, 0.78)
        chk:SetScript("OnClick", function(self)
            local id = NoteID(); if not id then return end
            if self:GetChecked() then
                BNB.UpdateNote(id, { [field] = true })
            else
                BNB.UpdateNote(id, { _clear = { field } })
            end
            Sync(id)
        end)
        chk:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(L[tipKey], 0.85, 0.85, 0.85, true)
            GameTooltip:Show()
        end)
        chk:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return chk
    end
    -- "Remove on zone leave" (wpClearOnLeave)
    local wpLeaveChk = WpCheck("STICKY_WP_LEAVE_REMOVE_LABEL", "NC_WP_LEAVE_REMOVE_TIP", "wpClearOnLeave")
    wpLeaveChk:SetPoint("TOPLEFT", wpPinBtn, "BOTTOMRIGHT", BTN_GAP - 2, -2)
    -- "Don't track it" (note.wpNoTrack, SUG-10). Only the waypoint a situation
    -- places honours it; Navigate and waypoint links in the text always track.
    local wpNoTrackChk = WpCheck("STICKY_WP_NOTRACK_LABEL", "NC_WP_NOTRACK_TIP", "wpNoTrack")
    wpNoTrackChk:SetPoint("TOPLEFT", wpLeaveChk, "TOPLEFT", 0, -CHK_PITCH)
    -- Manual's right edge on the pair's middle (1 px over the first box's bottom)
    wpManualBtn:SetPoint("RIGHT", wpLeaveChk, "BOTTOMLEFT", -(BTN_GAP - 2), 1)

    -- Manual coordinates row (hidden until Manual is clicked), under the
    -- checkbox column; nothing else lives there, so nothing has to move
    -- (ALL-233)
    local wpManualRow = CreateFrame("Frame", nil, panel)
    wpManualRow:SetHeight(22)
    wpManualRow:SetPoint("TOPLEFT",  wpPinBtn, "BOTTOMLEFT", 0, -(2 + CHK_PITCH + 24 + 4))
    wpManualRow:SetPoint("TOPRIGHT", panel,      "TOPRIGHT",  -padR, 0)
    wpManualRow:Hide()

    local function CoordBox(anchor, label)
        local lbl = wpManualRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        if anchor then lbl:SetPoint("LEFT", anchor, "RIGHT", 6, 0)
        else lbl:SetPoint("LEFT", wpManualRow, "LEFT", 0, 0) end
        lbl:SetText(label)
        lbl:SetTextColor(0.78, 0.78, 0.78)
        lbl:SetWidth(14)
        local eb = CreateFrame("EditBox", nil, wpManualRow, "BackdropTemplate")
        BNB.EnsureBackdrop(eb)
        BNB.SetBackdropDark(eb)
        eb:SetPoint("LEFT", lbl, "RIGHT", 2, 0)
        eb:SetSize(52, 20)
        eb:SetFontObject("GameFontNormalSmall")
        eb:SetAutoFocus(false); eb:SetMaxLetters(8)
        eb:SetNumeric(false); eb:SetTextInsets(3, 3, 0, 0)
        return eb
    end
    local wpXEb = CoordBox(nil, L["STICKY_WP_X_LABEL"])
    local wpYEb = CoordBox(wpXEb, L["STICKY_WP_Y_LABEL"])
    local wpSetBtn = BNB.CreateButton(nil, wpManualRow, L["STICKY_WP_BTN_SET"], 38, 20)
    wpSetBtn:SetPoint("LEFT", wpYEb, "RIGHT", 4, 0)


    -- Waypoint line at the panel bottom
    local bottom = opts.bottom or 6
    local wpStatusLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    wpStatusLbl:SetPoint("BOTTOMLEFT",  panel, "BOTTOMLEFT",  padL, bottom)
    wpStatusLbl:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -padR, bottom)
    wpStatusLbl:SetJustifyH("CENTER")
    wpStatusLbl:SetTextColor(0.55, 0.85, 1, 1)
    wpStatusLbl:Hide()

    -- Everything below the add row shows only while the note has a situation
    local typedOnly = { dispDiv, dispLabel, disp.frame, trigLabel, trig.frame, freqLabel, freq.frame,
                        wpDiv, wpHdr, wpDesc, wpStatusTag, wpInfoLbl, wpInfoHit,
                        wpPinBtn, wpNavBtn, wpClearBtn, wpManualBtn, wpLeaveChk, wpNoTrackChk }

    -- ── Refreshers ───────────────────────────────────────────────────────────
    local function RefreshWaypointDisplay()
        -- The last waypoint added (ALL-282 S2 turns this into a list)
        local note = NoteID() and BNB.GetNote(NoteID())
        local wps  = BNB.NoteWaypoints(note)
        local wp   = wps[#wps]
        if wp and wp.x and wp.y then
            local title = BNB.WaypointName(note, wp)
            local coords = string.format("%.1f, %.1f", wp.x, wp.y)
            if #wps > 1 then coords = coords .. string.format(" (+%d)", #wps - 1) end
            wpStatusLbl:SetText(L["STICKY_WP_STATUS_LABEL"] .. "\n"
                .. (title ~= "" and (title .. "\n") or "") .. coords)
            wpStatusLbl:Show()
        else
            wpStatusLbl:SetText("")
            wpStatusLbl:Hide()
        end
    end

    local function ShowTypedControls(show)
        for _, w in ipairs(typedOnly) do   -- FontStrings among them: Show/Hide, never SetShown
            if show then w:Show() else w:Hide() end
        end
        RefreshLeaveRow(show)
        if not show then wpManualRow:Hide(); return end
        RefreshWPStatusTag()
        local note = NoteID() and BNB.GetNote(NoteID())
        wpLeaveChk:SetChecked(note and note.wpClearOnLeave == true)
        wpNoTrackChk:SetChecked(note and note.wpNoTrack == true)
        -- Greyed without any waypoint support
        local avail = WPAvailable() and true or false
        wpPinBtn:SetEnabled(avail); wpNavBtn:SetEnabled(avail)
        wpClearBtn:SetEnabled(avail); wpManualBtn:SetEnabled(avail)
        wpLeaveChk:SetEnabled(avail); wpNoTrackChk:SetEnabled(avail)
        if avail then
            wpDesc:SetText(L["STICKY_WP_DESC"])
            wpDesc:SetTextColor(0.60, 0.60, 0.60)
        else
            wpDesc:SetText(L["NC_WP_INSTALL_ADDON_FEATURE"])
            wpDesc:SetTextColor(0.65, 0.40, 0.35)
        end
    end

    -- The list rows, the scroll bar, the trigger words and what shows below
    RefreshList = function()
        local sits = BNB.NoteSituations(NoteID() and BNB.GetNote(NoteID()))
        local n = #sits
        listOffset = math.max(0, math.min(listOffset, n - LIST_ROWS))
        for i, row in ipairs(rows) do
            local idx = listOffset + i
            local s = sits[idx]
            if s then
                local kind, value = BNB.DecodeContext(s)
                row._index = idx
                row._kind:SetText(KIND_LABELS[kind] or kind or "?")
                row._value:SetText(BNB.SituationValueLabel(kind, value) or s)
                row:Show()
                -- A hidden row gets no OnLeave: its X must not come back with it
                if not row:IsMouseOver() then row._del:Hide() end
            else
                row._index = nil
                row:Hide()
                row._del:Hide()
            end
        end
        if n == 0 then emptyLbl:Show() else emptyLbl:Hide() end
        -- "Situations (4)" (Dukul, 2026-10-04); no count while empty
        hdr:SetText(n > 0 and string.format(L["SIT_LIST_HDR_FMT"], n) or L["SIT_LIST_HDR"])
        list:EnableMouseWheel(n > LIST_ROWS)   -- otherwise the wheel is the window's
        if n > LIST_ROWS then
            local inner = LIST_ROWS * LIST_ROW_H
            local h = math.max(8, inner * LIST_ROWS / n)
            thumb:ClearAllPoints()
            thumb:SetPoint("TOPRIGHT", list, "TOPRIGHT", -2, -2 - (inner - h) * listOffset / (n - LIST_ROWS))
            thumb:SetHeight(h)
            thumb:Show()
        else
            thumb:Hide()
        end
        -- Instance type and rested are places; a window is its own group
        local place, player, window = false, false, false
        for _, s in ipairs(sits) do
            local k = BNB.DecodeContext(s)
            if PLAYER_KINDS[k] then player = true
            elseif k == "open" then window = true
            else place = true end
        end
        local groups = (place and 1 or 0) + (player and 1 or 0) + (window and 1 or 0)
        ApplyKindWords(groups > 1 and "mixed" or player and "player" or window and "window" or "place",
            player)
        ShowTypedControls(n > 0)
        clearBtn:SetEnabled(n > 0)
    end

    SelectType = function(t)
        typ.value = t
        -- The zone picker covers zones and instances only
        local browse = (t == "zone" or t == "instance")
        browseBtn:SetShown(browse)
        PlaceValueBox(browse)
        -- Typed name, a picked key, or nothing to pick (Rested)
        local choices = BNB.SITUATION_CHOICES and BNB.SITUATION_CHOICES[t]
        valueEb:SetShown(not KEY_KINDS[t])
        if choices then pick:SetChoices(choices, ChoiceLabels(t)); pick.frame:Show()
        else pick.frame:Hide() end
        useCurrentBtn:SetEnabled(t ~= "state")   -- Rested has nothing to fill in
        if KEY_KINDS[t] then
            valueEb:ClearFocus()
            addBtn:SetEnabled(true)
        else
            addBtn:SetEnabled((valueEb:GetText() or ""):find("%S") ~= nil)
        end
        HideAC()
        if BNB.ZonePicker and BNB.ZonePicker.Close then BNB.ZonePicker.Close() end
    end

    -- Saves the note's new situation list and brings everything that shows
    -- it up to date
    local function SaveSituations(id, sits)
        if #sits > 0 then
            BNB.UpdateNote(id, { situations = sits })
        else
            BNB.UpdateNote(id, { _clear = { "situations" } })
        end
        RefreshList()
        if BNB.CheckContextualNotes then BNB.CheckContextualNotes() end
        if BNB.Sticky and BNB.Sticky.RefreshMarkers then BNB.Sticky.RefreshMarkers(id) end
        Sync(id)
    end

    RemoveAt = function(idx)
        local id = NoteID(); if not id or not idx then return end
        local sits = {}
        for i, s in ipairs(BNB.NoteSituations(BNB.GetNote(id))) do
            if i ~= idx then sits[#sits + 1] = s end
        end
        SaveSituations(id, sits)
    end

    -- Adds the add row's situation at the end of the list; one the note
    -- already has (situations match without case) is left out with a line
    local function AddSituation()
        local id = NoteID(); if not id then return end
        local val
        if typ.value == "state" then
            val = "rested"   -- the one state there is
        elseif KEY_KINDS[typ.value] then
            val = pick.value or ""
        else
            val = (valueEb:GetText() or ""):match("^%s*(.-)%s*$") or ""
        end
        if val == "" then return end
        local s = typ.value .. ":" .. val
        local sits = {}
        for i, old in ipairs(BNB.NoteSituations(BNB.GetNote(id))) do
            if old:lower() == s:lower() then BNB:Print(L["SIT_DUPLICATE"]); return end
            sits[i] = old
        end
        sits[#sits + 1] = s
        valueEb:SetText("")
        valueEb:ClearFocus()
        HideAC()
        listOffset = #sits   -- clamped by RefreshList: the new row shows at the bottom
        SaveSituations(id, sits)
    end

    -- ── Button handlers ──────────────────────────────────────────────────────
    useCurrentBtn:SetScript("OnClick", function()
        local t, val = typ.value, ""
        -- A picked kind: the instance type you are in or the window that is
        -- open; nothing changes when there is none
        if KEY_KINDS[t] then
            local cur = BNB.CurrentSituationValue and BNB.CurrentSituationValue(t)
            if cur and t ~= "state" then pick:Set(cur) end
            return
        end
        if t == "zone" then
            val = GetZoneText() or ""
        elseif t == "subzone" then
            val = GetSubZoneText and GetSubZoneText() or ""
        elseif t == "instance" then
            val = (GetInstanceInfo and select(1, GetInstanceInfo())) or GetRealZoneText() or ""
        elseif t == "player" or t == "npc" then
            val = (BNB.UnitNameRealm("target")) or ""
        elseif t == "guild" then
            -- The target's guild, never your own through targeting yourself
            if UnitIsPlayer("target") and not UnitIsUnit("target", "player") then
                val = GetGuildInfo("target") or ""
            end
        end
        valueEb:SetText(val)
    end)

    addBtn:SetScript("OnClick", AddSituation)
    valueEb:SetScript("OnEnterPressed", AddSituation)

    -- With 2+ situations Clear all takes two clicks: the first turns the
    -- button into "Sure?" for a few seconds (Dukul, 2026-10-04)
    local CLEAR_ARM_SECS = 3
    local clearArmed, clearTimer = false, nil
    local function DisarmClear()
        clearArmed = false
        if clearTimer then clearTimer:Cancel(); clearTimer = nil end
        clearBtn:SetText(L["SIT_CLEAR_ALL"])
    end
    clearBtn:HookScript("OnHide", DisarmClear)

    -- Every situation and every option back to the defaults
    clearBtn:SetScript("OnClick", function()
        local id = NoteID(); if not id then return end
        if not clearArmed and #BNB.NoteSituations(BNB.GetNote(id)) > 1 then
            clearArmed = true
            clearBtn:SetText("|cffff5555" .. L["SIT_CLEAR_SURE"] .. "|r")
            clearTimer = C_Timer.NewTimer(CLEAR_ARM_SECS, DisarmClear)
            return
        end
        DisarmClear()
        BNB.UpdateNote(id, { _clear = { "situations", "contextDisplay", "contextLeave",
                                        "contextTrigger", "contextFreq" } })
        ResetSeen(id)
        if BNB.Sticky and BNB.Sticky.RefreshMarkers then BNB.Sticky.RefreshMarkers(id) end
        disp:Set("popup"); leave:Set("keep")
        trig:Set("arrive"); freq:Set("always")
        listOffset = 0
        RefreshList()
        -- Also take this note's placed waypoints off the map
        if BNB.RemoveNoteWaypoints then BNB.RemoveNoteWaypoints(id) end
        if BNB.CheckContextualNotes then BNB.CheckContextualNotes() end
        Sync(id)
    end)

    -- Adds a waypoint at x, y (0-100) on mapID, placed by the situation (on).
    -- Without TomTom the game's pin holds one point, so the others go off
    local function SetWaypoint(note, id, mapID, x, y, msgKey)
        local zone = GetRealZoneText() or GetZoneText() or ""
        local list = {}
        local single = not (TomTom and TomTom.AddWaypoint)
        for _, wp in ipairs(BNB.NoteWaypoints(note)) do
            local c = BNB.CleanWaypoint(wp)
            if c then
                if single then c.on = nil end
                list[#list + 1] = c
            end
        end
        local wp = { mapID = mapID, x = x, y = y, label = zone ~= "" and zone or nil, on = true }
        list[#list + 1] = wp
        local fields = { waypoints = list }
        if single and note.wpCreatedOn then fields._clear = { "wpCreatedOn" } end
        BNB.UpdateNote(id, fields)
        RefreshWaypointDisplay()
        BNB:Print(string.format(L[msgKey], BNB.WaypointName(note, wp), x, y))
        Sync(id)
    end

    local function CommitManualCoords()
        local id   = NoteID(); if not id then return end
        local note = BNB.GetNote(id); if not note then return end
        local x = tonumber(wpXEb:GetText():match("^%s*(.-)%s*$") or "")
        local y2 = tonumber(wpYEb:GetText():match("^%s*(.-)%s*$") or "")
        if not x or not y2 then
            BNB:Print("|cffff6666Invalid coordinates. Enter numbers like 54.3|r"); return
        end
        x  = math.max(0, math.min(100, x))
        y2 = math.max(0, math.min(100, y2))
        local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        wpManualRow:Hide()
        local last = BNB.NoteWaypoints(note)[#BNB.NoteWaypoints(note)]
        SetWaypoint(note, id, mapID or (last and last.mapID), x, y2, "NC_WP_SET_MANUAL_MSG")
    end

    wpManualBtn:SetScript("OnClick", function()
        if wpManualRow:IsShown() then wpManualRow:Hide(); return end
        -- Pre-filled with the last saved waypoint
        local note = NoteID() and BNB.GetNote(NoteID())
        local wps  = BNB.NoteWaypoints(note)
        local wp   = wps[#wps]
        if wp and wp.x then wpXEb:SetText(string.format("%.1f", wp.x)) end
        if wp and wp.y then wpYEb:SetText(string.format("%.1f", wp.y)) end
        wpManualRow:Show()
        wpXEb:SetFocus()
    end)
    Tip(wpManualBtn, L["STICKY_WP_MANUAL_TIP"])
    wpSetBtn:SetScript("OnClick", CommitManualCoords)
    wpXEb:SetScript("OnEnterPressed", function() wpYEb:SetFocus() end)
    wpYEb:SetScript("OnEnterPressed", CommitManualCoords)
    wpXEb:SetScript("OnEscapePressed", function() wpManualRow:Hide() end)
    wpYEb:SetScript("OnEscapePressed", function() wpManualRow:Hide() end)

    wpPinBtn:SetScript("OnClick", function()
        local id   = NoteID(); if not id then return end
        local note = BNB.GetNote(id); if not note then return end
        local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        if not mapID then BNB:Print("|cffff6666Cannot get map position.|r"); return end
        local pos = C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
        if not pos then BNB:Print("|cffff6666Cannot get map position.|r"); return end
        local px, py = pos:GetXY()
        SetWaypoint(note, id, mapID, math.floor(px * 1000 + 0.5) / 10,
            math.floor(py * 1000 + 0.5) / 10, "NC_WP_PINNED_MSG")
    end)
    Tip(wpPinBtn, L["STICKY_WP_PIN_TIP_TITLE"], L["STICKY_WP_PIN_TIP_BODY"], true)

    -- Every waypoint placed by the situation; none on = the first waypoint,
    -- else where the note was made
    wpNavBtn:SetScript("OnClick", function()
        local note = NoteID() and BNB.GetNote(NoteID()); if not note then return end
        local list = BNB.ActiveWaypoints(note)
        if not list[1] then list = { BNB.NoteWaypoints(note)[1] or BNB.CreationWaypoint(note) } end
        if not list[1] then
            BNB:Print("|cffff6666No waypoint set on this note.|r"); return
        end
        BNB.NavigateWaypoints(note, list)
    end)
    Tip(wpNavBtn, L["STICKY_WP_NAV_TIP_TITLE"], L["STICKY_WP_NAV_TIP_BODY"], true)

    wpClearBtn:SetScript("OnClick", function()
        local id = NoteID(); if not id then return end
        BNB.UpdateNote(id, { _clear = { "waypoints", "wpCreatedOn" } })
        RefreshWaypointDisplay()
        Sync(id)
    end)
    Tip(wpClearBtn, L["STICKY_WP_REMOVE_TIP"])

    -- The popup is parented to UIParent, so it would outlive the window
    if ed.host then
        ed.host:HookScript("OnHide", function()
            if _popup and _popupOwner == ed then _popup:Hide() end
        end)
    end

    -- ── Load a note ──────────────────────────────────────────────────────────
    function ed:Load(noteID)
        -- Another note: back to the top of the list, and not the previous
        -- note's half-typed name. The same note (a save in the other editor)
        -- keeps both
        if noteID ~= self.noteID then
            listOffset = 0
            valueEb:SetText("")
            HideAC()
            DisarmClear()
        end
        self.noteID = noteID
        local note = noteID and BNB.GetNote(noteID)
        local cd = note and note.contextDisplay
        disp:Set((cd == "sticky" or cd == "both") and cd or "popup")
        local lv = note and note.contextLeave
        leave:Set((lv == "minimize" or lv == "hide") and lv or "keep")
        local tr = note and note.contextTrigger
        trig:Set((tr == "leave" or tr == "both") and tr or "arrive")
        local fq = note and note.contextFreq
        local known = false
        for _, k in ipairs(FREQ_KEYS) do if k == fq then known = true end end
        freq:Set(known and fq or "always")
        RefreshList()
        RefreshWaypointDisplay()
    end

    -- Start empty: nothing below the add row until the note has a situation
    typ:Set("zone")
    SelectType("zone")
    ShowTypedControls(false)
    return ed
end

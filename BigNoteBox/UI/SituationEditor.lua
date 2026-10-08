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
-- X removes it, right-click = Edit / Remove) above one add row (ALL-232 S3,
-- Dukul's layout A, 2026-10-04). The waypoint list sits at the bottom, shown
-- with or without a situation: the creation spot, then every waypoint
-- (Name | Zone | X, Y; click = green / grey, double-click the name = rename,
-- hover arrow = navigate, hover X = remove, right-click = all of those,
-- ALL-282 S2).
--
-- Public API:
--   BNB.CreateSituationEditor(panel, opts) -> ed   build once per window
--     opts.padL, opts.padR  panel edge to the content
--     opts.ddR              right inset of the dropdowns
--     opts.top              y of the header
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
local LIST_ROWS, LIST_ROW_H = 5, 20   -- the list box is always 5 rows; the wheel scrolls past that
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
-- WaypointUI draws the game's own pin in the world (arrow, distance). It does
-- not provide TomTom's API, so placement stays one point through the game's
-- pin; only the status says it is there (ALL-307)
local function HasWaypointUI() return WaypointUIAPI and WaypointUIAPI.Navigation and true or false end
local function WPAvailable()  return HasWPAddon() or HasRetailPin() end

-- Divider line in the skin border colour (skin mode) or grey
local function Divider(panel)
    local t = panel:CreateTexture(nil, "ARTWORK")
    t:SetHeight(1)
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset then
        local br, bg_, bb = BNB.SkinRuleOf(BNB.GetSkinPreset())
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

-- The thin scroll bar of a list box showing `shown` of n rows from offset;
-- rowH = the list's row height (nil = LIST_ROW_H)
local function PlaceThumb(thumb, list, shown, n, offset, rowH)
    if n <= shown then thumb:Hide(); return end
    local inner = shown * (rowH or LIST_ROW_H)
    local h = math.max(8, inner * shown / n)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOPRIGHT", list, "TOPRIGHT", -2, -2 - (inner - h) * offset / (n - shown))
    thumb:SetHeight(h)
    thumb:Show()
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
    local dd = BNB.SkinDropdown(CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate"))
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
        if not self:IsEnabled() then return end   -- addon already installed (ALL-316)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["NC_WP_COPY_URL_TIP"], 0.55, 0.85, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function BuildPopup()
    local f = BNB.CreateBackdropFrame("Frame", "BNBWaypointInfoPopup", UIParent)
    f:SetSize(310, 210)   -- 20 px shorter (ALL-316)
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

    -- Our close button (ALL-316); follows skin mode like the window's look
    local closeBtn = BNB.CreateIconButton(f, 20, "close", { onClick = function() f:Hide() end })
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)

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
    wpuiBtn:SetPoint("RIGHT", f, "RIGHT", -14, 0)   -- the buttons fill the width (ALL-316)
    local ttBtn = LinkButton(f, L["STICKY_WP_BTN_TOMTOM"], "https://www.curseforge.com/wow/addons/tomtom")
    ttBtn:SetPoint("TOPLEFT", wpuiBtn, "BOTTOMLEFT", 0, -4)
    ttBtn:SetPoint("RIGHT", f, "RIGHT", -14, 0)
    f._wpuiBtn, f._ttBtn = wpuiBtn, ttBtn

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
    elseif HasWaypointUI() and HasRetailPin() then
        f._statusLbl:SetText("|cff66ff66" .. L["STICKY_WP_STATUS_WAYPOINTUI"] .. "|r")
        f._descLbl:SetText(L["NC_WP_WAYPOINTUI_DETAIL"])
    elseif HasRetailPin() then
        f._statusLbl:SetText("|cffffaa00" .. L["STICKY_WP_STATUS_BASIC"] .. "|r")
        f._descLbl:SetText(L["NC_WP_BASIC_PIN_DETAIL"])
    else
        f._statusLbl:SetText("|cffff5555" .. L["STICKY_WP_STATUS_NONE"] .. "|r")
        f._descLbl:SetText(L["NC_WP_NO_SUPPORT_DETAIL"])
    end
    -- An addon that is installed has nothing to link to (ALL-316)
    f._wpuiBtn:SetEnabled(not HasWaypointUI())
    f._ttBtn:SetEnabled(not HasWPAddon())
    f:ClearAllPoints()
    if ed.host then
        f:SetPoint("TOPLEFT", ed.host, "TOPRIGHT", 4, 0)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    end
    f:Show()
    f:Raise()   -- Note Settings is DIALOG too since 2026-10-04: stay above it
end

-- ── Waypoint rows (ALL-354) ─────────────────────────────────────────────────
-- Two lines per waypoint: Name | X, Y on top, Zone | Sub-zone below, a faint
-- rule between waypoints. The list is the situation list plus two rows tall
-- (Dukul, 2026-10-06), which holds four waypoints
-- Note Settings' tabs do not scroll (ALL-318): these and the side-by-side
-- checkboxes keep the section inside the 640 px window
local WP_ROWS, WP_ROW_H  = 4, 32
local WP_LINE_H          = 15
local WP_HDR_LINE_H      = 11
local WP_XY_W            = 92   -- room for the X and Y edit boxes over it

-- The four columns inside a holder as wide as a row (a row, or the labels
-- above the list); y1 / y2 = top of each line, h = line height
local function PlaceWpCols(holder, nameFS, xyFS, zoneFS, subFS, y1, y2, h)
    xyFS:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -4, y1); xyFS:SetWidth(WP_XY_W)
    nameFS:SetPoint("TOPLEFT",  holder, "TOPLEFT", 6, y1)
    nameFS:SetPoint("TOPRIGHT", xyFS,   "TOPLEFT", -4, 0)
    zoneFS:SetPoint("TOPLEFT",  holder, "TOPLEFT", 6, y2)
    zoneFS:SetPoint("TOPRIGHT", holder, "TOP",    -2, y2)
    subFS:SetPoint("TOPLEFT",   holder, "TOP",     2, y2)
    subFS:SetPoint("TOPRIGHT",  holder, "TOPRIGHT", -4, y2)
    for _, fs in ipairs({ nameFS, xyFS, zoneFS, subFS }) do
        fs:SetHeight(h)
        fs:SetJustifyH("LEFT"); fs:SetJustifyV("MIDDLE"); fs:SetWordWrap(false)
    end
end

-- One waypoint row's look: highlight, four columns, the rule under it and
-- the two hover buttons, drawn over the text at the right end (arrow on the
-- top line, X on the bottom one). The editor gives it its scripts
local function NewWaypointRow(list, i)
    local row = CreateFrame("Button", nil, list)
    row:SetHeight(WP_ROW_H)
    local top = -2 - (i - 1) * WP_ROW_H
    row:SetPoint("TOPLEFT",  list, "TOPLEFT",  2, top)
    row:SetPoint("TOPRIGHT", list, "TOPRIGHT", -7, top)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    -- The Trash / Alarms hover art, stretched over the two-line row (Dukul, 2026-10-08)
    -- Skin mode fill at 18%: 6% could not be seen over the dark list (Dukul)
    row._hi = BNB.CreateListRowArt(row, "hover", { 1, 1, 1, 0.18 })
    local function Col() return row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") end
    row._name, row._xy, row._zone, row._sub = Col(), Col(), Col(), Col()
    PlaceWpCols(row, row._name, row._xy, row._zone, row._sub, -1, -1 - WP_LINE_H, WP_LINE_H)
    -- The rule between this waypoint and the next: the editor's 1 px rule,
    -- grey in normal mode, the preset's border tint in skin mode (ALL-246;
    -- it was white at 8% and could not be seen, Dukul 2026-10-07)
    local rule = BNB.CreateNoteRule(row)
    rule:SetPoint("BOTTOMLEFT",  row, "BOTTOMLEFT",  4, 0)
    rule:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 0)
    rule:Hide()
    row._rule = rule
    -- X removes (no confirm, never on the creation row), the arrow navigates
    -- to this row alone
    row._nav = BNB.CreateIconButton(row, 16, "right",
        { tip = L["WP_NAV_ROW_TIP"], tipAnchor = "ANCHOR_TOP" })
    row._nav:SetPoint("TOPRIGHT", row, "TOPRIGHT", -2, 0)
    row._del = BNB.CreateIconButton(row, 16, "close",
        { tip = L["WP_REMOVE_TIP"], tipAnchor = "ANCHOR_TOP" })
    row._del:SetPoint("TOPRIGHT", row, "TOPRIGHT", -2, -WP_LINE_H - 1)
    row._del:Hide(); row._nav:Hide()
    return row
end

-- Sub-zone suggestions under an edit box while typing (2+ letters), from the
-- location browser's sub-zone list; a click puts the name in the box and
-- keeps it focused. Returns the list frame (a press on it is not "outside")
local AC_MAX, AC_ROW_H = 6, 18
local function AttachSubzoneAC(eb)
    local ac = BNB.CreateBackdropFrame("Frame", nil, eb)
    BNB.SetBackdrop(ac, 0.08, 0.08, 0.10, 0.97, 0.35, 0.35, 0.38, 1)
    ac:SetPoint("TOPLEFT",  eb, "BOTTOMLEFT",  0, -1)
    ac:SetPoint("TOPRIGHT", eb, "BOTTOMRIGHT", 0, -1)
    ac:SetFrameLevel(eb:GetFrameLevel() + 5)
    ac:Hide()
    local rows = {}
    local function Update()
        local text = eb:GetText() or ""
        local ZP = BNB.ZonePicker
        local m = (#text >= 2 and eb:HasFocus() and ZP and ZP.GetMatches) and ZP.GetMatches(text, "subzone", AC_MAX) or {}
        local n = math.min(#m, AC_MAX)
        if n == 0 then ac:Hide(); return end
        for i = 1, n do
            local r = rows[i]
            if not r then
                r = CreateFrame("Button", nil, ac)
                r:SetHeight(AC_ROW_H)
                r:SetPoint("TOPLEFT",  ac, "TOPLEFT",  2, -2 - (i - 1) * AC_ROW_H)
                r:SetPoint("TOPRIGHT", ac, "TOPRIGHT", -2, -2 - (i - 1) * AC_ROW_H)
                local hl = r:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.10)
                r._fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                r._fs:SetPoint("LEFT", r, "LEFT", 4, 0); r._fs:SetPoint("RIGHT", r, "RIGHT", -4, 0)
                r._fs:SetJustifyH("LEFT"); r._fs:SetWordWrap(false)
                r:SetScript("OnClick", function(self)
                    eb:SetText(self._value); eb:SetCursorPosition(#self._value)
                    ac:Hide(); eb:SetFocus()
                end)
                rows[i] = r
            end
            r._value = m[i].name
            r._fs:SetText(m[i].name)
            r:Show()
        end
        for i = n + 1, #rows do rows[i]:Hide() end
        ac:SetHeight(n * AC_ROW_H + 4)
        ac:Show()
    end
    eb:HookScript("OnTextChanged", function(_, user) if user then Update() end end)
    eb:HookScript("OnEditFocusLost", function()
        C_Timer.After(0.1, function() if not eb:HasFocus() then ac:Hide() end end)
    end)
    return ac
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

    local SelectType, RemoveAt, RefreshList, SitMenu   -- below
    local editIndex   -- the situation loaded into the add row by Edit; Add saves over it

    -- ── The list: one row per situation, always 5 rows tall ──────────────────
    -- Nothing below it moves with the count; past 5 the mouse wheel scrolls
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
        -- The waypoint rows' hover: list art, 18% fill in skin mode (Dukul, 2026-10-08)
        local hi = BNB.CreateListRowArt(row, "hover", { 1, 1, 1, 0.18 })
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
        -- Right-click: Edit / Remove (ALL-282)
        row:SetScript("OnMouseUp", function(self, button)
            if button == "RightButton" and self._index then GameTooltip:Hide(); SitMenu(self) end
        end)
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
            -- The picker has a Zones and an Instances tab: a pick from the
            -- other tab switches the type too, or an instance picked while
            -- the type says Zone would be saved as a zone and never match
            BNB.ZonePicker.Open(valueRow, function(name, kind)
                if (kind == "zone" or kind == "instance") and kind ~= typ.value then
                    typ:Set(kind)
                    SelectType(kind)
                end
                valueEb:SetText(name)
            end, typ.value)
        end
    end)

    -- ── Show as | Trigger / How often | On leaving ───────────────────────────
    -- Label above a dropdown, as everywhere else (Dukul, 2026-10-03;
    -- label-left rows ran past the window's right edge), two per row since
    -- ALL-282 (the room went to the waypoint list); the dropdown cuts a long
    -- choice short
    local dispDiv = Divider(panel)
    dispDiv:SetPoint("TOPLEFT",  useCurrentBtn, "BOTTOMLEFT", 0, -14)
    dispDiv:SetPoint("TOPRIGHT", panel,         "TOPRIGHT",  -padR, 0)

    local OPT_PITCH, OPT_GAP = 44, 8   -- label 12 + 3 + dropdown 24 + gap; between the columns
    -- dispDiv ends padR from the panel edge; the dropdowns end ddR from it
    local optArea = CreateFrame("Frame", nil, panel)
    optArea:SetPoint("TOPLEFT",  dispDiv, "BOTTOMLEFT",  0, 0)
    optArea:SetPoint("TOPRIGHT", dispDiv, "BOTTOMRIGHT", padR - ddR, 0)
    optArea:SetHeight(1)
    -- Places the picker in row n, column col (1 = left, 2 = right) of the
    -- option block, its label above it
    local function OptionRow(n, col, labelKey, c)
        local y = -6 - (n - 1) * OPT_PITCH - 15
        if col == 1 then
            c.frame:SetPoint("TOPLEFT",  optArea, "TOPLEFT", 0, y)
            c.frame:SetPoint("TOPRIGHT", optArea, "TOP", -OPT_GAP / 2, y)
        else
            c.frame:SetPoint("TOPLEFT",  optArea, "TOP", OPT_GAP / 2, y)
            c.frame:SetPoint("TOPRIGHT", optArea, "TOPRIGHT", 0, y)
        end
        local lbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("BOTTOMLEFT",  c.frame, "TOPLEFT",  0, 3)
        lbl:SetPoint("BOTTOMRIGHT", c.frame, "TOPRIGHT", 0, 3)
        lbl:SetJustifyH("LEFT"); lbl:SetWordWrap(false)
        lbl:SetText(L[labelKey])
        lbl:SetTextColor(0.78, 0.78, 0.78)
        return lbl
    end

    local RefreshToastBtn   -- below the Toast... button; the Show as pick calls it
    local disp = NewChoice(panel, DISPLAY_KEYS,
        { L["STICKY_DISP_POPUP"], L["STICKY_DISP_STICKY"], L["STICKY_DISP_BOTH"] },
        function(mode)
            local id = NoteID(); if not id then return end
            if mode == "sticky" or mode == "both" then
                BNB.UpdateNote(id, { contextDisplay = mode })
            else
                BNB.UpdateNote(id, { _clear = { "contextDisplay" } })
            end
            RefreshToastBtn()
            Sync(id)
        end)
    local dispLabel = OptionRow(1, 1, "SIT_ROW_SHOW_AS", disp)

    -- Toast... (ALL-383): the note's own toast style and time on screen, in a
    -- small window (the tab is full). Shares row 1 with Show as
    local TOAST_BTN_W = 66
    disp.frame:SetPoint("TOPRIGHT", optArea, "TOP", -OPT_GAP / 2 - TOAST_BTN_W - 4, -21)
    local toastBtn = BNB.CreateButton(nil, panel, L["SIT_TOAST_BTN"], TOAST_BTN_W, 24)
    toastBtn:SetPoint("TOPLEFT", disp.frame, "TOPRIGHT", 4, 0)
    toastBtn:SetScript("OnClick", function()
        local id = NoteID(); if not id then return end
        BNB.NoteToastWindow.Open(id, ed.host)
    end)
    toastBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["SIT_TOAST_BTN_TIP_TITLE"], 1, 1, 1)
        GameTooltip:AddLine(self:IsEnabled() and L["SIT_TOAST_BTN_TIP"] or L["SIT_TOAST_BTN_OFF_TIP"],
            0.78, 0.78, 0.78, true)
        GameTooltip:Show()
    end)
    toastBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    toastBtn:SetMotionScriptsWhileDisabled(true)
    -- Greyed while the note would show no toast: Show as Sticky alone, or
    -- the Toasts module / situation toasts off
    function RefreshToastBtn()
        local sticky = disp.value == "sticky" and BNB.StickiesEnabled()
        local on = not sticky and BNB.ToastsEnabled() and BNB.ToastSourceOn("situation")
        toastBtn:SetEnabled(on and true or false)
    end
    if ed.host then
        ed.host:HookScript("OnHide", function() BNB.NoteToastWindow.Close(ed.host) end)
    end

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
    local leaveLabel = OptionRow(2, 2, "SIT_ROW_LEAVE", leave)

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
    local trigLabel = OptionRow(1, 2, "SIT_ROW_TRIGGER", trig)
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
    local freqLabel = OptionRow(2, 1, "SIT_ROW_FREQ", freq)
    freq.frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["SIT_ROW_FREQ"], 1, 1, 1)
        GameTooltip:AddLine(L["SIT_FREQ_TIP"], 0.78, 0.78, 0.78, true)
        GameTooltip:Show()
    end)
    freq.frame:HookScript("OnLeave", function() GameTooltip:Hide() end)

    -- ── Waypoints ────────────────────────────────────────────────────────────
    -- note.waypoints = { { mapID, x, y, label, name, on }, ... } (ALL-282,
    -- Core/NoteFields.lua), listed under the spot where the note was made.
    -- Shown with or without a situation: Navigate works either way (Dukul,
    -- 2026-10-05). A green row is placed when the situation matches (TomTom
    -- takes every green row, the game's pin only one), a grey one is kept for
    -- Navigate.
    local wpDiv = Divider(panel)
    wpDiv:SetPoint("TOPLEFT",  dispDiv, "TOPLEFT",  0, -(6 + 2 * OPT_PITCH + 4))
    wpDiv:SetPoint("TOPRIGHT", panel,   "TOPRIGHT", -padR, 0)

    local wpHdr = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    wpHdr:SetPoint("TOPLEFT", wpDiv, "BOTTOMLEFT", 0, -6)
    wpHdr:SetTextColor(1, 0.82, 0, 1)
    wpHdr:SetText(L["STICKY_WP_HEADER"])

    -- "(Addon installed)" / "(Enhanced)" / "(Basic)" / "(Addon required)"
    local wpStatusTag = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    wpStatusTag:SetPoint("LEFT", wpHdr, "RIGHT", 6, 0)

    local wpInfoLbl, wpInfoHit   -- built below; RefreshWPStatusTag shows / hides them
    local function RefreshWPStatusTag()
        if HasWPAddon() then
            wpStatusTag:SetText(HasRetailPin() and L["STICKY_WP_TAG_ENHANCED"] or L["STICKY_WP_TAG_ADDON"])
            wpStatusTag:SetTextColor(0.4, 1, 0.4)
        elseif HasWaypointUI() and HasRetailPin() then
            wpStatusTag:SetText(L["STICKY_WP_TAG_WAYPOINTUI"])
            wpStatusTag:SetTextColor(0.4, 1, 0.4)
        elseif HasRetailPin() then
            wpStatusTag:SetText(L["STICKY_WP_TAG_BASIC"])
            wpStatusTag:SetTextColor(0.85, 0.70, 0.2)
        else
            wpStatusTag:SetText(L["STICKY_WP_TAG_REQUIRED"])
            wpStatusTag:SetTextColor(0.85, 0.30, 0.25)
        end
        -- Both addons installed: nothing left to explain, no "?" (ALL-316)
        local both = (HasWPAddon() and HasWaypointUI()) and true or false
        wpInfoLbl:SetShown(not both)
        -- The hit frame stays: the tag's tooltip lists the addons (ALL-348)
        wpInfoHit._both = both
    end

    -- "?" icon (visual only; the hit frame below takes the click, ALL-316)
    wpInfoLbl = panel:CreateTexture(nil, "OVERLAY")
    wpInfoLbl:SetSize(14, 14)
    wpInfoLbl:SetPoint("LEFT", wpStatusTag, "RIGHT", 4, 0)
    wpInfoLbl:SetTexture("Interface\\AddOns\\BigNoteBox\\Assets\\UI\\ui-mini-question-mark")
    wpInfoLbl:SetAlpha(0.8)

    wpInfoHit = CreateFrame("Button", nil, panel)
    wpInfoHit:SetPoint("LEFT",  wpStatusTag, "LEFT",  -2, 0)
    wpInfoHit:SetPoint("RIGHT", wpInfoLbl,   "RIGHT",  4, 0)
    wpInfoHit:SetHeight(18)
    wpInfoHit:SetScript("OnClick", function(self)
        if not self._both then TogglePopup(ed) end
    end)
    wpInfoHit:SetScript("OnEnter", function(self)
        wpInfoLbl:SetAlpha(1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        -- Which waypoint addons are installed (ALL-348), then the "?" hint
        for _, a in ipairs({ { "WaypointUI", HasWaypointUI() }, { "TomTom", HasWPAddon() } }) do
            if a[2] then
                GameTooltip:AddLine(string.format(L["WP_ADDON_INSTALLED_FMT"], a[1]), 0.4, 1, 0.4)
            else
                GameTooltip:AddLine(string.format(L["WP_ADDON_MISSING_FMT"], a[1]), 0.6, 0.6, 0.6)
            end
        end
        if not self._both then
            GameTooltip:AddLine(L["STICKY_WP_INFO_TIP"], 0.55, 0.85, 1)
        end
        GameTooltip:Show()
    end)
    wpInfoHit:SetScript("OnLeave", function()
        wpInfoLbl:SetAlpha(0.8)
        GameTooltip:Hide()
    end)

    -- Two lines per waypoint (ALL-354): Name | X, Y over Zone | Sub-zone. The
    -- column labels above the list use the same places (PlaceWpCols)
    local WP_LIST_H = WP_ROWS * WP_ROW_H + 4
    local wpList = BNB.CreateBackdropFrame("Frame", nil, panel)
    BNB.SetBackdropDark(wpList)
    wpList:SetPoint("TOPLEFT",  wpDiv, "BOTTOMLEFT",  0, -47)
    wpList:SetPoint("TOPRIGHT", wpDiv, "BOTTOMRIGHT", 0, -47)
    wpList:SetHeight(WP_LIST_H)

    local colHdr = CreateFrame("Frame", nil, panel)
    colHdr:SetPoint("BOTTOMLEFT",  wpList, "TOPLEFT",  2, 2)
    colHdr:SetPoint("BOTTOMRIGHT", wpList, "TOPRIGHT", -7, 2)
    colHdr:SetHeight(2 * WP_HDR_LINE_H)
    local function ColLabel(key)
        local fs = colHdr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetText(L[key])
        fs:SetTextColor(0.60, 0.60, 0.60)
        return fs
    end
    PlaceWpCols(colHdr, ColLabel("WP_COL_NAME"), ColLabel("WP_COL_XY"), ColLabel("WP_COL_ZONE"),
        ColLabel("WP_COL_SUBZONE"), 0, -WP_HDR_LINE_H, WP_HDR_LINE_H)

    local wpEmpty = wpList:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    wpEmpty:SetPoint("LEFT",  wpList, "LEFT",  8, 0)
    wpEmpty:SetPoint("RIGHT", wpList, "RIGHT", -8, 0)
    wpEmpty:SetJustifyH("CENTER")
    wpEmpty:SetTextColor(0.45, 0.45, 0.45)
    wpEmpty:SetText(L["WP_LIST_EMPTY"])

    local wpThumb = wpList:CreateTexture(nil, "OVERLAY")
    wpThumb:SetWidth(3)
    wpThumb:SetColorTexture(0.6, 0.6, 0.6, 0.6)
    wpThumb:Hide()

    local wpOffset  = 0    -- rows scrolled past the top
    local wpEntries = {}   -- what the rows show: { created = true, wp } / { index, wp }
    local wpRows    = {}
    local RefreshWaypoints, WpToggle, WpRemove, WpNavigate, WpMenu, StartEdit, StartZonePick   -- below
    local renameEb, wpEditX, wpEditY, subEb   -- the edit boxes, below

    -- One press on a column toggles the row a moment later; a second press
    -- inside that time edits that column instead (name, X, Y and sub-zone =
    -- the edit boxes, zone = location browser; Dukul 2026-10-06), so a
    -- double-click never toggles first (two presses, as the sticky's inline
    -- edit counts them, ALL-47). Never on the creation row
    local DBL_SECS = 0.35
    local pendingRow, pendingTimer
    local function CancelPending()
        if pendingTimer then pendingTimer:Cancel() end
        pendingRow, pendingTimer = nil, nil
    end
    -- The column under the pointer: the line by y, the column by x (a
    -- FontString is only as wide as its column)
    local function ColumnAt(row)
        local s = row:GetEffectiveScale()
        local x, y = GetCursorPosition()
        x, y = x / s, y / s
        local function In(fs, l) return x >= (l or fs:GetLeft() or 0) and x <= (fs:GetRight() or 0) end
        if y < (row:GetTop() or 0) - 1 - WP_LINE_H then
            if In(row._sub) then return "sub" end
            if In(row._zone, row:GetLeft()) then return "zone" end
        else
            if In(row._xy) then return "xy" end
            if In(row._name, row:GetLeft()) then return "name" end
        end
    end

    for i = 1, WP_ROWS do
        local row = NewWaypointRow(wpList, i)
        local hi = row._hi
        row._del:SetScript("OnClick", function() GameTooltip:Hide(); WpRemove(row._entry) end)
        row._nav:SetScript("OnClick", function() WpNavigate(row._entry) end)
        local function HoverOff()
            if row:IsMouseOver() then return end   -- moved between the row and its buttons
            hi:Hide(); row._del:Hide(); row._nav:Hide()
        end
        for _, b in ipairs({ row._del, row._nav }) do
            b:HookScript("OnEnter", function() hi:Show() end)
            b:HookScript("OnLeave", HoverOff)
        end
        function row._showHover(self)
            hi:Show(); self._nav:Show()
            if self._entry and not self._entry.created then self._del:Show() end
        end
        row:SetScript("OnEnter", function(self)
            self:_showHover()
            local e = self._entry; if not e then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(self._name:GetText() or "", 1, 1, 1)
            local where = BNB.WaypointZone(e.wp)
            if e.wp.subzone then where = where .. " - " .. e.wp.subzone end
            GameTooltip:AddLine(string.format("%s  %.1f, %.1f", where, e.wp.x, e.wp.y), 0.78, 0.78, 0.78)
            if e.created then GameTooltip:AddLine(L["WP_ROW_TIP_CREATED"], 0.60, 0.60, 0.60, true) end
            GameTooltip:AddLine(e.wp.on and L["WP_ROW_TIP_ON"] or L["WP_ROW_TIP_OFF"], 0.40, 0.85, 0.40, true)
            if not HasWPAddon() then GameTooltip:AddLine(L["WP_ROW_TIP_SINGLE"], 0.85, 0.70, 0.2, true) end
            if not e.created then GameTooltip:AddLine(L["WP_ROW_TIP_RENAME"], 0.60, 0.60, 0.60, true) end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide(); HoverOff() end)
        row:SetScript("OnClick", function(self, button)
            local e = self._entry; if not e then return end
            GameTooltip:Hide()
            if button == "RightButton" then CancelPending(); WpMenu(self); return end
            local col = not e.created and ColumnAt(self)
            if not col then CancelPending(); WpToggle(e); return end
            if pendingRow == self then
                CancelPending()
                if col == "xy" then StartEdit(self, wpEditX)
                elseif col == "sub" then StartEdit(self, subEb)
                elseif col == "zone" then StartZonePick(self)
                else StartEdit(self, renameEb) end
                return
            end
            CancelPending()
            pendingRow = self
            pendingTimer = C_Timer.NewTimer(DBL_SECS, function()
                pendingRow, pendingTimer = nil, nil
                WpToggle(e)
            end)
        end)
        row:Hide()
        wpRows[i] = row
    end
    wpList:SetScript("OnMouseWheel", function(_, delta)
        wpOffset = wpOffset - delta
        RefreshWaypoints()
    end)

    -- Edit in place (ALL-329, ALL-354): four boxes laid over the row, Name and
    -- X, Y on the top line, Sub-zone below (with suggestions while typing); a
    -- double-click on one of those columns opens all four with that one
    -- focused. Tab / Shift+Tab move between them; Enter or a press outside the
    -- boxes saves (empty name = the note title again, empty sub-zone = none),
    -- ESC leaves the row as it was
    local function EditBoxOver()
        local eb = CreateFrame("EditBox", nil, wpList, "BackdropTemplate")
        BNB.EnsureBackdrop(eb)
        BNB.SetBackdropDark(eb)
        eb:SetHeight(18)
        eb:SetFontObject("GameFontHighlightSmall")
        eb:SetAutoFocus(false)
        eb:SetTextInsets(3, 3, 0, 0)
        eb:SetFrameLevel(wpList:GetFrameLevel() + 10)
        eb:Hide()
        return eb
    end
    renameEb, wpEditX, wpEditY, subEb = EditBoxOver(), EditBoxOver(), EditBoxOver(), EditBoxOver()
    renameEb:SetMaxLetters(64)
    wpEditX:SetMaxLetters(16)
    wpEditY:SetMaxLetters(16)
    subEb:SetMaxLetters(64)
    local subAC = AttachSubzoneAC(subEb)
    local editBoxes = { renameEb, wpEditX, wpEditY, subEb }
    BNB.TabChain(editBoxes)
    local renaming   -- index into note.waypoints of the row being edited
    local editWatch = CreateFrame("Frame")
    local function EndRename()
        renaming = nil
        editWatch:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        for _, eb in ipairs(editBoxes) do eb:ClearFocus(); eb:Hide() end
    end
    for _, eb in ipairs(editBoxes) do eb:SetScript("OnEscapePressed", EndRename) end
    wpList:HookScript("OnHide", function() if renaming then EndRename() end end)

    -- [Pin Here] [Manual] [Navigate]
    local BTN_W, BTN_H, BTN_GAP = 72, 22, 6
    local wpPinBtn = BNB.CreateButton(nil, panel, L["STICKY_WP_BTN_PIN_HERE"], BTN_W, BTN_H)
    wpPinBtn:SetPoint("TOPLEFT", wpList, "BOTTOMLEFT", 0, -6)
    local wpManualBtn = BNB.CreateButton(nil, panel, L["STICKY_WP_BTN_MANUAL"], BTN_W, BTN_H)
    wpManualBtn:SetPoint("LEFT", wpPinBtn, "RIGHT", BTN_GAP, 0)
    local wpNavBtn = BNB.CreateButton(nil, panel, L["STICKY_WP_BTN_NAVIGATE"], BTN_W, BTN_H)
    wpNavBtn:SetPoint("LEFT", wpManualBtn, "RIGHT", BTN_GAP, 0)

    -- The two checkboxes side by side (room for the two-line waypoint rows,
    -- ALL-354). One line each; a long
    -- translation is cut at the panel edge, the tooltips carry the full text.
    -- Greyed while the note has no situation: both act on the waypoints a
    -- situation places
    local CHK_COL_X = 134   -- the second checkbox: half the 266 px panel
    local function WpCheck(labelKey, tipKey, field)
        local chk = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        BNB.LabelHit(chk)   -- the tooltip and click reach over its label too
        chk:SetSize(24, 24)
        local lbl = chk:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("LEFT", chk, "RIGHT", 2, 0)
        lbl:SetPoint("RIGHT", panel, "RIGHT", -padR, 0)
        lbl:SetJustifyH("LEFT")
        lbl:SetWordWrap(false)
        lbl:SetText(L[labelKey])
        lbl:SetTextColor(0.78, 0.78, 0.78)
        chk._lbl = lbl
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
        chk:SetMotionScriptsWhileDisabled(true)   -- the tooltip says what it does while greyed
        return chk
    end
    -- "Remove on zone leave" (wpClearOnLeave)
    local wpLeaveChk = WpCheck("STICKY_WP_LEAVE_REMOVE_LABEL", "NC_WP_LEAVE_REMOVE_TIP", "wpClearOnLeave")
    wpLeaveChk:SetPoint("TOPLEFT", wpPinBtn, "BOTTOMLEFT", -2, -2)
    -- "Don't track it" (note.wpNoTrack, SUG-10). Only the waypoint a situation
    -- places honours it; Navigate and waypoint links in the text always track.
    local wpNoTrackChk = WpCheck("STICKY_WP_NOTRACK_LABEL", "NC_WP_NOTRACK_TIP", "wpNoTrack")
    wpNoTrackChk:SetPoint("TOPLEFT", wpLeaveChk, "TOPLEFT", CHK_COL_X, 0)
    wpLeaveChk._lbl:SetPoint("RIGHT", wpNoTrackChk, "LEFT", -2, 0)

    -- Manual row (hidden until Manual is clicked) under the checkboxes:
    -- X, Y and an optional name; nothing else lives there, so nothing has to
    -- move (ALL-233)
    local wpManualRow = CreateFrame("Frame", nil, panel)
    wpManualRow:SetHeight(22)
    wpManualRow:SetPoint("TOPLEFT",  wpPinBtn, "BOTTOMLEFT", 0, -(2 + 24 + 4))
    wpManualRow:SetPoint("TOPRIGHT", panel,    "TOPRIGHT",  -padR, 0)
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
        eb:SetSize(46, 20)
        eb:SetFontObject("GameFontNormalSmall")
        eb:SetAutoFocus(false); eb:SetMaxLetters(8)
        eb:SetNumeric(false); eb:SetTextInsets(3, 3, 0, 0)
        return eb
    end
    local wpXEb = CoordBox(nil, L["STICKY_WP_X_LABEL"])
    local wpYEb = CoordBox(wpXEb, L["STICKY_WP_Y_LABEL"])
    local wpSetBtn = BNB.CreateButton(nil, wpManualRow, L["STICKY_WP_BTN_SET"], 38, 20)
    wpSetBtn:SetPoint("RIGHT", wpManualRow, "RIGHT", 0, 0)
    local wpNameEb = CreateFrame("EditBox", nil, wpManualRow, "BackdropTemplate")
    BNB.EnsureBackdrop(wpNameEb)
    BNB.SetBackdropDark(wpNameEb)
    wpNameEb:SetPoint("LEFT",  wpYEb,    "RIGHT", 6, 0)
    wpNameEb:SetPoint("RIGHT", wpSetBtn, "LEFT", -4, 0)
    wpNameEb:SetHeight(20)
    wpNameEb:SetFontObject("GameFontNormalSmall")
    wpNameEb:SetAutoFocus(false); wpNameEb:SetMaxLetters(64)
    wpNameEb:SetTextInsets(3, 3, 0, 0)
    BNB.AddPlaceholder(wpNameEb, L["WP_NAME_PLACEHOLDER"])

    -- Without any waypoint support: the red line in the manual row's place
    -- (Manual is greyed then, so the row never shows)
    local wpNoSupport = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    wpNoSupport:SetPoint("TOPLEFT",  wpManualRow, "TOPLEFT",  0, 0)
    wpNoSupport:SetPoint("TOPRIGHT", wpManualRow, "TOPRIGHT", 0, 0)
    wpNoSupport:SetJustifyH("LEFT"); wpNoSupport:SetWordWrap(true)
    wpNoSupport:SetTextColor(0.65, 0.40, 0.35)
    wpNoSupport:SetText(L["NC_WP_INSTALL_ADDON_FEATURE"])
    wpNoSupport:Hide()

    -- Everything below the add row except the waypoints shows only while the
    -- note has a situation
    local typedOnly = { dispDiv, dispLabel, disp.frame, trigLabel, trig.frame, freqLabel, freq.frame }

    -- ── Refreshers ───────────────────────────────────────────────────────────
    -- The two checkboxes: greyed without a situation or waypoint support
    local function RefreshWpChecks()
        local note = NoteID() and BNB.GetNote(NoteID())
        local on = WPAvailable() and #BNB.NoteSituations(note) > 0 and true or false
        wpLeaveChk:SetChecked(note and note.wpClearOnLeave == true)
        wpNoTrackChk:SetChecked(note and note.wpNoTrack == true)
        for _, chk in ipairs({ wpLeaveChk, wpNoTrackChk }) do
            chk:SetEnabled(on)
            local v = on and 0.78 or 0.40
            chk._lbl:SetTextColor(v, v, v)
        end
    end

    -- The waypoint rows, the scroll bar, the buttons
    RefreshWaypoints = function()
        local note = NoteID() and BNB.GetNote(NoteID())
        if renaming then EndRename() end   -- the rows may move under the box
        wipe(wpEntries)
        local c = BNB.CreationWaypoint(note)
        if c then wpEntries[1] = { created = true, wp = c } end
        for i, wp in ipairs(BNB.NoteWaypoints(note)) do
            if BNB.CleanWaypoint(wp) then wpEntries[#wpEntries + 1] = { index = i, wp = wp } end
        end
        local n = #wpEntries
        wpOffset = math.max(0, math.min(wpOffset, n - WP_ROWS))
        for i, row in ipairs(wpRows) do
            local e = wpEntries[wpOffset + i]
            row._entry = e
            if e then
                row._name:SetText(BNB.WaypointName(note, e.wp))
                row._zone:SetText(BNB.WaypointZone(e.wp))
                row._sub:SetText(e.wp.subzone or "")
                row._xy:SetText(string.format("%.1f, %.1f", e.wp.x, e.wp.y))
                -- Green = placed by the situation, grey = kept for Navigate;
                -- the note title standing in for a name is dimmer
                local r, g, b = 0.55, 0.55, 0.55
                if e.wp.on then r, g, b = 0.40, 0.85, 0.40 end
                row._zone:SetTextColor(r, g, b)
                row._sub:SetTextColor(r, g, b)
                row._xy:SetTextColor(r, g, b)
                -- The rule only between two waypoints
                row._rule:SetShown(wpEntries[wpOffset + i + 1] ~= nil and i < WP_ROWS)
                local dim = e.wp.name and 1 or 0.7
                row._name:SetTextColor(r * dim, g * dim, b * dim)
                row:Show()
                -- A hidden row gets no OnLeave: its buttons must not come back with it
                if row:IsMouseOver() then row:_showHover() else row._del:Hide(); row._nav:Hide() end
            else
                row:Hide()
                row._del:Hide(); row._nav:Hide(); row._rule:Hide()
            end
        end
        if n == 0 then wpEmpty:Show() else wpEmpty:Hide() end
        wpList:EnableMouseWheel(n > WP_ROWS)   -- otherwise the wheel is the window's
        PlaceThumb(wpThumb, wpList, WP_ROWS, n, wpOffset, WP_ROW_H)

        RefreshWPStatusTag()
        local avail = WPAvailable() and note and true or false
        wpPinBtn:SetEnabled(avail); wpManualBtn:SetEnabled(avail)
        wpNavBtn:SetEnabled(avail and n > 0)
        if not avail then wpManualRow:Hide() end
        if WPAvailable() then wpNoSupport:Hide() else wpNoSupport:Show() end
        RefreshWpChecks()
    end

    local function ShowTypedControls(show)
        for _, w in ipairs(typedOnly) do   -- FontStrings among them: Show/Hide, never SetShown
            if show then w:Show() else w:Hide() end
        end
        RefreshLeaveRow(show)
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
                -- Gold while Edit has it in the add row
                if idx == editIndex then row._value:SetTextColor(1, 0.82, 0)
                else row._value:SetTextColor(1, 1, 1) end
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
        PlaceThumb(thumb, list, LIST_ROWS, n, listOffset)
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
        RefreshWpChecks()
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

    -- Edit is over: the add row adds again
    local function EndEdit()
        if not editIndex then return end
        editIndex = nil
        addBtn:SetText(L["SIT_ADD_BTN"])
    end

    RemoveAt = function(idx)
        local id = NoteID(); if not id or not idx then return end
        EndEdit()   -- the rows below move up
        local sits = {}
        for i, s in ipairs(BNB.NoteSituations(BNB.GetNote(id))) do
            if i ~= idx then sits[#sits + 1] = s end
        end
        SaveSituations(id, sits)
    end

    -- Loads situation idx into the add row; Add (now Save) puts it back in
    -- its place (ALL-282, Dukul 2026-10-05)
    local function EditAt(idx)
        local id = NoteID(); if not id then return end
        local s = BNB.NoteSituations(BNB.GetNote(id))[idx]; if not s then return end
        local kind, value = BNB.DecodeContext(s)
        local known = false
        for _, t in ipairs(TYPES) do if t == kind then known = true end end
        if not known then return end
        typ:Set(kind)
        SelectType(kind)
        if KEY_KINDS[kind] then
            if kind ~= "state" then pick:Set(value) end
        else
            valueEb:SetText(value or "")
        end
        editIndex = idx
        addBtn:SetText(L["SIT_SAVE_BTN"])
        addBtn:SetEnabled(true)
        RefreshList()
        if not KEY_KINDS[kind] then valueEb:SetFocus(); valueEb:HighlightText() end
    end

    SitMenu = function(row)
        local idx = row._index; if not idx then return end
        BNB.ContextMenu.Open(row, function(root)
            root:CreateTitle(row._value:GetText() or "")
            root:CreateButton(L["SIT_MENU_EDIT"], function() EditAt(idx) end)
            root:CreateDivider()
            root:CreateButton(L["SIT_MENU_REMOVE"], function() RemoveAt(idx) end, { danger = true })
        end)
    end

    -- Adds the add row's situation at the end of the list, or over the one
    -- Edit loaded; one the note already has (situations match without case)
    -- is left out with a line
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
            if i ~= editIndex and old:lower() == s:lower() then BNB:Print(L["SIT_DUPLICATE"]); return end
            sits[i] = old
        end
        if editIndex and sits[editIndex] then
            sits[editIndex] = s
        else
            sits[#sits + 1] = s
            listOffset = #sits   -- clamped by RefreshList: the new row shows at the bottom
        end
        EndEdit()
        valueEb:SetText("")
        valueEb:ClearFocus()
        HideAC()
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
    -- ESC while editing drops the edit; the row stays as it was
    valueEb:SetScript("OnEscapePressed", function(self)
        if editIndex then
            EndEdit()
            self:SetText("")
            RefreshList()
        end
        self:ClearFocus()
    end)

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
        EndEdit()
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

    -- ── Waypoint handlers ────────────────────────────────────────────────────
    -- Without TomTom the game's pin holds one point: one green row at most
    local function SinglePin() return not HasWPAddon() end

    -- A fresh copy of the note's waypoints to change and save; an unusable
    -- one is false, so the indices still match the rows
    local function CopyWaypoints(note)
        local list = {}
        for i, wp in ipairs(BNB.NoteWaypoints(note)) do list[i] = BNB.CleanWaypoint(wp) or false end
        return list
    end

    -- Saves the list (false = left out) and the creation row's green flag
    local function SaveWaypoints(id, list, createdOn)
        local out = {}
        for _, wp in ipairs(list) do if wp then out[#out + 1] = wp end end
        local fields, clear = {}, {}
        if out[1] then fields.waypoints = out else clear[#clear + 1] = "waypoints" end
        if createdOn then fields.wpCreatedOn = true else clear[#clear + 1] = "wpCreatedOn" end
        if clear[1] then fields._clear = clear end
        BNB.UpdateNote(id, fields)
        RefreshWaypoints()
        Sync(id)
    end

    -- Green <-> grey; turning one green without TomTom greys the others
    WpToggle = function(e)
        local id = NoteID(); local note = id and BNB.GetNote(id)
        if not (note and e) then return end
        local turnOn = not e.wp.on
        local list = CopyWaypoints(note)
        local createdOn = note.wpCreatedOn == true
        if turnOn and SinglePin() then
            for _, wp in ipairs(list) do if wp then wp.on = nil end end
            createdOn = false
        end
        if e.created then
            createdOn = turnOn
        elseif list[e.index] then
            list[e.index].on = turnOn or nil
        end
        SaveWaypoints(id, list, createdOn)
    end

    WpRemove = function(e)
        local id = NoteID(); local note = id and BNB.GetNote(id)
        if not (note and e) or e.created then return end
        local list = CopyWaypoints(note)
        list[e.index] = false
        SaveWaypoints(id, list, note.wpCreatedOn == true)
    end

    -- A coordinate typed in one box: 0-100, a decimal comma counts as a point
    -- ("20,1" = "20.1"); anything else = nil
    local function WpCoord(text)
        local v = tonumber(((text or ""):gsub(",", ".")):match("^%s*(.-)%s*$"))
        if v and v >= 0 and v <= 100 then return v end
    end

    -- Saves the four boxes in one write. Name and sub-zone always; X, Y only
    -- when both read as coordinates. Both numbers pasted into X ("20.1 23.2",
    -- "20,1; 23,2") count too
    local function WpSaveEdit(index, name, xText, yText, subText)
        local id = NoteID(); local note = id and BNB.GetNote(id)
        if not note then return end
        local list = CopyWaypoints(note)
        if not list[index] then return end
        name = (name or ""):match("^%s*(.-)%s*$") or ""
        list[index].name = name ~= "" and name or nil
        local sub = (subText or ""):match("^%s*(.-)%s*$") or ""
        list[index].subzone = sub ~= "" and sub or nil
        local a, b = (xText or ""):match("^%s*([%d%.,]+)[%s;]+([%d%.,]+)%s*$")
        local x, y
        if a then x, y = WpCoord(a), WpCoord(b)
        else      x, y = WpCoord(xText), WpCoord(yText) end
        if x and y then list[index].x, list[index].y = x, y end
        SaveWaypoints(id, list, note.wpCreatedOn == true)
    end

    local function CommitEdit()
        local index = renaming
        if not index then return end
        local name, xt, yt, st = renameEb:GetText(), wpEditX:GetText(), wpEditY:GetText(), subEb:GetText()
        EndRename()
        WpSaveEdit(index, name, xt, yt, st)
    end
    -- A press outside the boxes (and the sub-zone suggestions) saves (Dukul 2026-10-06)
    editWatch:SetScript("OnEvent", function()
        if not renaming then return end
        if not renameEb:IsVisible() then EndRename() return end   -- window gone: nothing to save into
        for _, eb in ipairs(editBoxes) do if eb:IsMouseOver() then return end end
        if subAC:IsShown() and subAC:IsMouseOver() then return end
        CommitEdit()
    end)
    for _, eb in ipairs(editBoxes) do eb:SetScript("OnEnterPressed", CommitEdit) end

    WpNavigate = function(e)
        local note = NoteID() and BNB.GetNote(NoteID())
        if note and e then BNB.NavigateWaypoints(note, { e.wp }) end
    end

    -- Opens the four boxes over the row, focus on `focus` (one of them)
    StartEdit = function(row, focus)
        local e = row._entry
        if not e or e.created then return end
        renaming = e.index
        renameEb:ClearAllPoints()
        renameEb:SetPoint("LEFT",  row._name, "LEFT",  -3, 0)
        renameEb:SetPoint("RIGHT", row._name, "RIGHT",  3, 0)
        renameEb:SetText(e.wp.name or "")
        wpEditX:ClearAllPoints()
        wpEditX:SetPoint("LEFT", row._xy, "LEFT", -3, 0)
        wpEditX:SetWidth(44)
        wpEditX:SetText(string.format("%.1f", e.wp.x))
        wpEditY:ClearAllPoints()
        wpEditY:SetPoint("LEFT",  wpEditX, "RIGHT", 4, 0)
        wpEditY:SetPoint("RIGHT", row,     "RIGHT", 0, 0)   -- over the hover buttons too: room to type
        wpEditY:SetText(string.format("%.1f", e.wp.y))
        subEb:ClearAllPoints()
        subEb:SetPoint("LEFT",  row._sub, "LEFT", -3, 0)
        subEb:SetPoint("RIGHT", row,      "RIGHT", 0, 0)
        subEb:SetText(e.wp.subzone or "")
        for _, eb in ipairs(editBoxes) do eb:Show() end
        focus:SetFocus()
        focus:HighlightText()
        -- From the next frame, so the press that opened it does not count
        C_Timer.After(0, function()
            if renaming then pcall(editWatch.RegisterEvent, editWatch, "GLOBAL_MOUSE_DOWN") end
        end)
    end

    -- Zone: the location browser on its Zones tab, over the waypoint section.
    -- A zone moves the waypoint to that map (X, Y kept, label = the new name);
    -- an instance has no map to move to and changes nothing
    StartZonePick = function(row)
        local e = row._entry
        if not e or e.created then return end
        local index = e.index
        BNB.ZonePicker.Open(wpDiv, function(name, _, mapID)
            local id = NoteID(); local note = id and BNB.GetNote(id)
            if not (note and mapID) then return end
            local list = CopyWaypoints(note)
            if not list[index] then return end
            list[index].mapID, list[index].label = mapID, name
            SaveWaypoints(id, list, note.wpCreatedOn == true)
        end, "zone")
    end

    -- The same choices as the row's click, arrow and X (Dukul, 2026-10-05)
    WpMenu = function(row)
        local e = row._entry; if not e then return end
        local note = BNB.GetNote(NoteID())
        BNB.ContextMenu.Open(row, function(root)
            root:CreateTitle(BNB.WaypointName(note, e.wp))
            root:CreateButton(L["WP_MENU_NAVIGATE"], function() WpNavigate(e) end)
            if not e.created then
                root:CreateButton(L["WP_MENU_RENAME"], function()
                    -- Still the same row (nothing reloaded the list meanwhile)
                    local now = row._entry
                    if now and not now.created and now.index == e.index then StartEdit(row, renameEb) end
                end)
            end
            root:CreateRadio(L["WP_MENU_AUTO"], function() return e.wp.on == true end,
                function() WpToggle(e) end)
            if not e.created then
                root:CreateDivider()
                root:CreateButton(L["WP_MENU_REMOVE"], function() WpRemove(e) end, { danger = true })
            end
        end)
    end

    -- Adds a waypoint at x, y (0-100) on mapID at the end of the list, green
    local function AddWaypoint(mapID, x, y, name, msgKey, subzone)
        local id = NoteID(); local note = id and BNB.GetNote(id)
        if not (note and mapID) then return end
        -- One waypoint per spot: the same map and X, Y to one decimal as a row
        -- or the creation spot is refused (Dukul, 2026-10-07)
        local function Same(wp)
            return wp and wp.mapID == mapID and wp.x and wp.y
               and math.abs(wp.x - x) < 0.05 and math.abs(wp.y - y) < 0.05
        end
        local dup = Same(BNB.CreationWaypoint(note))
        for _, wp in ipairs(BNB.NoteWaypoints(note)) do dup = dup or Same(wp) end
        if dup then
            BNB:Print(string.format(L["NC_WP_DUPLICATE_MSG"], x, y)); return
        end
        local list = CopyWaypoints(note)
        local createdOn = note.wpCreatedOn == true
        if SinglePin() then
            for _, wp in ipairs(list) do if wp then wp.on = nil end end
            createdOn = false
        end
        local zone = BNB.WaypointZone({ mapID = mapID })
        if zone == "" then zone = GetRealZoneText() or GetZoneText() or "" end
        local wp = { mapID = mapID, x = x, y = y, label = zone ~= "" and zone or nil,
                     name = name and name ~= "" and name or nil, on = true, subzone = subzone }
        list[#list + 1] = wp
        wpOffset = #list + 1   -- clamped by RefreshWaypoints: the new row shows at the bottom
        SaveWaypoints(id, list, createdOn)
        BNB:Print(string.format(L[msgKey], BNB.WaypointName(note, wp), x, y))
    end

    local function CommitManualCoords()
        local id   = NoteID(); if not id then return end
        local note = BNB.GetNote(id); if not note then return end
        -- A decimal comma counts as a point ("54,3"), as in the row edit (ALL-329)
        local x = tonumber((wpXEb:GetText():gsub(",", ".")):match("^%s*(.-)%s*$") or "")
        local y2 = tonumber((wpYEb:GetText():gsub(",", ".")):match("^%s*(.-)%s*$") or "")
        if not x or not y2 then
            BNB:Print("|cffff6666Invalid coordinates. Enter numbers like 54.3|r"); return
        end
        x  = math.max(0, math.min(100, x))
        y2 = math.max(0, math.min(100, y2))
        local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        local wps   = BNB.NoteWaypoints(note)
        local last  = wps[#wps] or BNB.CreationWaypoint(note)
        local name  = (wpNameEb:GetRealText() or ""):match("^%s*(.-)%s*$")
        wpManualRow:Hide()
        AddWaypoint(mapID or (last and last.mapID), x, y2, name, "NC_WP_SET_MANUAL_MSG")
    end

    wpManualBtn:SetScript("OnClick", function()
        if wpManualRow:IsShown() then wpManualRow:Hide(); return end
        -- Pre-filled with the last saved waypoint; the name starts empty
        local note = NoteID() and BNB.GetNote(NoteID())
        local wps  = BNB.NoteWaypoints(note)
        local wp   = wps[#wps]
        if wp and wp.x then wpXEb:SetText(string.format("%.1f", wp.x)) end
        if wp and wp.y then wpYEb:SetText(string.format("%.1f", wp.y)) end
        wpNameEb:SetRealText("")
        wpManualRow:Show()
        wpXEb:SetFocus()
    end)
    Tip(wpManualBtn, L["STICKY_WP_MANUAL_TIP"])
    wpSetBtn:SetScript("OnClick", CommitManualCoords)

    -- ALL-317: a press outside the row closes it while nothing was typed (the
    -- coordinates it starts with are pre-filled, not typed). Listens only
    -- while the row shows; the Manual button toggles the row itself.
    local manualTyped = false
    for _, eb in ipairs({ wpXEb, wpYEb, wpNameEb }) do
        eb:HookScript("OnTextChanged", function(_, user) if user then manualTyped = true end end)
    end
    local manualWatch = CreateFrame("Frame")
    manualWatch:SetScript("OnEvent", function()
        if not wpManualRow:IsShown() or manualTyped then return end
        if wpManualRow:IsMouseOver() or wpManualBtn:IsMouseOver() then return end
        wpManualRow:Hide()
    end)
    wpManualRow:HookScript("OnShow", function()
        manualTyped = false
        pcall(manualWatch.RegisterEvent, manualWatch, "GLOBAL_MOUSE_DOWN")
    end)
    wpManualRow:HookScript("OnHide", function() manualWatch:UnregisterEvent("GLOBAL_MOUSE_DOWN") end)
    BNB.TabChain({ wpXEb, wpYEb, wpNameEb })
    wpXEb:SetScript("OnEnterPressed", function() wpYEb:SetFocus() end)
    wpYEb:SetScript("OnEnterPressed", CommitManualCoords)
    wpNameEb:SetScript("OnEnterPressed", CommitManualCoords)
    for _, eb in ipairs({ wpXEb, wpYEb, wpNameEb }) do
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); wpManualRow:Hide() end)
    end

    wpPinBtn:SetScript("OnClick", function()
        local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        if not mapID then BNB:Print("|cffff6666Cannot get map position.|r"); return end
        local pos = C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
        if not pos then BNB:Print("|cffff6666Cannot get map position.|r"); return end
        local px, py = pos:GetXY()
        AddWaypoint(mapID, math.floor(px * 1000 + 0.5) / 10,
            math.floor(py * 1000 + 0.5) / 10, nil, "NC_WP_PINNED_MSG", BNB.CurrentSubzone())
    end)
    Tip(wpPinBtn, L["STICKY_WP_PIN_TIP_TITLE"], L["STICKY_WP_PIN_TIP_BODY"], true)

    -- Every green row (TomTom), the first green one (the game's pin); none
    -- green = the first waypoint, else where the note was made
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
            listOffset, wpOffset = 0, 0
            valueEb:SetText("")
            HideAC()
            DisarmClear()
            wpManualRow:Hide()
        end
        -- The other editor may have changed the list: Edit's row number and a
        -- pending click no longer hold
        EndEdit()
        CancelPending()
        self.noteID = noteID
        local note = noteID and BNB.GetNote(noteID)
        local cd = note and note.contextDisplay
        disp:Set((cd == "sticky" or cd == "both") and cd or "popup")
        local lv = note and note.contextLeave
        leave:Set((lv == "minimize" or lv == "hide") and lv or "keep")
        -- Sticky Notes off (ALL-343): the note shows as a popup and has no
        -- sticky to close, so both pickers are greyed; the saved choice stays
        local stickyOn = BNB.StickiesEnabled()
        for _, c in ipairs({ disp, leave }) do
            c.frame:SetEnabled(stickyOn); c.frame:SetAlpha(stickyOn and 1 or 0.45)
        end
        dispLabel:SetAlpha(stickyOn and 1 or 0.45); leaveLabel:SetAlpha(stickyOn and 1 or 0.45)
        RefreshToastBtn()
        BNB.NoteToastWindow.Rebind(noteID, self.host)
        local tr = note and note.contextTrigger
        trig:Set((tr == "leave" or tr == "both") and tr or "arrive")
        local fq = note and note.contextFreq
        local known = false
        for _, k in ipairs(FREQ_KEYS) do if k == fq then known = true end end
        freq:Set(known and fq or "always")
        RefreshList()
        RefreshWaypoints()
    end

    -- A renamed note renames every row that shows its title (ALL-282; the
    -- placed TomTom waypoints follow through ContextNotes' NoteChanged)
    BNB.RegisterMessage("SituationEditor" .. #_editors, "NoteChanged", function(_, id, fields)
        if id == ed.noteID and type(fields) == "table" and fields.title ~= nil and panel:IsVisible() then
            RefreshWaypoints()
        end
    end)

    -- Start empty: nothing below the add row until the note has a situation
    typ:Set("zone")
    SelectType("zone")
    ShowTypedControls(false)
    RefreshWaypoints()

    -- Situations module off (ALL-375): the tab stays, covered by a line that
    -- says so and a way to the switch; the note's situations are kept
    local off = CreateFrame("Frame", nil, panel)
    off:SetAllPoints(panel)
    off:SetFrameLevel(panel:GetFrameLevel() + 50)
    off:EnableMouse(true)
    off:EnableMouseWheel(true)
    off:SetScript("OnMouseWheel", function() end)
    local offBg = off:CreateTexture(nil, "BACKGROUND")
    offBg:SetAllPoints(); offBg:SetColorTexture(0, 0, 0, 0.85)
    local offTxt = off:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    offTxt:SetPoint("LEFT",  off, "LEFT",  16, 24)
    offTxt:SetPoint("RIGHT", off, "RIGHT", -16, 24)
    offTxt:SetJustifyH("CENTER"); offTxt:SetWordWrap(true)
    offTxt:SetText(L["SIT_MODULE_OFF"])
    local offBtn = BNB.CreateButton(nil, off, L["SIT_MODULE_OFF_BTN"], 160, 24)
    offBtn:SetPoint("TOP", offTxt, "BOTTOM", 0, -12)
    offBtn:SetScript("OnClick", function() BNB.OpenSettingsPage("modules", "situations") end)
    local function SyncOff()
        if BNB.SituationsEnabled() then off:Hide() else off:Show() end
    end
    SyncOff()
    panel:HookScript("OnShow", SyncOff)
    BNB.RegisterMessage("SituationEditorOff" .. #_editors, "SituationsModule", SyncOff)
    return ed
end

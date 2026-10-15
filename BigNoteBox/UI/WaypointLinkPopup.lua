-- BigNoteBox UI/WaypointLinkPopup.lua - the editor toolbar's waypoint link
-- popup (ALL-478)
--
-- Under the toolbar's tb-way button: Name, Zone (suggestions as you type), X
-- and Y, filled with where you stand when it opens (Here fills them again),
-- and Insert. Under that the open note's waypoints and creation spot, one
-- click each; "From another note..." lists another note's instead, picked
-- with the note search (only notes with waypoints). What it inserts is a
-- waypoint link (BNB.NoteLinks.WayLink), through the toolbar's own insert
-- (one undo step, rich View mode switches to Edit). Esc, a click elsewhere
-- or the button again closes it. Seated over Focus mode while that is open.
--
-- Public API:
--   BNB.ToggleWaypointLinkPopup(anchor, insert)   insert(snippet)

local BNB = BigNoteBox
local L   = BNB.L

local W, PAD, EB_H, ROW_H, LBL_W, MAX_ROWS, AC_ROWS = 300, 8, 22, 18, 44, 8, 6

local popup, nameEb, zoneEb, xEb, yEb, status, listHead, emptyFS, otherBtn, rule
local acList, acNav
local acRows, wpRows = {}, {}
local _anchor, _insert, _zoneMapID

local function Close()
    if popup then popup:Hide() end
end

local function Insert(wp)
    local fn = _insert
    Close()
    if fn and BNB.NoteLinks then fn(BNB.NoteLinks.WayLink(wp)) end
end

local function Error(msg)
    status:SetText(msg)
    status:Show()
end

-- 0-100, a decimal comma read as a point
local function Coord(eb)
    local t = (eb:GetText() or ""):gsub(",", "."):match("^%s*(.-)%s*$")
    local v = tonumber(t)
    return (v and v >= 0 and v <= 100) and v or nil
end

-- The map the Zone box names: the one picked or filled in while its name is
-- still there, "#84", else looked up by name
local function ZoneMapID()
    local text = (zoneEb:GetText() or ""):match("^%s*(.-)%s*$")
    if text == "" then return nil end
    if _zoneMapID and BNB.WaypointZone({ mapID = _zoneMapID }) == text then return _zoneMapID end
    local num = tonumber(text:match("^#(%d+)$"))
    if num then return C_Map.GetMapInfo(num) and num or nil end
    local zp = BNB.ZonePicker
    return zp and zp.ZoneMapID and zp.ZoneMapID(text)
end

local function InsertTyped()
    local mapID = ZoneMapID()
    if not mapID then Error(L["WAYLINK_ERR_ZONE"]); return end
    local x, y = Coord(xEb), Coord(yEb)
    if not (x and y) then Error(L["WAYLINK_ERR_XY"]); return end
    local name = nameEb:GetRealText():match("^%s*(.-)%s*$")
    Insert({ mapID = mapID, x = x, y = y, name = name ~= "" and name or nil })
end

local function SetZone(mapID)
    _zoneMapID = mapID
    zoneEb:SetText(mapID and BNB.WaypointZone({ mapID = mapID }) or "")
    zoneEb:SetCursorPosition(0)
end

-- Where you stand; nothing in an instance (the game gives no position)
local function FillHere()
    local mapID, x, y
    pcall(function()
        mapID = C_Map.GetBestMapForUnit("player")
        local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
        if pos then x, y = pos:GetXY() end
    end)
    if not (mapID and x and y) or (x == 0 and y == 0) then
        Error(L["WAYLINK_ERR_HERE"])
        return
    end
    SetZone(mapID)
    xEb:SetText(string.format("%.1f", x * 100))
    yEb:SetText(string.format("%.1f", y * 100))
    status:Hide()
end

-- ── Zone suggestions ─────────────────────────────────────────────────────────

local function AcRow(i)
    local r = acRows[i]
    if r then return r end
    r = CreateFrame("Button", nil, acList)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT",  acList, "TOPLEFT",  2, -2 - (i - 1) * ROW_H)
    r:SetPoint("TOPRIGHT", acList, "TOPRIGHT", -2, -2 - (i - 1) * ROW_H)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.10)
    r._fs = r:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    r._fs:SetPoint("LEFT", r, "LEFT", 4, 0)
    r._fs:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    r._fs:SetJustifyH("LEFT"); r._fs:SetWordWrap(false)
    r:SetScript("OnClick", function(self)
        acList:Hide()
        local zp = BNB.ZonePicker
        zoneEb:SetText(self._name)
        _zoneMapID = zp and zp.ZoneMapID and zp.ZoneMapID(self._name)
        xEb:SetFocus(); xEb:HighlightText()
    end)
    acRows[i] = r
    return r
end

local function RefreshAc()
    local text = zoneEb:GetText() or ""
    local zp = BNB.ZonePicker
    local m = (#text >= 2 and zoneEb:HasFocus() and zp and zp.GetMatches) and zp.GetMatches(text, "zone", AC_ROWS) or {}
    if #m == 0 then acList:Hide(); return end
    for i, e in ipairs(m) do
        local r = AcRow(i)
        r._name = e.name
        local cont = e.continent and e.continent ~= "" and ("  |cff888888" .. e.continent .. "|r") or ""
        r._fs:SetText(e.name .. cont)
        BNB.SetTextWhite(r._fs)
        r:Show()
    end
    for i = #m + 1, #acRows do acRows[i]:Hide() end
    acList:SetHeight(#m * ROW_H + 4)
    acList:Show()
end

-- ── A note's waypoints ───────────────────────────────────────────────────────

local function WpRow(i)
    local r = wpRows[i]
    if r then return r end
    r = CreateFrame("Button", nil, popup)
    r:SetHeight(ROW_H)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.10)
    r._fs = r:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    r._fs:SetPoint("LEFT", r, "LEFT", 4, 0)
    r._fs:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    r._fs:SetJustifyH("LEFT"); r._fs:SetWordWrap(false)
    r:SetScript("OnClick", function(self) if self._wp then Insert(self._wp) end end)
    wpRows[i] = r
    return r
end

-- Lists note id's creation spot and waypoints; lays out the bottom half and
-- sets the popup's height
local function ShowWaypoints(id)
    local note = id and BNB.GetNote(id)
    local entries = {}
    if note then
        local c = BNB.CreationWaypoint(note)
        if c then entries[#entries + 1] = c end
        for _, wp in ipairs(BNB.NoteWaypoints(note)) do entries[#entries + 1] = wp end
    end
    if id == BNB._currentNoteID then
        listHead:SetText(L["WAYLINK_THIS_NOTE"])
    else
        local title = note and note.title ~= "" and note.title or L["UNTITLED"]
        listHead:SetText(string.format(L["WAYLINK_NOTE_FMT"], title))
    end
    local shown = math.min(#entries, MAX_ROWS)
    for i = 1, shown do
        local wp, r = entries[i], WpRow(i)
        local name = BNB.WaypointName(note, wp)
        if wp.created then name = L["WAYLINK_CREATED"] end
        r._fs:SetText(string.format("%s  |cff66d966%s (%.1f %.1f)|r", name, BNB.WaypointZone(wp), wp.x, wp.y))
        BNB.SetTextWhite(r._fs)
        r._wp = { mapID = wp.mapID, x = wp.x, y = wp.y, name = BNB.WaypointName(note, wp) }
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT",  listHead, "BOTTOMLEFT",  -4, -4 - (i - 1) * ROW_H)
        r:SetPoint("TOPRIGHT", listHead, "BOTTOMRIGHT",  0, -4 - (i - 1) * ROW_H)
        r:Show()
    end
    for i = shown + 1, #wpRows do wpRows[i]:Hide() end
    local listH = math.max(shown, 1) * ROW_H
    if shown == 0 then emptyFS:Show() else emptyFS:Hide() end
    otherBtn:ClearAllPoints()
    otherBtn:SetPoint("TOPLEFT", listHead, "BOTTOMLEFT", 0, -4 - listH - 6)
    -- The part down to the rule is fixed (_fixedH), then heading, list, button
    popup:SetHeight(popup._fixedH + 6 + 16 + 4 + listH + 6 + 22 + PAD)
end

local function PickOtherNote()
    local NL = BNB.NoteLinks
    BNB.ToggleNotePicker(otherBtn, {
        onPick      = function(id) ShowWaypoints(id) end,
        filter      = NL and NL.HasWaypoints,
        exclude     = BNB._currentNoteID,
        placeholder = L["WAYLINK_PICK_PH"],
        noneText    = L["WAYLINK_PICK_NONE"],
    })
end

-- ── Build ────────────────────────────────────────────────────────────────────

local function Box(w)
    local bg = BNB.CreateBackdropFrame("Frame", nil, popup)
    BNB.SetBackdropDark(bg)
    bg:SetSize(w, EB_H)
    local e = CreateFrame("EditBox", nil, bg)
    e:SetAllPoints(bg)
    e:SetTextInsets(6, 6, 0, 0)
    e:SetFontObject("BNBFontNormalSmall")
    e:SetAutoFocus(false)
    e:SetMaxLetters(60)
    BNB.SetTextWhite(e)
    e:SetScript("OnEnterPressed", InsertTyped)
    e:SetScript("OnEscapePressed", Close)
    e:HookScript("OnTextChanged", function(_, userInput) if userInput then status:Hide() end end)
    return bg, e
end

local function Label(text, box)
    local fs = popup:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    fs:SetPoint("RIGHT", box, "LEFT", -6, 0)
    fs:SetJustifyH("RIGHT")
    fs:SetText(text)
    BNB.SetTextWhite(fs, 0.8)
    return fs
end

local function Build()
    if popup then return end
    popup = BNB.CreateBackdropFrame("Frame", "BNBWaypointLinkPopup", UIParent)
    BNB.SetBackdrop(popup, 0.08, 0.08, 0.10, 0.97, 0.35, 0.35, 0.38, 1)
    popup:SetWidth(W)
    popup:SetFrameStrata("DIALOG")
    popup:SetToplevel(true)
    popup:SetClampedToScreen(true)
    popup:EnableMouse(true)
    popup:Hide()

    local head = popup:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    head:SetPoint("TOPLEFT", popup, "TOPLEFT", PAD, -PAD)
    head:SetText(L["WAYLINK_TITLE"])
    BNB.SetHeaderColor(head)

    local boxW = W - PAD * 2 - LBL_W - 6
    local nameBg; nameBg, nameEb = Box(boxW)
    nameBg:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -PAD, -(PAD + 22))
    BNB.AddPlaceholder(nameEb, L["WAYLINK_NAME_PH"])
    Label(L["WP_COL_NAME"], nameBg)

    local zoneBg; zoneBg, zoneEb = Box(boxW)
    zoneBg:SetPoint("TOPRIGHT", nameBg, "BOTTOMRIGHT", 0, -4)
    Label(L["WP_COL_ZONE"], zoneBg)

    local xBg; xBg, xEb = Box(56)
    xBg:SetPoint("TOPLEFT", zoneBg, "BOTTOMLEFT", 0, -4)
    Label("X", xBg)
    local yBg; yBg, yEb = Box(56)
    yBg:SetPoint("LEFT", xBg, "RIGHT", 22, 0)
    Label("Y", yBg)
    xEb:SetMaxLetters(6); yEb:SetMaxLetters(6)

    local hereBtn = BNB.CreateButton(nil, popup, L["WAYLINK_HERE"], 70, EB_H)
    hereBtn:SetPoint("TOPRIGHT", zoneBg, "BOTTOMRIGHT", 0, -4)
    hereBtn:SetScript("OnClick", FillHere)

    local insertBtn = BNB.CreateButton(nil, popup, L["NE_INSERT_BTN"], 70, EB_H)
    insertBtn:SetPoint("TOPRIGHT", hereBtn, "BOTTOMRIGHT", 0, -6)
    insertBtn:SetScript("OnClick", InsertTyped)

    status = popup:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    status:SetPoint("LEFT",  insertBtn, "LEFT", -(W - PAD * 2 - 70), 0)
    status:SetPoint("RIGHT", insertBtn, "LEFT", -6, 0)
    status:SetJustifyH("LEFT"); status:SetWordWrap(false)
    status:SetTextColor(1, 0.35, 0.35)
    status:Hide()

    -- Everything down to the Insert row: header, three rows, Insert
    popup._fixedH = PAD + 22 + (EB_H + 4) * 3 + 2 + EB_H + 8

    rule = BNB.CreateNoteRule(popup)
    rule:SetPoint("TOPLEFT",  popup, "TOPLEFT",  PAD,  -popup._fixedH)
    rule:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -PAD, -popup._fixedH)

    listHead = popup:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    listHead:SetPoint("TOPLEFT",  popup, "TOPLEFT",  PAD,  -(popup._fixedH + 6))
    listHead:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -PAD, -(popup._fixedH + 6))
    listHead:SetHeight(16)
    listHead:SetJustifyH("LEFT"); listHead:SetWordWrap(false)
    BNB.SetHeaderColor(listHead)

    emptyFS = popup:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    emptyFS:SetPoint("TOPLEFT", listHead, "BOTTOMLEFT", 0, -4 - (ROW_H - 12) / 2)
    emptyFS:SetTextColor(0.50, 0.50, 0.50)
    emptyFS:SetText(L["WAYLINK_NO_WAYPOINTS"])

    otherBtn = BNB.CreateButton(nil, popup, L["WAYLINK_OTHER_NOTE"], W - PAD * 2, 22)
    otherBtn:SetScript("OnClick", PickOtherNote)

    -- Zone suggestions over the rows below the box
    acList = BNB.CreateBackdropFrame("Frame", nil, popup)
    BNB.SetBackdrop(acList, 0.06, 0.06, 0.08, 0.98, 0.35, 0.35, 0.38, 1)
    acList:SetPoint("TOPLEFT",  zoneBg, "BOTTOMLEFT",  0, -1)
    acList:SetPoint("TOPRIGHT", zoneBg, "BOTTOMRIGHT", 0, -1)
    acList:SetFrameLevel(popup:GetFrameLevel() + 20)
    acList:Hide()

    zoneEb:HookScript("OnTextChanged", function(_, userInput)
        if not userInput then return end
        _zoneMapID = nil
        BNB.Debounce("wayLinkZoneAc", 0.15, RefreshAc)
    end)
    zoneEb:HookScript("OnEditFocusLost", function()
        C_Timer.After(0.2, function() if not acList:IsMouseOver() then acList:Hide() end end)
    end)
    -- Arrow keys over the suggestions (ALL-427): Enter takes a highlighted
    -- one, else inserts; Esc closes an open list before the popup
    acNav = BNB.AttachListKeys(zoneEb, acList, acRows)
    zoneEb:SetScript("OnEnterPressed", function() if not acNav:Take() then InsertTyped() end end)
    zoneEb:SetScript("OnEscapePressed", function() if not acNav:Close() then Close() end end)

    BNB.TabChain({ nameEb, zoneEb, xEb, yEb })

    -- A click anywhere else closes it; not while the note search for "From
    -- another note" is open (its rows are outside this frame)
    popup:SetScript("OnEvent", function(self)
        if self:IsMouseOver() or (_anchor and _anchor:IsMouseOver()) then return end
        if BNB.NotePickerShown and BNB.NotePickerShown() then return end
        Close()
    end)
    popup:SetScript("OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
    popup:SetScript("OnHide", function(self)
        self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        for _, e in ipairs({ nameEb, zoneEb, xEb, yEb }) do e:ClearFocus() end
        acList:Hide()
    end)
end

function BNB.ToggleWaypointLinkPopup(anchor, insert)
    Build()
    if popup:IsShown() then
        local same = anchor == _anchor
        Close()
        if same then return end
    end
    _anchor, _insert = anchor, insert
    if not anchor._bnbWayPopHooked then
        anchor._bnbWayPopHooked = true
        anchor:HookScript("OnHide", Close)   -- the toolbar goes with its window
    end
    nameEb:SetRealText("")
    SetZone(nil); xEb:SetText(""); yEb:SetText("")
    status:Hide()
    FillHere()
    ShowWaypoints(BNB._currentNoteID)
    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    BNB.SeatWindow(popup, "DIALOG")
    popup:Show()
    popup:Raise()
end

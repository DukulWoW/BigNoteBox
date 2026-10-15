-- BigNoteBox Features/UnitNotes.lua
-- Shared pieces of the two features that make a note from a unit: InspectNote
-- (players, from the Inspect frame) and TargetNote (NPCs, keybind and unit
-- menu). The note bodies and the duplicate lookups stay in each feature, since
-- they read different data and different keys (ALL-65.7).
--
-- Public API (BNB.UnitNotes):
--   Dialog(globalName, w, h, title)          small skin-aware dialog, hidden
--   TypeDialog(globalName, title, glowKey)   Normal / Rich; dlg:Open(onPick)
--   WarnDialog(globalName, w, h, rowY, dupeW) "note exists"; dlg:Open(...)
--   OpenNote(noteID)                         main window, note selected
--   FindPlayerNote(name, realm)              existing note for a player
--   UniqueTitle(baseName)                    "Name (Duplicate)" when taken
--   EncounteredPlace(unitName)               place text, /way line (or nil)
--   AddPlainEncountered / AddRichEncountered(lines, place, way)  body lines
--   FormatNumber(n)                          client thousands separator
--------------------------------------------------------------------------------

local BNB = BigNoteBox
local L   = BNB.L

BNB.UnitNotes = BNB.UnitNotes or {}
local UN = BNB.UnitNotes

--------------------------------------------------------------------------------
-- MODULE SWITCH (ALL-343): Player & NPC Notes. Off = the notes stay in the
-- list as ordinary notes: no way to make or update one (Inspect frame button,
-- automatic mode, unit menu, target note key), and none of the live bits
-- (the target's live portrait on a row / sticky / Reference Box tab, the
-- Reference Box Model tab). Saved fields, portraits and tags are kept.
--------------------------------------------------------------------------------
function BNB.UnitNotesEnabled()
    return not BigNoteBoxDB or BigNoteBoxDB.unitNotesEnabled ~= false
end

-- Each feature adds a function that hides its type / "note exists" dialogs
UN._closers = {}
function UN.CloseDialogs()
    for _, fn in ipairs(UN._closers) do fn() end
end

function BNB.ApplyUnitNotesModule(on)
    if UN.ApplyInspectBtn then UN.ApplyInspectBtn(on) end
    if not on and UN.CloseDialogs then UN.CloseDialogs() end
    if BNB.ApplyRefBoxModules then BNB.ApplyRefBoxModules() end   -- Model tab
    if BNB.ApplyUnitFrameBadges then BNB.ApplyUnitFrameBadges() end   -- Target / Focus badge (ALL-389)
    if BNB.RefreshNoteList then BNB.RefreshNoteList() end         -- live portraits
    local SN = BNB.Sticky
    if SN and SN.RefreshNote and SN.IsOpen then
        for id, n in pairs(BNB.NotesDB().notes or {}) do
            if (n.source == "inspect" or n.source == "target") and SN.IsOpen(id) then
                SN.RefreshNote(id)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- DIALOG FRAME
-- The shared window shell (UI/ToolWindow.lua, CMP-02 S5): skin mode decides
-- the chrome once, when the dialog is first built. Returned hidden.
--------------------------------------------------------------------------------
function UN.Dialog(globalName, w, h, title)
    local f = BNB.CreateToolWindow({
        name = globalName, w = w, h = h, title = title, pad = 14,
        toplevel = true, escClose = true,
    })
    f:SetPoint("CENTER")
    return f
end

--------------------------------------------------------------------------------
-- TYPE DIALOG: "Normal" or "Rich"
-- dlg:Open(onPick) shows it; a click hides it, then calls onPick(richMode).
-- onPick is set on every Open, so it sees the caller's current data.
--------------------------------------------------------------------------------
function UN.TypeDialog(globalName, title, glowKey)
    local f = UN.Dialog(globalName, 220, 100, title)

    local function Pick(richMode)
        f:Hide()
        if f._onPick then f._onPick(richMode) end
    end

    local nb = BNB.CreateButton(nil, f, L["SW_MODE_NORMAL"], 85, 28)
    nb:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 14)
    nb:SetScript("OnClick", function() Pick(false) end)

    local rb = BNB.CreateButton(nil, f, L["INS_RICH_BTN"], 85, 28)
    rb:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 14)
    rb:SetScript("OnClick", function() Pick(true) end)

    f:HookScript("OnHide", function(self)
        if BNB.StopWindowGlow then BNB.StopWindowGlow(self, glowKey) end
    end)

    function f:Open(onPick)
        self._onPick = onPick
        self:Show()
        -- Seated ButtonFrameTemplate: the default placement; skin frame: flush
        if BNB.StartWindowGlow then
            BNB.StartWindowGlow(self, glowKey, self._isSkin and { l = 0, t = 0, r = 0, b = 0 } or nil)
        end
    end
    return f
end

--------------------------------------------------------------------------------
-- WARNING DIALOG: "You already have a note for [Name]"
-- Open Note | Create Duplicate | Close in one row, rowY up from the bottom.
-- A feature with more buttons adds them to the returned frame.
-- dlg:Open(name, noteID, onDuplicate) sets the text and wires the buttons.
--------------------------------------------------------------------------------
function UN.WarnDialog(globalName, w, h, rowY, dupeW)
    local f = UN.Dialog(globalName, w, h, L["INS_NOTE_EXISTS"])

    local msg = f:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    msg:SetPoint("TOP",   f, "TOP",   0,   -38)
    msg:SetPoint("LEFT",  f, "LEFT",  16,  0)
    msg:SetPoint("RIGHT", f, "RIGHT", -16, 0)
    msg:SetJustifyH("CENTER"); msg:SetWordWrap(true)
    f._msgLbl = msg

    f._openBtn = BNB.CreateButton(nil, f, L["AO_OPEN_NOTE_BTN"], 90, 26)
    f._openBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, rowY)

    f._dupeBtn = BNB.CreateButton(nil, f, L["INS_WARN_DUPLICATE"], dupeW, 26)
    f._dupeBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, rowY)

    local closeBtn = BNB.CreateButton(nil, f, L["CLOSE"], 70, 26)
    closeBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, rowY)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    function f:Open(name, noteID, onDuplicate)
        self._msgLbl:SetText(string.format(L["INS_WARN_EXISTS_FMT"], name))
        self._openBtn:SetScript("OnClick", function()
            self:Hide()
            UN.OpenNote(noteID)
        end)
        self._dupeBtn:SetScript("OnClick", function()
            self:Hide()
            if onDuplicate then onDuplicate() end
        end)
        self:Show()
    end
    return f
end

--------------------------------------------------------------------------------
-- NOTE HELPERS
--------------------------------------------------------------------------------
function UN.OpenNote(noteID)
    if BNB.OpenMainWindow then BNB.OpenMainWindow() end
    if BNB.SelectNote then
        if BNB.SaveCurrentNote then BNB.SaveCurrentNote() end
        BNB.SelectNote(noteID)
    end
    if BNB.RefreshNoteList then BNB.RefreshNoteList() end
end

-- The unit situation a new player / NPC note gets (ALL-435): always added,
-- on or off by the module's setting (onKey), and with it on but the toast
-- off (toastKey) the note shows nothing ("none"). Writes into fields.
function UN.AddUnitSituation(fields, sit, onKey, toastKey)
    local db = BigNoteBoxDB
    local on = db and db[onKey] == true
    fields.situations = { BNB.SituationState(sit, on) }
    if on and db[toastKey] == false then fields.contextDisplay = "none" end
end

-- An existing note for a player. Returns noteID or nil.
-- Matches the player context (on or off), or an inspect note's
-- inspectName/inspectRealm (the same test as NoteList and ReferenceBox). The
-- context was only saved when inspectNoteAddSituation was on (default off)
-- before ALL-435, so on its own it missed every note made with default
-- settings: no warning, and auto mode made a new "(Duplicate)" note on every
-- inspect.
function UN.FindPlayerNote(playerName, realm)
    local ndb = BNB.NotesDB()
    if not ndb or not ndb.notes or not playerName then return nil end
    local ctx = "player:" .. playerName
    if realm and realm ~= "" then ctx = ctx .. "-" .. realm end
    for id, note in pairs(ndb.notes) do
        if BNB.NoteHasSituation(note, ctx, true) then return id end
        if note.source == "inspect" and note.inspectName == playerName
           and (not note.inspectRealm or note.inspectRealm == "" or note.inspectRealm == realm) then
            return id
        end
    end
    return nil
end

local function TitleTaken(ndb, title)
    for _, note in pairs(ndb.notes) do
        if note.title == title then return true end
    end
    return false
end

-- baseName when free, else "Name (Duplicate)", "Name (Duplicate 2)", ...
function UN.UniqueTitle(baseName)
    local ndb = BNB.NotesDB()
    if not ndb or not ndb.notes then return baseName end
    if not TitleTaken(ndb, baseName) then return baseName end
    for i = 1, 100 do
        local candidate
        if i == 1 then
            candidate = string.format(L["INSPECT_DUP_FMT"], baseName)
        else
            candidate = string.format(L["INSPECT_DUP_N_FMT"], baseName, tostring(i))
        end
        if not TitleTaken(ndb, candidate) then return candidate end
    end
    return string.format(L["INSPECT_DUP_N_FMT"], baseName, tostring(time()))
end

-- Where a unit note is made (ALL-449): the place ("Sub, Zone", "" when the
-- game names none) and a /way line to the player's spot, labelled with the
-- unit's name (nil where the game gives no position: instances). The zone is
-- written by name when that name leads back to the same map, else as #mapID,
-- so a click on the link always finds it.
local function PlaceText(zone, sub)
    zone, sub = zone or "", sub or ""
    return (sub ~= "" and sub ~= zone) and (sub .. ", " .. zone) or zone
end

-- "/way Zone x y Name" for a map and a 0-100 position, nil when there is none
local function WayLine(mapID, x, y, unitName)
    if not (mapID and x and y) or (x == 0 and y == 0) then return nil end
    local way
    pcall(function()
        local info = C_Map.GetMapInfo(mapID)
        local zp = BNB.ZonePicker
        local name = info and info.name
        local where = (name and name ~= "" and zp and zp.ZoneMapID and zp.ZoneMapID(name) == mapID)
                      and name or ("#" .. mapID)
        way = string.format("/way %s %.1f %.1f", where, x, y)
        if unitName and unitName ~= "" then way = way .. " " .. unitName end
    end)
    return way
end

function UN.EncounteredPlace(unitName)
    local place = PlaceText(GetZoneText(), GetSubZoneText())
    local way
    pcall(function()
        local mapID = C_Map.GetBestMapForUnit("player")
        local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
        if not pos then return end
        local x, y = pos:GetXY()
        if not (x and y) then return end
        way = WayLine(mapID, x * 100, y * 100, unitName)
    end)
    return place, way
end

-- A player note's encounters (ALL-474): note.unitMet = { at, place, way }
-- (first met), note.unitSeen = { n, at, place } (how often, and the last
-- time). A note made before them has neither: first met is where and when
-- the note was made, which is what its old "Encountered in" line said, and
-- that counts as the first encounter. Never written back from here.
function UN.NoteEncounters(note)
    local met, seen = note.unitMet, note.unitSeen
    if not met then
        met = {
            at    = note.created or time(),
            place = PlaceText(note.coordZone, note.coordSubzone),
            way   = WayLine(note.coordMapID, note.coordX, note.coordY, note.inspectName),
        }
    end
    if not seen then seen = { n = 1, at = met.at, place = met.place } end
    return { met = met, seen = seen }
end

-- The stored /way line written into a body as a waypoint link (ALL-478,
-- Dukul 2026-10-15); the line itself when it cannot be one
local function WayOut(way)
    local NL = BNB.NoteLinks
    return NL and NL.WayLineLink(way) or way
end

-- The Encountered lines of a body, from EncounteredPlace: plain = a footer
-- line plus the waypoint link; rich = a section, the same link
function UN.AddPlainEncountered(lines, place, way)
    if place ~= "" then lines[#lines + 1] = string.format(L["TGT_LINE_ENCOUNTERED"], place) end
    if way then lines[#lines + 1] = WayOut(way) end
end

function UN.AddRichEncountered(lines, place, way)
    if place == "" and not way then return end
    lines[#lines + 1] = "{h3}" .. L["TGT_HDR_ENCOUNTERED"] .. "{/h3}"
    lines[#lines + 1] = ""
    if place ~= "" then
        lines[#lines + 1] = "{p}{icon:achievement_zone_northrend_01:18}  " .. place .. "{/p}"
    end
    if way then
        lines[#lines + 1] = "{p}{icon:inv_misc_map_01:18}  " .. WayOut(way) .. "{/p}"
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = ""
end

-- A player note's encounter lines (ALL-474), from UN.NoteEncounters: "First
-- met: place, date" and its /way; from the second encounter on "Last seen:
-- place, date" and "Encountered N times"; then "Updated: date", the day BNB
-- last refreshed the player's data (enc.updated, unitAuto.at; a date only,
-- so the text changes at most once a day for it). Plain = lines; rich = a
-- section, the /way as a link.
local function PlaceDate(key, dateKey, place, ts)
    local d = BNB.FmtDate(ts)
    if place and place ~= "" then return string.format(L[key], place, d) end
    return string.format(L[dateKey], d)
end
local function EncTexts(enc)
    local t = { met = PlaceDate("TGT_LINE_FIRST_MET", "TGT_LINE_FIRST_MET_DATE", enc.met.place, enc.met.at) }
    local seen = enc.seen
    if seen and (seen.n or 0) > 1 then
        t.last  = PlaceDate("TGT_LINE_LAST_SEEN", "TGT_LINE_LAST_SEEN_DATE", seen.place, seen.at)
        t.count = string.format(L["TGT_LINE_SEEN_COUNT"], tostring(seen.n))
    end
    if enc.updated then t.updated = string.format(L["TGT_LINE_UPDATED"], BNB.FmtDate(enc.updated)) end
    return t
end

function UN.AddPlainMet(lines, enc)
    local t = EncTexts(enc)
    lines[#lines + 1] = t.met
    if enc.met.way then lines[#lines + 1] = WayOut(enc.met.way) end
    if t.last then lines[#lines + 1] = t.last end
    if t.count then lines[#lines + 1] = t.count end
    if t.updated then lines[#lines + 1] = t.updated end
end

function UN.AddRichMet(lines, enc)
    local t = EncTexts(enc)
    lines[#lines + 1] = "{h3}" .. L["TGT_HDR_ENCOUNTERED"] .. "{/h3}"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "{p}{icon:achievement_zone_northrend_01:18}  " .. t.met .. "{/p}"
    if enc.met.way then
        lines[#lines + 1] = "{p}{icon:inv_misc_map_01:18}  " .. WayOut(enc.met.way) .. "{/p}"
    end
    if t.last then lines[#lines + 1] = "{p}{icon:inv_misc_pocketwatch_01:18}  " .. t.last .. "{/p}" end
    if t.count then lines[#lines + 1] = "{p}{icon:inv_misc_head_human_01:18}  " .. t.count .. "{/p}" end
    if t.updated then lines[#lines + 1] = "{p}{col:888888}" .. t.updated .. "{/col}{/p}" end
    lines[#lines + 1] = ""
    lines[#lines + 1] = ""
end

-- What a player note's generated top is built from (ALL-474), kept on the
-- note as note.unitAuto.data so a target or group update can rebuild it with
-- only the values that changed. The same keys GatherInspectData returns.
local SNAP_KEYS = { "name", "displayTitle", "level", "race", "className", "classHex", "spec",
                    "factionLabel", "guild", "guildRank", "ilvl", "achievePoints", "honorKills" }
local GEAR_KEYS = { "slot", "slotIdx", "id", "name", "quality", "ilvl", "icon", "linkData" }
function UN.PlayerSnapshot(data)
    local s = {}
    for _, k in ipairs(SNAP_KEYS) do s[k] = data[k] end
    s.gear = {}
    for _, g in ipairs(data.gear or {}) do
        local c = {}
        for _, k in ipairs(GEAR_KEYS) do c[k] = g[k] end
        s.gear[#s.gear + 1] = c
    end
    return s
end

-- A short fingerprint of the generated top (ALL-474): text that no longer
-- matches it was edited by hand. djb2, kept under 2^32 so it stays exact.
function UN.Fingerprint(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
    return tostring(h)
end

-- body split at its Notes heading line (head): the top above it, and the
-- rest from the line break before the heading to the end. nil when the
-- heading is not a line of its own any more.
function UN.SplitAtHead(body, head)
    if not (body and head and head ~= "") then return nil end
    local from = 1
    while true do
        local s, e = body:find("\n" .. head, from, true)
        if not s then return nil end
        local after = body:sub(e + 1, e + 1)
        if after == "" or after == "\n" or after == "\r" then
            return body:sub(1, s - 1), body:sub(s)
        end
        from = e + 1
    end
end

-- After a player note's body was written from here (an automatic update or
-- "Update gear and note"): the editor and an open sticky show it at once.
-- The sticky keeps its scroll position and leaves an inline edit alone.
function UN.RefreshNoteViews(id)
    if BNB._currentNoteID == id and BNB.LoadNoteInEditor then BNB.LoadNoteInEditor(id) end
    if BNB.Sticky and BNB.Sticky.RefreshBodyLive then BNB.Sticky.RefreshBodyLive(id) end
end

function UN.FormatNumber(n)
    if not n then return "?" end
    -- The client's own thousands separator (ALL-72)
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(math.floor(n)) end
    local s = tostring(math.floor(n))
    local pos, result = #s, ""
    while pos > 0 do
        local start = math.max(1, pos - 2)
        result = s:sub(start, pos) .. (result ~= "" and "," or "") .. result
        pos = start - 1
    end
    return result
end

-- BigNoteBox Features/NoteLinks.lua - waypoint links and note links in the
-- note text (ALL-478)
--
-- Both are chat-style links stored in the body, so one form works in plain
-- notes (the body EditBox shows, hovers and clicks |H links,
-- Features/DragDrop.lua) and in rich notes (AM.ToHTML turns |H links into
-- <a href>, Features/AdvancedMode.lua):
--   |cff66d966|Hbnbwp:<mapID>:<x>:<y>:<name>|h<Zone (x y) Name>|h|r
--   |cff6cb4ee|Hbnbnote:<id>|h<title>|h|r
-- x / y are 0-100 with one decimal; the name may be empty. A note link finds
-- its note by id, so it survives a rename: the text is rewritten in every
-- note that links to it when the title changes, and turns grey with
-- "(deleted)" while the note is in the Trash or gone (back on restore /
-- Rescue). Typed /way lines are another thing (bnbway, ALL-381 / ALL-477)
-- and stay text (Dukul, 2026-10-15).
-- Text that leaves BNB for chat goes through NL.ToChat (custom link types
-- make the server drop a chat message), an HTML export through NL.ToText;
-- backups, share strings and Direct Send keep the links.
--
-- Public API (BNB.NoteLinks):
--   NL.WayLink(wp)                  link for { mapID, x, y, name }
--   NL.WayLineLink(line)            a /way line as a link (the line if it cannot be)
--   NL.NoteLink(id)                 link to a note
--   NL.HasWaypoints(note)           creation spot or a waypoint
--   NL.OnEnter(owner, link)         tooltip; true when it was one of ours
--   NL.OnClick(link, button)        click;   true when it was one of ours
--   NL.ToChat(text) / NL.ToText(text)

local BNB = BigNoteBox
local L   = BNB.L
local NL  = {}
BNB.NoteLinks = NL

local WAY_COL  = "ff66d966"   -- the green of the rich /way links (AM WayLinks)
local NOTE_COL = "ff6cb4ee"
local GONE_COL = "ff808080"

-- Text inside a link: no escape bar (it would end the link), one line
local function Clean(s)
    if type(s) ~= "string" then return nil end
    s = s:gsub("|", ""):gsub("[\r\n]", " "):match("^%s*(.-)%s*$")
    return s ~= "" and s or nil
end

local function Num(v) return string.format("%.1f", v) end

local function ParseWay(data)
    local mapID, x, y, name = data:match("^bnbwp:(%d+):([%d%.]+):([%d%.]+):?(.*)$")
    mapID, x, y = tonumber(mapID), tonumber(x), tonumber(y)
    if not (mapID and x and y) then return nil end
    return { mapID = mapID, x = x, y = y, name = Clean(name) }
end

-- ── Waypoint links ───────────────────────────────────────────────────────────

-- Label "Zone (x y) Name" (Dukul, 2026-10-15); the zone in this client's
-- language at the time it is written
function NL.WayLink(wp)
    local zone = Clean(BNB.WaypointZone(wp)) or ("#" .. wp.mapID)
    local name = Clean(wp.name)
    if name == zone then name = nil end
    local label = string.format("%s (%s %s)", zone, Num(wp.x), Num(wp.y))
    if name then label = label .. " " .. name end
    return string.format("|c%s|Hbnbwp:%d:%s:%s:%s|h%s|h|r",
        WAY_COL, wp.mapID, Num(wp.x), Num(wp.y), name or "", label)
end

function NL.WayLineLink(line)
    local wp = line and BNB.WayLineWaypoint and BNB.WayLineWaypoint(line)
    if not wp then return line end
    -- WayLineWaypoint names a nameless line after its zone: the label has it
    wp.name = select(5, BNB.ParseWayLine(line))
    return NL.WayLink(wp)
end

-- The /way line for copying: the zone by name when that name leads back to
-- the same map, else #mapID (as UnitNotes' WayLine)
local function WayText(wp)
    local zone = BNB.WaypointZone(wp)
    local zp = BNB.ZonePicker
    local where = (zone ~= "" and zp and zp.ZoneMapID and zp.ZoneMapID(zone) == wp.mapID)
                  and zone or ("#" .. wp.mapID)
    local s = string.format("/way %s %s %s", where, Num(wp.x), Num(wp.y))
    if wp.name then s = s .. " " .. wp.name end
    return s
end

-- The game's own map pin link (Retail, Forever), which other players can
-- click; Classic has none: "Zone (x, y)" (Dukul, 2026-10-15)
local function HasMapPin()
    return MAP_PIN_HYPERLINK ~= nil and C_Map ~= nil and C_Map.GetUserWaypointHyperlink ~= nil
end
local function MapPinLink(wp)
    if HasMapPin() then
        return string.format("|cffffff00|Hworldmap:%d:%d:%d|h[%s]|h|r", wp.mapID,
            math.floor(wp.x * 100 + 0.5), math.floor(wp.y * 100 + 0.5), MAP_PIN_HYPERLINK)
    end
    return string.format("%s (%s, %s)", BNB.WaypointZone(wp), Num(wp.x), Num(wp.y))
end

-- Into the open chat line, else a new one. Never through InsertLink: a
-- focused note body takes those (DragDrop's shift-click hook)
local function IntoChat(text)
    pcall(function()
        local CU = ChatFrameUtil
        local eb = (CU and CU.GetActiveWindow and CU.GetActiveWindow())
                   or (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow())
        if eb then eb:Insert(text); return end
        local open = (CU and CU.OpenChat) or ChatFrame_OpenChat
        if open then open(text) end
    end)
end

function NL.HasWaypoints(note)
    return BNB.CreationWaypoint(note) ~= nil or #BNB.NoteWaypoints(note) > 0
end

-- ── Note links ───────────────────────────────────────────────────────────────

-- The note, and whether it is gone (in the Trash: its trash copy; nil = gone
-- for good)
local function NoteState(id)
    local note = BNB.GetNote(id)
    if note then return note, false end
    local ndb = BNB.NotesDB()
    return ndb and ndb.trash and ndb.trash[id], true
end

local function GoneSuffix() return " " .. L["NOTELINK_DELETED"] end

-- oldText: what the link said, the title of last resort for a note gone for good
local function NoteLabel(id, oldText)
    local note, gone = NoteState(id)
    local title = note and Clean(note.title)
    if not gone then return NOTE_COL, title or L["UNTITLED"] end
    if not title and oldText then
        local sfx = GoneSuffix()
        if oldText:sub(-#sfx) == sfx then oldText = oldText:sub(1, -#sfx - 1) end
        title = Clean(oldText)
    end
    return GONE_COL, (title or L["UNTITLED"]) .. GoneSuffix()
end

function NL.NoteLink(id, oldText)
    local col, label = NoteLabel(id, oldText)
    return string.format("|c%s|Hbnbnote:%s|h%s|h|r", col, id, label)
end

-- A note body with the text of its links to id brought up to date. The note
-- open in the editor is saved first when it has changes, and shown again
-- after (as UN.RefreshNoteViews after an automatic player note update).
local function RewriteLinksIn(nid, id)
    local pat = "|c%x%x%x%x%x%x%x%x|Hbnbnote:" .. (id:gsub("%p", "%%%0")) .. "|h(.-)|h|r"
    local function New(body)
        return (body:gsub(pat, function(text) return NL.NoteLink(id, text) end))
    end
    local note = BNB.GetNote(nid)
    local body = note and note.body
    if type(body) ~= "string" or New(body) == body then return end
    local open = BNB._currentNoteID == nid
    if open and BNB._dirty and BNB.SaveCurrentNoteQuiet then
        BNB.SaveCurrentNoteQuiet()
        body = BNB.GetNote(nid).body or ""
    end
    BNB.UpdateNote(nid, { body = New(body) }, { noTouch = true })
    local UN = BNB.UnitNotes
    if UN and UN.RefreshNoteViews then UN.RefreshNoteViews(nid) end
end

function NL.RefreshLinksTo(id)
    local ndb = BNB.NotesDB()
    if not (ndb and ndb.notes and id) then return end
    local key = "|Hbnbnote:" .. id .. "|h"
    local hits = {}
    for nid, n in pairs(ndb.notes) do
        if nid ~= id and type(n.body) == "string" and n.body:find(key, 1, true) then
            hits[#hits + 1] = nid
        end
    end
    for _, nid in ipairs(hits) do xpcall(RewriteLinksIn, geterrorhandler(), nid, id) end
end

-- After the edit that caused it, once per note: a title typed with autosave
-- on saves many times
local function Schedule(id)
    BNB.Debounce("noteLinks:" .. id, 1, function() NL.RefreshLinksTo(id) end)
end

-- Every save sends the title along: only a real change rewrites anything
local _titles = {}
BNB.RegisterMessage("NoteLinks", "NoteChanged", function(_, id, fields)
    if not (id and fields and fields.title ~= nil) or _titles[id] == fields.title then return end
    _titles[id] = fields.title
    Schedule(id)
end)
BNB.RegisterMessage("NoteLinks", "NoteDeleted", function(_, ids)
    for _, id in ipairs(ids or {}) do Schedule(id) end
end)
BNB.RegisterMessage("NoteLinks", "NoteRestored", function(_, id) if id then Schedule(id) end end)
BNB.RegisterMessage("NoteLinks", "NoteCreated",  function(_, id) if id then Schedule(id) end end)   -- Rescue

-- ── Hover and click ──────────────────────────────────────────────────────────

-- Text without codes, cut to n bytes on a whole UTF-8 character
local function Plain(s)
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[%w_]+:", ""):gsub("|r", "")
         :gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("|A.-|a", "")
    return s
end
local function Cut(s, n)
    if #s <= n then return s end
    while n > 0 and s:byte(n + 1) and s:byte(n + 1) >= 0x80 and s:byte(n + 1) < 0xC0 do n = n - 1 end
    return s:sub(1, n) .. "..."
end

local function Hint(text) GameTooltip:AddLine(text, 0.78, 0.78, 0.78, true) end

-- A note lost without a delete (in the Rescue list, ALL-466); a note deleted
-- for good had its history dropped, so it is never in it
local function Rescuable(id)
    if not (BNB.HistoryRescueList and BNB.OpenRescuePage) then return false end
    for _, e in ipairs(BNB.HistoryRescueList()) do
        if e.id == id and e.kind == "missing" then return true end
    end
    return false
end

local function NotePreview(note)
    local body = note.body or ""
    local AM = BNB.AdvancedMode
    if note.richMode and AM and AM.StripMarkup then body = AM.StripMarkup(body) end
    if BNB.Tokens then body = BNB.Tokens.Fill(body) end   -- ALL-481
    local n = 0
    for line in (Plain(body) .. "\n"):gmatch("([^\n]*)\n") do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" then
            GameTooltip:AddLine(Cut(line, 60), 0.70, 0.70, 0.70)
            n = n + 1
            if n == 3 then break end
        end
    end
end

function NL.OnEnter(owner, link)
    local kind = link and link:match("^(bnb%a+):")
    if kind == "bnbwp" then
        local wp = ParseWay(link)
        if not wp then return true end
        GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
        GameTooltip:AddLine(wp.name or L["WAY_LINK_TIP_TITLE"], 1, 1, 1)
        GameTooltip:AddLine(string.format("%s (%s, %s)", BNB.WaypointZone(wp), Num(wp.x), Num(wp.y)),
            0.40, 0.85, 0.40)
        Hint(L["WAYLINK_TIP_CLICK"])
        Hint(L[HasMapPin() and "WAYLINK_TIP_SHIFT" or "WAYLINK_TIP_SHIFT_TEXT"])
        Hint(L["WAYLINK_TIP_CTRL"])
        Hint(L["WAYLINK_TIP_ALT"])
        GameTooltip:Show()
        return true
    elseif kind == "bnbnote" then
        local note, gone = NoteState(link:sub(9))
        GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
        if gone then
            local id = link:sub(9)
            GameTooltip:AddLine(note and Clean(note.title) or L["UNTITLED"], 0.6, 0.6, 0.6)
            GameTooltip:AddLine(L[note and "NOTELINK_IN_TRASH" or "NOTELINK_GONE"], 1, 0.35, 0.35, true)
            if note then Hint(L["NOTELINK_TIP_RESTORE"])
            elseif Rescuable(id) then Hint(L["NOTELINK_TIP_RESCUE"]) end
        else
            local tc = note.titleColor
            GameTooltip:AddLine(Clean(note.title) or L["UNTITLED"],
                tc and tc.r or 1, tc and tc.g or 1, tc and tc.b or 1)
            NotePreview(note)
            Hint(L["NOTELINK_TIP_CLICK"])
            if BNB.StickiesEnabled() then Hint(L["NOTELINK_TIP_SHIFT"]) end
        end
        GameTooltip:Show()
        return true
    end
    return false
end

-- Left click places the waypoint (tracked, as Navigate), Shift puts the map
-- pin into chat, Ctrl copies a /way line (Dukul, 2026-10-15), Alt shows it on
-- the map (ALL-319). A note link opens the note; Shift as a sticky.
function NL.OnClick(link, button)
    local kind = link and link:match("^(bnb%a+):")
    if kind == "bnbwp" then
        if button ~= "LeftButton" then return true end
        local wp = ParseWay(link)
        if not (wp and C_Map and C_Map.GetMapInfo(wp.mapID)) then
            BNB:Print(string.format(L["WAYLINK_BAD_MAP"], tostring(wp and wp.mapID)))
            return true
        end
        if IsShiftKeyDown() then IntoChat(MapPinLink(wp))
        elseif IsControlKeyDown() then BNB.ShowClipboardHint(WayText(wp), nil, nil, true)
        elseif IsAltKeyDown() then BNB.ShowWaypointOnMap(wp)
        else
            wp.name = wp.name or BNB.WaypointZone(wp)
            BNB.NavigateWaypoints(nil, { wp })
        end
        return true
    elseif kind == "bnbnote" then
        if button ~= "LeftButton" then return true end
        local id = link:sub(9)
        local note, gone = NoteState(id)
        -- Shift+click on a deleted note's link brings it back (Dukul,
        -- 2026-10-15): from the Trash at once (the link turns blue again
        -- through NoteRestored); a note lost without a delete opens the
        -- Rescue list. Deleted for good = nothing left to bring back.
        if gone then
            if IsShiftKeyDown() and note and BNB.RestoreNote then
                local title = Clean(note.title) or L["UNTITLED"]
                BNB.RestoreNote(id)
                BNB:Print(string.format(L["NOTELINK_RESTORED_FMT"], title))
            elseif IsShiftKeyDown() and not note and Rescuable(id) then
                BNB.OpenRescuePage()
            else
                BNB:Print(L[note and "NOTELINK_IN_TRASH" or "NOTELINK_GONE"])
            end
            return true
        end
        local sticky = IsShiftKeyDown() and BNB.StickiesEnabled()
        -- Next frame: the click may come from the box the note is about to replace
        C_Timer.After(0, function()
            if not BNB.GetNote(id) then return end
            local SN, K = BNB.Sticky, BNB._NoteListKit
            if sticky and SN and K then
                if SN.IsOpen(id) then SN.Open(id) else K.NOTE_ACTIONS.sticky(id) end
            else
                BNB.OpenNoteInMain(id)
            end
        end)
        return true
    end
    return false
end

-- ── Text that leaves BNB ─────────────────────────────────────────────────────

local WAY_PAT  = "|c%x%x%x%x%x%x%x%x|H(bnbwp:[^|]*)|h(.-)|h|r"
local NOTE_PAT = "|c%x%x%x%x%x%x%x%x|Hbnbnote:[^|]*|h(.-)|h|r"
local BARE_PAT = "|Hbnb%a+:[^|]*|h(.-)|h"   -- a link whose colour was edited away

-- For chat: a waypoint becomes the game's map pin link, a note link its title
function NL.ToChat(text)
    if not (text and text:find("|Hbnb", 1, true)) then return text end
    text = text:gsub(WAY_PAT, function(data, label)
        local wp = ParseWay(data)
        return wp and MapPinLink(wp) or label
    end)
    return (text:gsub(NOTE_PAT, "%1"):gsub(BARE_PAT, "%1"))
end

-- Outside the game (HTML export): the shown text only
function NL.ToText(text)
    if not (text and text:find("|Hbnb", 1, true)) then return text end
    return (text:gsub(WAY_PAT, "%2"):gsub(NOTE_PAT, "%1"):gsub(BARE_PAT, "%1"))
end

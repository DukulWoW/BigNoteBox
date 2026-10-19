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
-- UI links (bnbui:<key>, ALL-513) open a part of BigNoteBox: the keys and what
-- they open live in Features/UILinks.lua; hover, click and the link menu here.

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
        -- BigChatBox: straight into its own chat line, as the Reference Box
        -- does (through the game's chat line it flashed the Blizzard box and
        -- opened an empty BCB line, Dukul 2026-10-18)
        local B = BigChatBox
        if B and B.frame and B.editBox then
            B.frame:Show()
            B.editBox:SetFocus()
            if B.InsertLinkIntoBCB then B.InsertLinkIntoBCB(text) else B.editBox:Insert(text) end
            return
        end
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

-- A link to a note takes that note's title colour, the default blue when it
-- has none (Dukul, 2026-10-18)
local function TitleCol(note)
    local c = note and note.titleColor
    if type(c) ~= "table" or not c.r then return NOTE_COL end
    local function B(v) return math.max(0, math.min(255, math.floor((tonumber(v) or 1) * 255 + 0.5))) end
    return string.format("ff%02x%02x%02x", B(c.r), B(c.g), B(c.b))
end

-- oldText: what the link said, the title of last resort for a note gone for good
local function NoteLabel(id, oldText)
    local note, gone = NoteState(id)
    local title = note and Clean(note.title)
    if not gone then return TitleCol(note), title or L["UNTITLED"] end
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

-- Every save sends the title along: only a real change of the title or its
-- colour rewrites anything
local _titles = {}
local function ColourTouched(fields)
    if fields.titleColor ~= nil then return true end
    for _, k in ipairs(fields._clear or {}) do
        if k == "titleColor" then return true end
    end
    return false
end
BNB.RegisterMessage("NoteLinks", "NoteChanged", function(_, id, fields)
    if not (id and fields and (fields.title ~= nil or ColourTouched(fields))) then return end
    local note = BNB.GetNote(id)
    local sig = (note and note.title or "") .. "@@" .. TitleCol(note)
    if _titles[id] == sig then return end
    _titles[id] = sig
    Schedule(id)
end)
-- Links written before they took the note's colour (2026-10-18) are brought
-- up to date once a session, a moment after login: only links to notes that
-- have a title colour, and a body is written only when its text changes
BNB.RegisterEvent("PLAYER_LOGIN", function()
    C_Timer.After(5, function()
        local ndb = BNB.NotesDB()
        if not (ndb and ndb.notes) then return end
        local any = false
        for _, n in pairs(ndb.notes) do
            if type(n.body) == "string" and n.body:find("|Hbnbnote:", 1, true) then any = true; break end
        end
        if not any then return end
        for id, n in pairs(ndb.notes) do
            if type(n.titleColor) == "table" then xpcall(NL.RefreshLinksTo, geterrorhandler(), id) end
        end
    end)
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
    elseif kind == "bnbui" then   -- ALL-513
        local UL = BNB.UILinks
        if not UL then return false end
        local key = link:sub(7)
        local ok, why = UL.State(key)
        GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
        GameTooltip:AddLine(UL.Label(key), ok and 1 or 0.6, ok and 0.8 or 0.6, ok and 0.2 or 0.6)
        if ok then Hint(L["UILINK_TIP_CLICK"])
        else GameTooltip:AddLine(why, 1, 0.35, 0.35, true) end
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
    if kind == "bnbui" then   -- ALL-513: open that part of BigNoteBox
        if button == "LeftButton" and BNB.UILinks then BNB.UILinks.Open(link:sub(7)) end
        return true
    elseif kind == "bnbwp" then
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

-- ── Game links and the link menu (rich view and normal notes) ───────────────
-- A click on a game link in a note, rich or normal, acts as in chat: the card,
-- Ctrl = dressing room (SetItemRef, every client); Shift sends it to chat,
-- opening the chat line when none is open (Dukul, 2026-10-18: sending to
-- chat was missing in both). A right-click opens the link menu.

-- The whole link as chat wants it. A normal note's box hands the link as it
-- is written; the rich view only its shown text, so it is rebuilt (an item
-- from the game's own link, else GetFixedLink puts the colour back)
local function FullLink(link, text)
    if text and text:find("|H", 1, true) then return text end
    local name = text or ""
    name = name:match("|h(.-)|h") or name
    name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[%w_]+:", ""):gsub("|r", "")
    local full = "|H" .. link .. "|h" .. name .. "|h"
    if link:match("^item:") then
        local ok, _, il = pcall(C_Item.GetItemInfo, link)
        if ok and type(il) == "string" then return il end
    end
    if GetFixedLink then
        local ok, fixed = pcall(GetFixedLink, full)
        if ok and type(fixed) == "string" then full = fixed end
    end
    return full
end

local function IsWeb(kind) return not kind or kind == "http" or kind == "https" end

-- The icon of an item or spell link, for the link menu's title (Dukul,
-- 2026-10-18); nil for anything else
local function LinkIcon(link)
    local kind, id = link:match("^(%a+):(%d+)")
    id = tonumber(id)
    if not id then return nil end
    local ok, icon
    if kind == "item" and C_Item and C_Item.GetItemIconByID then
        ok, icon = pcall(C_Item.GetItemIconByID, id)
    elseif kind == "spell" and C_Spell and C_Spell.GetSpellTexture then
        ok, icon = pcall(C_Spell.GetSpellTexture, id)
    end
    return ok and icon or nil
end

-- The web link menu's title symbol: the toolbar's link art, gold in the
-- normal look, the skin accent in skin mode. Tinted here, not registered
-- with RegisterSkinAccentTex: the menu row's texture is reused for other icons
local WEB_ICON = "Interface\\AddOns\\BigNoteBox\\Assets\\Toolbar\\tb-rich-link"
local function WebIcon(tex)
    tex:SetTexture(WEB_ICON)
    tex:SetTexCoord(0, 1, 0, 1)
    local r, g, b
    if BigNoteBoxDB and BigNoteBoxDB.skinMode then
        r, g, b = BNB.SkinAccentOf(BNB.GetSkinPreset())
    else
        r, g, b = BNB.ICON_GOLD[1], BNB.ICON_GOLD[2], BNB.ICON_GOLD[3]
    end
    tex:SetVertexColor(r, g, b)
end

-- The note an "Add to Reference Box" goes to: only for the editor's text,
-- its rich view and Focus mode (text and rich preview), which show the
-- current note; nil elsewhere (stickies, chat)
local function EditorNoteOf(owner)
    if not owner then return nil end
    if owner == BNB._editorBody or owner == BNB._focusEditorBody
        or owner == BNB._editorRenderFrame or owner._bnbEditorPreview then
        return BNB._currentNoteID
    end
end

-- A left click on a link that is not one of ours (NL.OnClick said no)
function NL.GameLinkClick(owner, link, text, button)
    if button ~= "LeftButton" or not link then return end
    local kind = link:match("^(%a+):")
    if IsWeb(kind) then
        if BNB.ShowClipboardHint then BNB.ShowClipboardHint(link, nil, nil, true) end
        return
    end
    local full = FullLink(link, text)
    if IsShiftKeyDown() then IntoChat(full); return end
    if SetItemRef then pcall(SetItemRef, link, full, button, owner) end
end

-- Rows that need a game window (map, chat line, item card, dressing room)
-- or the main window / a sticky: in Focus mode they close it first, then act
-- once it has faded (Dukul, 2026-10-18). Our own windows open over Focus
-- mode instead (BNB.SeatWindow), so those rows are not wrapped.
local function OutOfFocus(fn)
    return function()
        if BNB.IsFocusModeOpen and BNB.IsFocusModeOpen() then
            BNB.CloseFocusMode()
            C_Timer.After(0.25, fn)
        else
            fn()
        end
    end
end

-- The right-click menu for a link. owner._bnbLinkMenuT tells a box's own
-- right-click menu (Features/InsertInfo.lua) to stand aside this time.
function NL.LinkMenu(owner, link, text)
    local CM = BNB.ContextMenu
    if not (CM and link) then return end
    if owner then owner._bnbLinkMenuT = GetTime() end
    local kind = link:match("^(%a+):")
    CM.Open(owner, function(root)
        if kind == "bnbui" and BNB.UILinks then   -- ALL-513
            local UL, key = BNB.UILinks, link:sub(7)
            local ok, why = UL.State(key)
            root:CreateTitle(UL.Label(key))
            local opts = { icon = "show", disabled = not ok }
            if not ok then opts.tip, opts.tipSub = UL.Label(key), why end   -- why it is greyed
            root:CreateButton(L["UILINK_MENU_OPEN"], function() UL.Open(key) end, opts)
        elseif kind == "bnbwp" then
            local wp = ParseWay(link)
            if not (wp and C_Map and C_Map.GetMapInfo(wp.mapID)) then
                root:CreateTitle(string.format(L["WAYLINK_BAD_MAP"], tostring(wp and wp.mapID)))
                return
            end
            wp.name = wp.name or BNB.WaypointZone(wp)
            root:CreateTitle(Clean(wp.name) or L["LINK_MENU_WAYPOINT"])
            root:CreateButton(L["LINK_MENU_NAVIGATE"], function() BNB.NavigateWaypoints(nil, { wp }) end,
                { icon = "create-situation" })
            root:CreateButton(L["LINK_MENU_MAP"], OutOfFocus(function() BNB.ShowWaypointOnMap(wp) end), { icon = "map" })
            root:CreateButton(L["LINK_MENU_CHAT"], OutOfFocus(function() IntoChat(MapPinLink(wp)) end), { icon = "send-chat" })
            root:CreateButton(L["LINK_MENU_COPY_WAY"], function()
                BNB.ShowClipboardHint(WayText(wp), nil, nil, true)
            end, { icon = "copy-clipboard" })
        elseif kind == "bnbway" then
            local line = link:sub(8)
            root:CreateTitle(line)
            root:CreateButton(L["LINK_MENU_NAVIGATE"], function() BNB.FollowWayLine(line, false) end,
                { icon = "create-situation" })
            root:CreateButton(L["LINK_MENU_MAP"], OutOfFocus(function() BNB.FollowWayLine(line, true) end), { icon = "map" })
            root:CreateButton(L["LINK_MENU_COPY_WAY"], function()
                BNB.ShowClipboardHint(line, nil, nil, true)
            end, { icon = "copy-clipboard" })
        elseif kind == "bnbnote" then
            local note = NoteState(link:sub(9))
            root:CreateTitle(note and (Clean(note.title) or L["UNTITLED"]) or L["NOTELINK_GONE"])
            root:CreateButton(L["LINK_MENU_OPEN_NOTE"], OutOfFocus(function() NL.OnClick(link, "LeftButton") end),
                { icon = "note", disabled = not note })
            -- The rest act on a live note only, not one in the Trash
            local id = link:sub(9)
            local live = BNB.GetNote(id)
            -- As the note list's menu (Dukul, 2026-10-18)
            if BNB.StickiesEnabled() then
                root:CreateButton(L["NL_CTX_OPEN_STICKY"], OutOfFocus(function()
                    local SN, K = BNB.Sticky, BNB._NoteListKit
                    if not (BNB.GetNote(id) and SN and K) then return end
                    if SN.IsOpen(id) then SN.Open(id) else K.NOTE_ACTIONS.sticky(id) end
                end), { icon = "sticky-note", disabled = not live })
            end
            -- The linked note's text to a chat channel (Send to Chat window;
            -- Dukul, 2026-10-18)
            root:CreateButton(L["LINK_MENU_SHARE_CHAT"], function()
                if BNB.OpenSendToChat then BNB.OpenSendToChat(id) end
            end, { icon = "send-chat", disabled = not live })
            root:CreateButton(L["NL_CTX_SHARE"], function()
                if BNB.OpenShareWindow then BNB.OpenShareWindow(id) end
            end, { icon = "share", disabled = not live })
            root:CreateButton(L["NL_CM_COPY_CLIPBOARD"], function()
                local n = BNB.GetNote(id)
                if not n then return end
                BNB:Print(L["BTN_COPY_NOTE_CLASSIC"])
                BNB.ShowClipboardHint((n.title and n.title ~= "" and (n.title .. "\n") or "") .. (n.body or ""))
            end, { icon = "copy-clipboard", disabled = not live })
            root:CreateButton(L["NL_CTX_COPY_MOVE"], function()
                if BNB.OpenCopyMovePopup then BNB.OpenCopyMovePopup(id, "copy") end
            end, { icon = "copy-move", disabled = not live })
        elseif IsWeb(kind) then
            -- Without https:// and www., so more of the address fits (Dukul, 2026-10-18)
            -- The external link symbol in front, gold / the skin accent (Dukul, 2026-10-18)
            root:CreateTitle((link:gsub("^%a+://", ""):gsub("^[Ww][Ww][Ww]%.", "")),
                { iconSetup = WebIcon })
            root:CreateButton(L["LINK_MENU_CHAT"], OutOfFocus(function() IntoChat(link) end), { icon = "send-chat" })
            root:CreateButton(L["LINK_MENU_COPY"], function()
                BNB.ShowClipboardHint(link, nil, nil, true)
            end, { icon = "copy-clipboard" })
        else
            local full = FullLink(link, text)
            root:CreateTitle(full, { icon = LinkIcon(link) })
            -- Into the Reference Box of the note the editor, its rich view or
            -- Focus mode shows; greyed once it is there (Dukul, 2026-10-18)
            local noteID = EditorNoteOf(owner)
            local has = BNB.RefBoxLinkState and BNB.RefBoxLinkState(noteID, link)
            if has ~= nil then
                local opts = { icon = "reference-box", disabled = has }
                if has then opts.tip = L["LINK_MENU_IN_REFBOX"] end   -- why it is greyed
                root:CreateButton(L["LINK_MENU_ADD_REFBOX"], function()
                    BNB.RefBoxAddLink(noteID, link, full)
                end, opts)
            end
            root:CreateButton(L["LINK_MENU_CHAT"], OutOfFocus(function() IntoChat(full) end), { icon = "send-chat" })
            root:CreateButton(L["LINK_MENU_SHOW"], OutOfFocus(function()
                if SetItemRef then pcall(SetItemRef, link, full, "LeftButton", owner) end
            end), { icon = "show" })
            if kind == "item" and DressUpItemLink then
                root:CreateButton(L["LINK_MENU_TRYON"], OutOfFocus(function() pcall(DressUpItemLink, full) end),
                    { icon = "dressing-room" })
            end
        end
    end)
end

-- ── Text that leaves BNB ─────────────────────────────────────────────────────

local WAY_PAT  = "|c%x%x%x%x%x%x%x%x|H(bnbwp:[^|]*)|h(.-)|h|r"
local NOTE_PAT = "|c%x%x%x%x%x%x%x%x|Hbnbnote:[^|]*|h(.-)|h|r"
local UI_PAT   = "|c%x%x%x%x%x%x%x%x|Hbnbui:[^|]*|h(.-)|h|r"   -- ALL-513: its text
local BARE_PAT = "|Hbnb%a+:[^|]*|h(.-)|h"   -- a link whose colour was edited away

-- For chat: a waypoint becomes the game's map pin link, a note link its title
function NL.ToChat(text)
    if not (text and text:find("|Hbnb", 1, true)) then return text end
    text = text:gsub(WAY_PAT, function(data, label)
        local wp = ParseWay(data)
        return wp and MapPinLink(wp) or label
    end)
    return (text:gsub(NOTE_PAT, "%1"):gsub(UI_PAT, "%1"):gsub(BARE_PAT, "%1"))
end

-- Outside the game (HTML export): the shown text only
function NL.ToText(text)
    if not (text and text:find("|Hbnb", 1, true)) then return text end
    return (text:gsub(WAY_PAT, "%2"):gsub(NOTE_PAT, "%1"):gsub(UI_PAT, "%1"):gsub(BARE_PAT, "%1"))
end

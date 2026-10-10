-- BigNoteBox UI/NoteTooltip.lua - the compact note tooltip (ALL-372 S3, S4)
--
-- One builder for every place that shows a note's details in a tooltip: the
-- note list hover (UI/NoteList.lua) and the Target / Focus frame badge
-- (Features/UnitFrameBadge.lua, ALL-400).
-- Sections, each left out when it has nothing: the tl;dr, the next alarm, the
-- situations, the waypoints. Compact on purpose (Dukul, 2026-10-08: "as
-- compact as possible"): a gold header per section, at most MAX_ITEMS lines
-- under it, every line cut to one line of at most MAX_W pixels.
--
-- BEHAVIOUR (Dukul, 2026-10-10):
--   * The note list hover is switched by BigNoteBoxDB.noteHoverDetails
--     (Settings > Modules > tl;dr) and works with the tl;dr module off (then
--     without the tl;dr).
--   * In the collapsed list the note title comes first (it replaces ALL-428's
--     title-only tooltip, which stays when the details are off); the expanded
--     list already shows the title, so there the tooltip shows only when the
--     note has details.
--   * Alarm and situations only while their module is on; waypoints always
--     (Navigate works with Situations off).
--   * The badge: title in the note's title colour, the details, then the
--     click hint. Always with details: noteHoverDetails is about the list.
--
-- PUBLIC API:
--   BNB.ShowNoteListTooltip(row, noteID, collapsed)
--   BNB.ShowNoteBadgeTooltip(owner, noteID)

local BNB = BigNoteBox
local L   = BNB.L

local MAX_W     = 260   -- px, the widest a line may get
local MAX_ITEMS = 3     -- lines per section, then "+N more"
local INDENT    = "  "

local TXT = { 1, 1, 1 }               -- values
local DIM = { 0.65, 0.65, 0.65 }      -- kind labels, coordinates, "+N more"

-- ── Fitting a line ──────────────────────────────────────────────────────────

local _meas
local function Measure(s)
    if not _meas then
        _meas = UIParent:CreateFontString(nil, "BACKGROUND", "GameTooltipText")
        _meas:SetWordWrap(false)
        _meas:Hide()
    end
    _meas:SetText(s)
    return _meas:GetStringWidth()
end

-- Typed text is shown as typed: a "|" would start an escape
local function Esc(s) return (s:gsub("|", "||")) end

-- s escaped and cut to one line of at most maxW pixels, "..." at the cut.
-- Cut by whole UTF-8 characters, measured, so wide (CJK) text fits too
local function Fit(s, maxW)
    s = s or ""
    if Measure(Esc(s)) <= maxW then return Esc(s) end
    local chars = {}
    for c in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars + 1] = c end
    local lo, hi = 0, #chars
    while lo < hi do
        local mid = math.ceil((lo + hi) / 2)
        if Measure(Esc(table.concat(chars, "", 1, mid)) .. "...") <= maxW then lo = mid else hi = mid - 1 end
    end
    return Esc((table.concat(chars, "", 1, lo):gsub("%s+$", ""))) .. "..."
end

-- ── Collecting the lines ────────────────────────────────────────────────────
-- Each line: { left, leftColour, right, rightColour } (right nil = one line)

-- Section headers take the header colour (skin aware) when drawn
local function Header(out, text) out[#out + 1] = { text, hdr = true } end

local function More(out, n)
    if n > 0 then out[#out + 1] = { INDENT .. string.format(L["NT_MORE_FMT"], n), DIM } end
end

local function TldrLines(out, note)
    local t = BNB.NoteTldr(note)
    if not t then return end
    Header(out, L["SIT_TLDR_LBL"])
    out[#out + 1] = { INDENT .. Fit(t, MAX_W), TXT }
end

local function AlarmLines(out, note, noteID)
    local alarm = note.alarm
    if type(alarm) ~= "table" or not (BNB.AlarmsEnabled and BNB.AlarmsEnabled()) then return end
    local AM = BNB.Alarm
    local t  = AM and AM.GetNextFireTime and AM.GetNextFireTime(noteID)
    Header(out, L["NT_ALARM"])
    if alarm.fired or not t then
        out[#out + 1] = { INDENT .. L["AO_FIRED"], TXT,
                          alarm.time and BNB.Date("%Y-%m-%d %H:%M", alarm.time) or nil, DIM }
        return
    end
    local left = BNB.AlarmOverview and BNB.AlarmOverview.FireTimeLeft
    out[#out + 1] = { INDENT .. BNB.Date("%a %Y-%m-%d %H:%M", t), TXT, left and left(noteID) or nil, TXT }
end

local function SituationLines(out, note)
    if not (BNB.SituationsEnabled and BNB.SituationsEnabled()) then return end
    local sits = BNB.NoteSituations(note)
    if not sits[1] then return end
    Header(out, string.format(L["NT_SITUATIONS_FMT"], #sits))
    for i = 1, math.min(#sits, MAX_ITEMS) do
        local kind, value = BNB.DecodeContext(sits[i])
        local shown = BNB.SituationValueLabel(kind, value) or sits[i]
        local kindLbl = BNB.SituationKindLabel(kind)
        if kind == "state" or not kindLbl then
            -- "Rested": the value says it all
            out[#out + 1] = { INDENT .. Fit(shown, MAX_W), TXT }
        else
            local k = INDENT .. kindLbl
            out[#out + 1] = { k, DIM, Fit(shown, MAX_W - Measure(k) - 16), TXT }
        end
    end
    More(out, #sits - MAX_ITEMS)
end

local function WaypointLines(out, note)
    local list = {}
    local c = BNB.CreationWaypoint(note)
    if c and c.on then list[1] = c end   -- the creation spot only when it is placed
    for _, wp in ipairs(BNB.NoteWaypoints(note)) do list[#list + 1] = wp end
    if not list[1] then return end
    Header(out, string.format(L["NT_WAYPOINTS_FMT"], #list))
    for i = 1, math.min(#list, MAX_ITEMS) do
        local wp = list[i]
        local where = BNB.WaypointZone(wp)
        if wp.subzone then where = where .. " - " .. wp.subzone end
        local xy = string.format("%.1f, %.1f", wp.x, wp.y)
        out[#out + 1] = { INDENT .. Fit(where, MAX_W - Measure(xy) - 16), TXT, xy, DIM }
    end
    More(out, #list - MAX_ITEMS)
end

local function Collect(note, noteID)
    local out = {}
    TldrLines(out, note)
    AlarmLines(out, note, noteID)
    SituationLines(out, note)
    WaypointLines(out, note)
    return out
end

local function Render(tt, lines)
    for _, ln in ipairs(lines) do
        local lc, rc = ln[2], ln[4] or TXT
        if ln.hdr then lc = { BNB.HeaderColor() } end
        if ln[3] then
            tt:AddDoubleLine(ln[1], ln[3], lc[1], lc[2], lc[3], rc[1], rc[2], rc[3])
        else
            tt:AddLine(ln[1], lc[1], lc[2], lc[3])
        end
    end
end

-- The title in the note's own title colour, as the list draws it (Dukul,
-- 2026-10-10), white without one
local function TitleLine(tt, note)
    local title = (note.title and note.title ~= "") and note.title or L["UNTITLED"]
    local tc = note.titleColor
    if type(tc) == "table" and tc.r then tt:AddLine(Esc(title), tc.r, tc.g, tc.b)
    else tt:AddLine(Esc(title), 1, 1, 1) end
end

-- ── Public ──────────────────────────────────────────────────────────────────

-- The note list row's hover. Collapsed: the title, then the details; expanded:
-- the details, nothing when the note has none
function BNB.ShowNoteListTooltip(row, noteID, collapsed)
    local note = noteID and BNB.GetNote(noteID)
    if not note then return end
    local details = not BigNoteBoxDB or BigNoteBoxDB.noteHoverDetails ~= false
    local lines = details and Collect(note, noteID) or {}
    if not collapsed and not lines[1] then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if collapsed then TitleLine(GameTooltip, note) end
    Render(GameTooltip, lines)
    GameTooltip:Show()
end

-- The Target / Focus frame badge's hover (ALL-400): title, details, click hint
function BNB.ShowNoteBadgeTooltip(owner, noteID)
    local note = noteID and BNB.GetNote(noteID)
    if not note then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    TitleLine(GameTooltip, note)
    Render(GameTooltip, Collect(note, noteID))
    GameTooltip:AddLine(L["UNIT_BADGE_TIP"], DIM[1], DIM[2], DIM[3])
    GameTooltip:Show()
end

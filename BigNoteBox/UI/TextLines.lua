--------------------------------------------------------------------------------
-- TextLines.lua -- lines drawn under / through parts of an edit box's text
--
-- Underline and strikethrough in rich notes' Edit mode ({u}...{/u},
-- {s}...{/s}, Dukul 2026-10-25), and the spellchecker's underlines later
-- (ALL-559 stage 1). The text itself is never touched: the lines are textures
-- over the box.
--
-- How (proven in BigNoteBox_Dev/SpellProbe.lua, ALL-559 stage 0):
--   * Measured on the edit box's OWN FontString (EditBox:GetRegions()), so the
--     layout is the box's by definition, font fallbacks (Chinese / Korean) too.
--   * FontString:CalculateScreenAreaFromCharacterSpan(first, last + 1): byte
--     indices, 1-based, end exclusive; a list of { left, bottom, width, height },
--     one per line, relative to the FontString's bottom-left.
--   * Its line step is a little wider than the box draws (12.727 vs 12.668), so
--     placing by its y drifts further down a long note: BNB's old failed
--     "Underline". The line NUMBER comes from the answer, the PLACE from the
--     box's own step ((height - insets) / GetNumLines()).
--   * A span costs more the longer the whole text (~2 ms at 34 KB): work is
--     spread over frames under a time budget, the part in view first.
--------------------------------------------------------------------------------
local BNB = BigNoteBox

local TL = {}
BNB.TextLines = TL

local BUDGET_MS = 4          -- span work per frame
local THICK     = 2          -- line thickness
local _attached = {}         -- every controller, for recoloring
local _n = 0

-- Gold in normal mode, the skin accent in skin mode (Dukul, 2026-10-25)
function TL.LineColor()
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.SkinAccentOf and BNB.GetSkinPreset then
        return BNB.SkinAccentOf(BNB.GetSkinPreset())
    end
    local c = BNB.ICON_GOLD or { 1, 0.86, 0.2 }
    return c[1], c[2], c[3]
end

-- {u}...{/u} and {s}...{/s} in typed markup -> { first, last, kind } (bytes,
-- the text between the tags). A tag left open runs to the end of its line.
local MARKUP = { { "{u}", "{/u}", "u" }, { "{s}", "{/s}", "s" } }
function TL.MarkupRanges(text)
    local out = {}
    for _, m in ipairs(MARKUP) do
        local open, close, kind = m[1], m[2], m[3]
        local pos = 1
        while true do
            local _, oEnd = text:find(open, pos, true)
            if not oEnd then break end
            local cStart, cEnd = text:find(close, oEnd + 1, true)
            local nl = text:find("\n", oEnd + 1, true)
            local last
            if cStart and not (nl and nl < cStart) then
                last, pos = cStart - 1, cEnd + 1
            else
                last = (nl or #text + 1) - 1
                pos = last + 1
            end
            if last >= oEnd + 1 then out[#out + 1] = { oEnd + 1, last, kind } end
        end
    end
    return out
end

-- The text with every {u} {/u} {s} {/s} taken out, and the ranges they
-- marked in the text that is left (same rules as MarkupRanges: an open tag
-- runs to the end of its line). For text shown, not edited: a normal note's
-- sticky read view, Send to Chat, toasts (Dukul, 2026-10-25)
function TL.StripLineTags(text)
    if not text or not text:find("{/?[us]}") then return text or "", {} end
    local out, ranges, open = {}, {}, {}
    local len, pos = 0, 1
    local function closeAt(kind, last)
        local first = open[kind]
        if first and last >= first then ranges[#ranges + 1] = { first, last, kind } end
        open[kind] = nil
    end
    while true do
        local s, e, slash, kind = text:find("{(/?)([us])}", pos)
        local chunk = text:sub(pos, (s or #text + 1) - 1)
        -- A newline in the plain part closes what is still open at it
        local cpos = 1
        while true do
            local nl = chunk:find("\n", cpos, true)
            if not nl then break end
            for k in pairs(open) do closeAt(k, len + nl - 1) end
            cpos = nl + 1
        end
        out[#out + 1] = chunk
        len = len + #chunk
        if not s then break end
        if slash == "/" then closeAt(kind, len) else
            if open[kind] then closeAt(kind, len) end
            open[kind] = len + 1
        end
        pos = e + 1
    end
    for k in pairs(open) do closeAt(k, len) end
    table.sort(ranges, function(a, b) return a[1] < b[1] end)
    return table.concat(out), ranges
end

local function OwnFontString(eb)
    for _, r in ipairs({ eb:GetRegions() }) do
        if r.GetObjectType and r:GetObjectType() == "FontString" and r.CalculateScreenAreaFromCharacterSpan then
            return r
        end
    end
end

local function Rects(fs, first, last)
    local ok, res = pcall(fs.CalculateScreenAreaFromCharacterSpan, fs, first, last + 1)
    if not ok or type(res) ~= "table" then return {} end
    if type(res[1]) == "table" then return res end
    return { res }
end

local function RectParts(r)
    return r.left or r[1], r.bottom or r[2], r.width or r[3], r.height or r[4]
end

-- Attach(eb, sf, getRanges): getRanges(text) returns a list of
-- { first, last, kind } ("u" underline, "s" strikethrough) or nil for none.
-- Returns the controller; ctl:Refresh() asks for a redraw.
function TL.Attach(eb, sf, getRanges)
    if not (eb and sf and getRanges) then return end
    _n = _n + 1
    local key = "TextLines" .. _n
    local ctl = { eb = eb, sf = sf, lines = {}, gen = 0 }
    _attached[#_attached + 1] = ctl

    -- Over the scroll frame, clipped to it; hidden with it (rich View mode)
    local layer = CreateFrame("Frame", nil, sf)
    layer:SetAllPoints(sf)
    layer:SetClipsChildren(true)
    layer:EnableMouse(false)
    ctl.layer = layer

    local lastSig

    local function GetLine(i)
        local t = ctl.lines[i]
        if not t then
            t = layer:CreateTexture(nil, "OVERLAY")
            ctl.lines[i] = t
        end
        return t
    end
    local function HideFrom(i)
        for j = i, #ctl.lines do ctl.lines[j]:Hide() end
    end

    local function Draw()
        ctl.gen = ctl.gen + 1
        local gen = ctl.gen
        if not eb:IsVisible() then lastSig = nil; HideFrom(1); return end
        layer:SetFrameLevel(eb:GetFrameLevel() + 2)
        local text = eb._showingPlaceholder and "" or (eb:GetText() or "")
        local ranges = getRanges(text) or {}
        local fs = OwnFontString(eb)
        if not fs or #ranges == 0 or text == "" then lastSig = nil; HideFrom(1); return end
        -- Nothing changed = nothing to do (BNB sets the same text again at times)
        local path, size, flags = eb:GetFont()
        local parts = { text, tostring(eb:GetWidth()), tostring(eb:GetHeight()), tostring(path),
            tostring(size), tostring(flags), tostring(eb:GetJustifyH()) }
        for _, r in ipairs(ranges) do parts[#parts + 1] = r[1] .. ":" .. r[2] .. r[3] end
        local sig = table.concat(parts, "\1")
        if sig == lastSig then return end
        lastSig = sig

        -- The text top: the first letter's rect top, plus a line per leading newline
        local lead = #(text:match("^\n*") or "")
        local topY
        local rT = Rects(fs, lead + 1, lead + 1)[1]
        if rT then
            local _, b, _, h = RectParts(rT)
            if b and h then topY = b + h + lead * h end
        end
        local nLines = fs.GetNumLines and fs:GetNumLines() or 0
        if not topY or nLines <= 0 then HideFrom(1); return end
        local _, _, insT, insB = eb:GetTextInsets()
        local apiStep = topY / nLines
        local boxStep = (eb:GetHeight() - (insT or 0) - (insB or 0)) / nLines
        if apiStep <= 0 or boxStep <= 0 then HideFrom(1); return end

        -- In view first: the letters under the scroll frame's corners
        local k = sf:GetEffectiveScale() / fs:GetEffectiveScale()
        local vA, vB = 1, #text
        if sf:GetLeft() and sf:GetTop() then
            local okA, a = pcall(fs.FindCharacterIndexAtCoordinate, fs, (sf:GetLeft() + 2) * k, (sf:GetTop() - 2) * k)
            local okB, b = pcall(fs.FindCharacterIndexAtCoordinate, fs, (sf:GetRight() - 2) * k, (sf:GetBottom() + 2) * k)
            if okA and type(a) == "number" then vA = a end
            if okB and type(b) == "number" then vB = b end
        end
        local order = {}
        for _, r in ipairs(ranges) do
            if r[2] >= vA and r[1] <= vB then order[#order + 1] = r end
        end
        for _, r in ipairs(ranges) do
            if not (r[2] >= vA and r[1] <= vB) then order[#order + 1] = r end
        end

        local cr, cg, cb = TL.LineColor()
        local i, n = 1, 0
        local function Step()
            if gen ~= ctl.gen then return end
            local t0 = debugprofilestop()
            while i <= #order and debugprofilestop() - t0 < BUDGET_MS do
                local r = order[i]
                for _, rect in ipairs(Rects(fs, r[1], r[2])) do
                    local l, b, w, h = RectParts(rect)
                    if l and b and w and h and w > 0 then
                        local idx = math.floor((topY - b - h) / apiStep + 0.5)
                        local y
                        if r[3] == "s" then
                            y = -(idx * boxStep + h * 0.5) + THICK / 2   -- through the middle
                        else
                            y = -(idx * boxStep + h) + 2                 -- just under the letters
                        end
                        n = n + 1
                        local t = GetLine(n)
                        t:ClearAllPoints()
                        t:SetPoint("TOPLEFT", fs, "TOPLEFT", l, y)
                        t:SetSize(w, THICK)
                        t:SetColorTexture(cr, cg, cb, 1)
                        t:Show()
                    end
                end
                i = i + 1
            end
            if i <= #order then C_Timer.After(0, Step); return end
            HideFrom(n + 1)
        end
        Step()
    end
    ctl.Draw = Draw

    -- Next frame, never inside the layout pass (FOR-30 rule for SimpleHTML;
    -- kept here too: a span lays the text out)
    function ctl.Refresh() BNB.Debounce(key, 0, Draw) end
    function ctl.Recolor() lastSig = nil; ctl.Refresh() end

    eb:HookScript("OnTextChanged", ctl.Refresh)
    eb:HookScript("OnSizeChanged", ctl.Refresh)
    eb:HookScript("OnShow", ctl.Refresh)
    sf:HookScript("OnSizeChanged", ctl.Refresh)
    sf:HookScript("OnShow", ctl.Refresh)
    -- A font, size or alignment change re-wraps without a text change
    hooksecurefunc(eb, "SetFont", ctl.Refresh)
    hooksecurefunc(eb, "SetFontObject", ctl.Refresh)
    hooksecurefunc(eb, "SetJustifyH", ctl.Refresh)
    return ctl
end

-- Every attached box, after a note's rich / plain switch or the like
function TL.RefreshAll()
    for _, ctl in ipairs(_attached) do ctl.Recolor() end
end

BNB.RegisterMessage("TextLines", "SkinChanged", function() TL.RefreshAll() end)

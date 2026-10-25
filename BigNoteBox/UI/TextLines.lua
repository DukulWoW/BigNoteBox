--------------------------------------------------------------------------------
-- TextLines.lua -- lines drawn under / through parts of an edit box's text
--
-- The spellchecker's lines in the editor (ALL-559), the {u} / {s} lines of a
-- normal note's sticky read view, and (TL.AttachHTML, below) underline and
-- strikethrough in rich notes' View mode and previews. Not in Edit mode: the
-- tags show there (Dukul, 2026-10-25). The text itself is never touched: the
-- lines are textures over the box.
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
local THICK     = 1          -- {u} / {s} line: one screen pixel (Dukul, 2026-10-25: thinner)
local _attached = {}         -- every controller, for recoloring
local _n = 0

-- A spelling mistake ("x") gets a wavy line: Assets/UI/ui-spell-squiggle.tga,
-- white on clear, tiled along the word and tinted (placeholder art, Dukul
-- redraws it: keep it a power-of-two size, SQUIG_W x SQUIG_H)
local SQUIGGLE = "Interface\\AddOns\\BigNoteBox\\Assets\\UI\\ui-spell-squiggle"
local SQUIG_W, SQUIG_H = 8, 4

-- One line texture in its look; a pooled texture may have been either before
local function Paint(t, kind, w, r, g, b)
    if kind == "x" then
        t:SetTexture(SQUIGGLE, "REPEAT", "CLAMP")
        t:SetTexCoord(0, w / SQUIG_W, 0, 1)
        t:SetVertexColor(r, g, b, 1)
        t:SetSize(w, SQUIG_H)
    else
        t:SetTexCoord(0, 1, 0, 1)
        t:SetVertexColor(1, 1, 1, 1)
        t:SetColorTexture(r, g, b, 1)
        -- One real pixel at any UI scale, so a 1 px line never blurs or vanishes
        local px = THICK
        if PixelUtil and PixelUtil.GetNearestPixelSize then
            px = PixelUtil.GetNearestPixelSize(THICK, t:GetEffectiveScale(), THICK)
        end
        t:SetSize(w, px)
    end
end

-- Gold in normal mode, the skin accent in skin mode (Dukul, 2026-10-25)
function TL.LineColor()
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.SkinAccentOf and BNB.GetSkinPreset then
        return BNB.SkinAccentOf(BNB.GetSkinPreset())
    end
    local c = BNB.ICON_GOLD or { 1, 0.86, 0.2 }
    return c[1], c[2], c[3]
end

-- The text with every {u} {/u} {s} {/s} taken out, and the ranges they
-- marked in the text that is left (an open tag runs to the end of its line,
-- as in AM.ToHTML's LineMarkers). For text shown, not edited: a normal note's
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

-- Attach(eb, sf, getRanges, color): getRanges(text) returns a list of
-- { first, last, kind } ("u" underline, "s" strikethrough, "x" a spelling
-- mistake, a wavy line) or nil for none. color (optional) = a
-- function returning r, g, b; TL.LineColor when left out. Several
-- controllers can sit on one box (the {u} lines and the spellchecker).
-- Returns the controller; ctl.Refresh() asks for a redraw.
function TL.Attach(eb, sf, getRanges, color)
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

        local cr, cg, cb = (color or TL.LineColor)()
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
                        Paint(t, r[3], w, cr, cg, cb)
                        t._range, t._lineH = r, boxStep
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

    -- The range whose drawn line is under the mouse pointer, or nil (the
    -- spellchecker's right-click, ALL-559). Read from the lines themselves:
    -- the game's own index-at-point answer drifts down a long note, as its
    -- spans do (see the header), so it missed words lower down
    function ctl.RangeAtPointer()
        if not sf:IsMouseOver() then return nil end
        for i = 1, #ctl.lines do
            local t = ctl.lines[i]
            if t:IsShown() and t._range and t:GetLeft() then
                local sc = t:GetEffectiveScale()
                local cx, cy = GetCursorPosition()
                cx, cy = cx / sc, cy / sc
                -- The letters stand on the line: from its bottom up one text line
                if cx >= t:GetLeft() - 2 and cx <= t:GetRight() + 2
                   and cy >= t:GetBottom() - 1 and cy <= t:GetTop() + (t._lineH or 12) then
                    return t._range
                end
            end
        end
    end

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

--------------------------------------------------------------------------------
-- The View mode: the same lines over a SimpleHTML view (ALL-561 stage 2)
--
-- AM.ToHTML turns {u} / {s} into an invisible link, |Hbnbline:u|h...|h ("s",
-- "us" for both). SimpleHTML draws one FontString per block, the marker stays
-- in its text, and the span function works on it once it is laid out (probe
-- /bnbspell html, 2026-10-25). Byte indices count the escape codes. Each
-- render ends in SetHeight(GetContentHeight()) at every call site, so that
-- and SetWidth are the "drawn again" signal: the old FontStrings may be gone,
-- so work in progress stops at once and starts again next frame (never
-- inside the layout pass, FOR-30). The lines sit on a layer over the frame,
-- placed from the frame's top-left, never anchored to SimpleHTML's own
-- FontStrings (they are freed on the next render).
--------------------------------------------------------------------------------

-- The marked parts of one FontString's text -> { first, last, kinds }.
-- A typed pipe is "||", so "||h" is not the end of a marker
local function MarkedSpans(text)
    local out, pos = {}, 1
    while true do
        local _, e, kinds = text:find("|Hbnbline:(%a+)|h", pos)
        if not e then break end
        local i, close = e + 1, nil
        while true do
            local p = text:find("|", i, true)
            if not p then break end
            local nx = text:sub(p + 1, p + 1)
            if nx == "h" then close = p; break end
            i = p + (nx == "|" and 2 or 1)
        end
        if not close then break end
        if close - 1 >= e + 1 then out[#out + 1] = { e + 1, close - 1, kinds } end
        pos = close + 2
    end
    return out
end
TL._MarkedSpans = MarkedSpans   -- offline tests

function TL.AttachHTML(rf)
    if not rf or rf._bnbLines then return end
    _n = _n + 1
    local key = "TextLines" .. _n
    local ctl = { lines = {}, gen = 0 }
    rf._bnbLines = ctl
    _attached[#_attached + 1] = ctl

    local layer = CreateFrame("Frame", nil, rf)
    layer:SetAllPoints(rf)
    layer:EnableMouse(false)

    local lastSig, retries = nil, 0

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

    -- One FontString's lines; n = lines drawn so far -> new n, and whether
    -- the span function answered (nil = not laid out yet)
    local function PlaceFS(job, n, rl, rt, cr, cg, cb)
        local fs = job.fs
        if fs:GetText() ~= job.text then return n, true end   -- drawn again since
        local fl, ft, fb = fs:GetLeft(), fs:GetTop(), fs:GetBottom()
        if not (fl and ft and fb) then return n, false end
        local fsH = ft - fb
        -- The line grid: the API's from the whole text, the drawn one from
        -- the FontString's height (the same line snap as the Edit mode)
        local all = Rects(fs, 1, #job.text)
        if #all == 0 then return n, false end
        local apiTop, apiBot
        for _, r in ipairs(all) do
            local _, b, _, h = RectParts(r)
            if b and h then
                apiTop = math.max(apiTop or b + h, b + h)
                apiBot = math.min(apiBot or b, b)
            end
        end
        local nL = #all
        local snap = nL > 1 and apiTop and fsH > 0 and apiTop > apiBot
        local apiStep = snap and (apiTop - apiBot) / nL
        local step = snap and fsH / nL
        for _, sp in ipairs(MarkedSpans(job.text)) do
            for _, rect in ipairs(Rects(fs, sp[1], sp[2])) do
                local l, b, w, h = RectParts(rect)
                if l and b and w and h and w > 0 then
                    local yTop   -- the rect's top, down from the FontString's top
                    if snap then
                        yTop = -math.floor((apiTop - b - h) / apiStep + 0.5) * step
                    else
                        yTop = b + h - fsH
                    end
                    for kind in sp[3]:gmatch("[us]") do
                        local y = kind == "s" and (yTop - h * 0.5 + THICK / 2) or (yTop - h + 2)
                        n = n + 1
                        local t = GetLine(n)
                        t:ClearAllPoints()
                        t:SetPoint("TOPLEFT", layer, "TOPLEFT", fl - rl + l, ft - rt + y)
                        Paint(t, kind, w, cr, cg, cb)
                        t:Show()
                    end
                end
            end
        end
        return n, true
    end

    local function Draw()
        ctl.gen = ctl.gen + 1
        local gen = ctl.gen
        if not rf:IsVisible() then lastSig = nil; HideFrom(1); return end
        layer:SetFrameLevel(rf:GetFrameLevel() + 2)
        local rl, rt = rf:GetLeft(), rf:GetTop()
        if not (rl and rt) then return end
        local jobs, parts = {}, { tostring(rf:GetWidth()) }
        for _, r in ipairs({ rf:GetRegions() }) do
            if r.GetObjectType and r:GetObjectType() == "FontString" and r:IsShown()
               and r.CalculateScreenAreaFromCharacterSpan then
                local t = r:GetText()
                if t and t:find("|Hbnbline:", 1, true) then
                    jobs[#jobs + 1] = { fs = r, text = t }
                    -- A font change re-wraps the same text: its size and place too
                    parts[#parts + 1] = t .. "\2" .. tostring(r:GetHeight()) .. "\2" .. tostring((r:GetTop() or 0) - rt)
                end
            end
        end
        if #jobs == 0 then lastSig = nil; HideFrom(1); return end
        local sig = table.concat(parts, "\1")
        if sig == lastSig then return end
        lastSig = sig

        local cr, cg, cb = TL.LineColor()
        local j, n, early = 1, 0, false
        local function Step()
            if gen ~= ctl.gen then return end
            local t0 = debugprofilestop()
            while j <= #jobs and debugprofilestop() - t0 < BUDGET_MS do
                local ok, nn, answered = pcall(PlaceFS, jobs[j], n, rl, rt, cr, cg, cb)
                if ok then
                    n = nn
                    if not answered then early = true end
                end
                j = j + 1
            end
            if j <= #jobs then C_Timer.After(0, Step); return end
            HideFrom(n + 1)
            -- Asked before SimpleHTML had laid the text out: once more, soon
            if early and retries < 3 then
                retries = retries + 1
                lastSig = nil
                BNB.Debounce(key, 0.1, Draw)
            else
                retries = 0
            end
        end
        Step()
    end

    local function Invalidate()
        ctl.gen = ctl.gen + 1   -- steps in progress stop now: their FontStrings may be gone
        retries = 0
        BNB.Debounce(key, 0, Draw)
    end
    function ctl.Refresh() BNB.Debounce(key, 0, Draw) end
    function ctl.Recolor() lastSig = nil; ctl.Refresh() end

    hooksecurefunc(rf, "SetHeight", Invalidate)
    hooksecurefunc(rf, "SetWidth", Invalidate)
    rf:HookScript("OnShow", Invalidate)
    return ctl
end

-- Every attached box, after a note's rich / plain switch or the like
function TL.RefreshAll()
    for _, ctl in ipairs(_attached) do ctl.Recolor() end
end

BNB.RegisterMessage("TextLines", "SkinChanged", function() TL.RefreshAll() end)

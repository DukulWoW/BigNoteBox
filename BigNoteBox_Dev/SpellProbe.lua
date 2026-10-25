-- SpellProbe.lua
-- ALL-559 stage 0 (2026-10-25): can BigNoteBox draw spelling underlines over
-- the note editor without touching the note text? Dev only, never packaged.
--
-- An invisible copy of the editor body text (a "mirror" FontString with the
-- same font, width, insets and alignment) is laid over the edit box. The game
-- is asked where each word sits on the mirror (CalculateScreenAreaFromCharacterSpan)
-- and a box is drawn there. If the boxes sit on the words of the real edit box,
-- underlines work.
--
--   /bnbspell          boxes on / off over the open note's body
--   /bnbspell mirror   show the mirror itself in red (does it wrap like the box?)
--   /bnbspell chars    switch span indices: bytes <-> characters
--   /bnbspell notes    make the three test notes (A, B, 5000 words with typos)
--   /bnbspell check    the real checker, simulated: red underlines on the typos only
--   /bnbspell snap     line snap on / off for the real check (round 8, the drift fix)
--   /bnbspell own      measure on the edit box's own FontString instead of the mirror
--   /bnbspell font     cycle how the mirror gets the edit box's font (see ApplyFont)
--   /bnbspell end      switch the span end: last letter + 1 (default) <-> last letter
--   /bnbspell regions  what EditBox:GetRegions() hands back
--   /bnbspell html     the rich View mode (SimpleHTML): its FontStrings, and a link-marker test
--   /bnbspell bench    timings: 5000-word text, edit distance
--   Hold Alt over the body: chat shows the letter under the mouse
--   (FindCharacterIndexAtCoordinate), throttled.

local MAX_BOXES = 600
local P = "|cff66bb6a[spell]|r "

local on, showMirror, charMode = false, false, false
local mirror, layer, eb, sf
local boxes = {}
local pending = false
local shapeShown = false
local lastAlt = 0

local function Say(...) print(P .. string.format(...)) end

local function Body()
    local B = BigNoteBox
    return B and B._editorBody, B and B._editorBodyScroll
end

-- Byte position -> character position (1-based) in a UTF-8 string
local function CharIndex(text, bytePos)
    local n = 0
    for i = 1, bytePos do
        local c = text:byte(i)
        if not c then break end
        if c < 128 or c >= 192 then n = n + 1 end
    end
    return n
end

-- Words: runs of ASCII letters / apostrophes or any UTF-8 bytes; links,
-- textures, colour codes and {markup} are blanked first so their letters
-- are never taken as words (byte offsets stay the same).
local function Words(text)
    local function blank(s) return string.rep(" ", #s) end
    local masked = text:gsub("|H.-|h.-|h", blank):gsub("|T.-|t", blank)
        :gsub("|A.-|a", blank):gsub("|c%x%x%x%x%x%x%x%x", blank):gsub("|r", blank)
        :gsub("{[^}]*}", blank)
    local out = {}
    local i, n = 1, #masked
    while i <= n do
        local s, e = masked:find("[%a\128-\255][%a\128-\255']*", i)
        if not s then break end
        out[#out + 1] = { first = s, last = e }
        i = e + 1
    end
    return out
end

local function ReadRect(r)
    if type(r) ~= "table" then return nil end
    local l = r.left or r.x or r[1]
    local b = r.bottom or r.y or r[2]
    local w = r.width or r.w or r[3]
    local h = r.height or r.h or r[4]
    if l and b and w and h then return l, b, w, h end
end

local function DumpShape(res, ...)
    local parts = { "return type: " .. type(res) }
    if type(res) == "table" then
        parts[#parts + 1] = "#=" .. #res
        local first = res[1] or res
        if type(first) == "table" then
            local keys = {}
            for k, v in pairs(first) do keys[#keys + 1] = tostring(k) .. "=" .. tostring(v) end
            parts[#parts + 1] = "first: {" .. table.concat(keys, ", ") .. "}"
        end
    else
        parts[#parts + 1] = "values: " .. table.concat({ tostring(res), tostring((...)), tostring(select(2, ...)), tostring(select(3, ...)) }, ", ")
    end
    Say("%s", table.concat(parts, "  "))
end

-- Round 3 (2026-10-25): with Chinese / Korean in the note the edit box drew the
-- WHOLE text in another font (wide Cyrillic, boxes for accents) while the
-- mirror kept the SetFont path, so it wrapped differently and the boxes
-- drifted. `/bnbspell font` cycles how the mirror gets its font:
local fontModes = {
    "path",         -- SetFont(eb:GetFont()), round 1-2
    "object",       -- SetFontObject(eb:GetFontObject()) only
    "object+path",  -- the object first (its alphabet fallbacks), then SetFont
    "editbox",      -- SetFontObject(eb): the edit box itself as the font
}
local fontMode = 1
local fontSaid

local function ApplyFont()
    local path, size, flags = eb:GetFont()
    local obj = eb.GetFontObject and eb:GetFontObject()
    local mode = fontModes[fontMode]
    local ok, err = true, nil
    if mode == "path" then
        if path then mirror:SetFont(path, size, flags or "") end
    elseif mode == "object" then
        ok, err = pcall(mirror.SetFontObject, mirror, obj)
    elseif mode == "object+path" then
        ok, err = pcall(mirror.SetFontObject, mirror, obj)
        if path then mirror:SetFont(path, size, flags or "") end
    else
        ok, err = pcall(mirror.SetFontObject, mirror, eb)
    end
    if fontSaid ~= fontMode then
        fontSaid = fontMode
        local mp, ms = mirror:GetFont()
        Say("font mode '%s'%s: edit box %s %s (object %s), mirror %s %s", mode,
            ok and "" or (" FAILED: " .. tostring(err)), tostring(path), tostring(size),
            obj and obj.GetName and tostring(obj:GetName()) or tostring(obj), tostring(mp), tostring(ms))
    end
end

local function CopyLook()
    ApplyFont()
    local l, r, t = eb:GetTextInsets()
    l, r, t = l or 0, r or 0, t or 0
    mirror:ClearAllPoints()
    mirror:SetPoint("TOPLEFT", eb, "TOPLEFT", l, -t)
    mirror:SetWidth(math.max(1, eb:GetWidth() - l - r))
    pcall(function() mirror:SetJustifyH(eb:GetJustifyH() or "LEFT") end)
    mirror:SetJustifyV("TOP")
    mirror:SetWordWrap(true)
    pcall(function() mirror:SetNonSpaceWrap(true) end)
    pcall(function() if eb.GetSpacing then mirror:SetSpacing(eb:GetSpacing() or 0) end end)
    pcall(function() mirror:SetShadowOffset(eb:GetShadowOffset()) end)
    mirror:SetText(eb:GetText() or "")
    if showMirror then
        mirror:SetTextColor(1, 0.2, 0.2, 1); mirror:SetAlpha(0.8)
    else
        mirror:SetTextColor(1, 1, 1, 1); mirror:SetAlpha(0)
    end
end

local function HideBoxes()
    for _, t in ipairs(boxes) do t:Hide() end
end

local function GetBox(i)
    local t = boxes[i]
    if not t then
        t = layer:CreateTexture(nil, "OVERLAY")
        boxes[i] = t
    end
    return t
end

local relativeMode  -- nil = not decided, true = rects relative to the mirror

-- Round 6 (2026-10-25): EditBox:GetRegions() hands back the box's own
-- FontString (same text, has the span function). `/bnbspell own` measures on
-- it instead of the mirror: same layout by definition, CJK fallback included.
local useOwn = true   -- round 6: right on every note, CJK included (mirror kept for comparison)
local src  -- the FontString measured: the mirror or the box's own

local function OwnFS()
    for _, r in ipairs({ eb:GetRegions() }) do
        if r.GetObjectType and r:GetObjectType() == "FontString" and r.CalculateScreenAreaFromCharacterSpan then
            return r
        end
    end
end

local function PickSource()
    src = mirror
    if useOwn then
        local own = OwnFS()
        if own then src = own else Say("no own FontString found, using the mirror") end
    end
end

-- Round 2 (2026-10-25): every box stopped one letter short with (first, last),
-- so the span end looks exclusive; `/bnbspell end` switches back to compare.
local endPlusOne = true
-- What asked for a redraw since the last one, and the state last drawn: the
-- first round redrew four times a second with nothing changed
local triggers = {}
local lastSig, forceDraw
local skips, lastSkipSay = 0, 0

local function Signature()
    local path, size, flags = eb:GetFont()
    return table.concat({ eb:GetText() or "", tostring(eb:GetWidth()), tostring(path), tostring(size),
        tostring(flags), tostring(eb:GetJustifyH()), tostring(showMirror), tostring(charMode), tostring(endPlusOne) }, "\1")
end

-- ── Round 7 (2026-10-25): the real checker, simulated ───────────────────────
-- `/bnbspell check`: instead of boxing every word, only the known typos (the
-- TYPO set, standing in for "not in the dictionary") get a red underline, the
-- way stage 1 will draw them: the visible part first, under a time budget per
-- frame (BUDGET_MS) so a long note never freezes the game.
local BUDGET_MS = 4
local typoMode = false
local snapLines = true   -- round 8, `/bnbspell snap` switches it off to compare
local runGen = 0

-- correct word -> the misspelling the long test note puts in its place
local TYPOS = {
    receive = "recieve", separate = "seperate", definitely = "definately", occurred = "occured",
    ["until"] = "untill", weird = "wierd", accommodate = "accomodate", necessary = "neccessary",
    because = "becuase", their = "thier", which = "wich", believe = "beleive",
    tomorrow = "tommorow", dungeon = "dungoen", achievement = "acheivement", friend = "freind",
    again = "agian", really = "realy", before = "befor", whether = "wether",
    beginning = "begining", probably = "probly", different = "diffrent", interesting = "intresting",
}
local TYPO_SET = {}
for _, wrong in pairs(TYPOS) do TYPO_SET[wrong] = true end
TYPO_SET.teh = true   -- note A only: "the" is too common for the long note

local function RunTypos(text, words, t0, t1)
    runGen = runGen + 1
    local myGen = runGen
    HideBoxes()
    local hits = {}
    for _, w in ipairs(words) do
        if TYPO_SET[text:sub(w.first, w.last):lower()] then hits[#hits + 1] = w end
    end
    local t2 = debugprofilestop()
    -- Visible byte range: the letters under the scroll frame's top-left and
    -- bottom-right corners (FindCharacterIndexAtCoordinate takes coords in
    -- the FontString's own scale, as the Alt probe found)
    local k = sf:GetEffectiveScale() / src:GetEffectiveScale()
    local okA, vA = pcall(src.FindCharacterIndexAtCoordinate, src, (sf:GetLeft() + 2) * k, (sf:GetTop() - 2) * k)
    local okB, vB = pcall(src.FindCharacterIndexAtCoordinate, src, (sf:GetRight() - 2) * k, (sf:GetBottom() + 2) * k)
    vA = (okA and type(vA) == "number") and vA or 1
    vB = (okB and type(vB) == "number") and vB or #text
    local order, nVis = {}, 0
    for _, w in ipairs(hits) do
        if w.last >= vA and w.first <= vB then nVis = nVis + 1; order[#order + 1] = w end
    end
    for _, w in ipairs(hits) do
        if not (w.last >= vA and w.first <= vB) then order[#order + 1] = w end
    end
    -- The text top: the first letter's rect top, plus a line per leading newline
    local lead = #(text:match("^\n*") or "")
    local topY = 0
    local okT, resT = pcall(src.CalculateScreenAreaFromCharacterSpan, src, lead + 1, lead + 2)
    local rT = okT and type(resT) == "table" and (type(resT[1]) == "table" and resT[1] or resT)
    if rT then
        local _, b, _, h = ReadRect(rT)
        if b then topY = b + h + lead * h end
    end
    -- Round 8 (2026-10-25): underlines drifted the further down the long
    -- note (BNB's old underline bug). The span answer spaces lines a little
    -- wider than the box draws them (note B: 12.73 vs 12.67), and the error
    -- adds up line by line. So: the line number comes from the answer, the
    -- place from the box's real line step (its height / its lines).
    local nLines = (src.GetNumLines and src:GetNumLines()) or 0
    local _, _, insT, insB = eb:GetTextInsets()
    local apiStep = nLines > 0 and topY / nLines or 0
    local realStep = nLines > 0 and (eb:GetHeight() - (insT or 0) - (insB or 0)) / nLines or 0
    local useSnap = snapLines and apiStep > 0 and realStep > 0
    local t3 = debugprofilestop()
    local i, frames, worst, total, visFrames, nBox = 1, 0, 0, 0, nil, 0
    local function step()
        if myGen ~= runGen or not on then return end
        local fs = debugprofilestop()
        while i <= #order and debugprofilestop() - fs < BUDGET_MS do
            local w = order[i]
            local ok, res = pcall(src.CalculateScreenAreaFromCharacterSpan, src, w.first, w.last + 1)
            local list = ok and type(res) == "table" and (type(res[1]) == "table" and res or { res }) or {}
            for _, r in ipairs(list) do
                local l, b, wd, h = ReadRect(r)
                if l then
                    nBox = nBox + 1
                    local line = GetBox(nBox)
                    line:ClearAllPoints()
                    -- 2 = lifted a pixel from round 7 (Dukul: "almost touches the words below")
                    local y = b - topY + 2
                    if useSnap then
                        local idx = math.floor((topY - b - h) / apiStep + 0.5)
                        y = -(idx * realStep + h) + 2
                    end
                    line:SetPoint("TOPLEFT", src, "TOPLEFT", l, y)
                    line:SetSize(math.max(1, wd), 2)
                    line:SetColorTexture(1, 0.15, 0.15, 0.95)
                    line:Show()
                end
            end
            i = i + 1
        end
        local spent = debugprofilestop() - fs
        frames = frames + 1
        total = total + spent
        if spent > worst then worst = spent end
        if not visFrames and i > nVis then visFrames = frames end
        if i <= #order then C_Timer.After(0, step); return end
        for j = nBox + 1, #boxes do boxes[j]:Hide() end
        Say("check: %d words, %d typos (%d in view, bytes %d-%d); in view underlined after %d frame(s), all after %d frames; spans %.1f ms in all, worst frame %.1f ms (budget %d); tokenize %.2f ms, look-up %.2f ms, view + top %.2f ms",
            #words, #hits, nVis, vA, vB, visFrames or 0, frames, total, worst, BUDGET_MS, t1 - t0, t2 - t1, t3 - t2)
        Say("lines: %d, text top %.1f, answer's line step %.3f, box's line step %.3f (box height %.1f), snap %s",
            nLines, topY, apiStep, realStep, eb:GetHeight() or 0, useSnap and "ON" or "off")
    end
    step()
end

local function Draw()
    pending = false
    if not on then return end
    eb, sf = Body()
    if not (eb and eb:IsVisible()) then HideBoxes(); return end
    local why = {}
    for k, n in pairs(triggers) do why[#why + 1] = k .. " x" .. n end
    wipe(triggers)
    local sig = Signature()
    if sig == lastSig and not forceDraw then
        -- At most one chat line every 5 s, so a loop shows without flooding
        skips = skips + 1
        if GetTime() - lastSkipSay > 5 then
            lastSkipSay = GetTime()
            Say("redraw asked by %s with nothing changed: skipped (%d skips so far)", table.concat(why, ", "), skips)
        end
        return
    end
    lastSig, forceDraw = sig, false
    local t0 = debugprofilestop()
    CopyLook()
    PickSource()
    local text = eb._showingPlaceholder and "" or (eb:GetText() or "")
    local words = Words(text)
    local t1 = debugprofilestop()
    local mL, mT = src:GetLeft(), src:GetTop()
    if not (mL and mT) then HideBoxes(); return end
    if typoMode then RunTypos(text, words, t0, t1); return end
    runGen = runGen + 1   -- stops a check still running
    local used, calls, misses = 0, 0, 0
    local rects = {}
    for _, w in ipairs(words) do
        local a, z = w.first, w.last
        if charMode then a, z = CharIndex(text, a), CharIndex(text, z) end
        if endPlusOne then z = z + 1 end
        calls = calls + 1
        local ok, res = pcall(src.CalculateScreenAreaFromCharacterSpan, src, a, z)
        if not ok then
            Say("CalculateScreenAreaFromCharacterSpan error: %s", tostring(res)); on = false; HideBoxes(); return
        end
        if not shapeShown then shapeShown = true; DumpShape(res) end
        local list = (type(res) == "table" and type(res[1]) == "table") and res or { res }
        local any = false
        for _, r in ipairs(list) do
            local l, b, wd, h = ReadRect(r)
            if l then
                any = true
                if relativeMode == nil then
                    -- Screen coords sit near the mirror's own left; relative ones near 0
                    relativeMode = (mL > 50 and l < mL * 0.5) or false
                    Say("rects look %s (first rect left %.1f, mirror left %.1f, bottom %.1f, mirror top %.1f)",
                        relativeMode and "RELATIVE to the mirror" or "in SCREEN coords", l, mL, b, mT)
                end
                used = used + 1
                if used > MAX_BOXES then break end
                rects[used] = { l, b, wd, h }
            end
        end
        if not any then misses = misses + 1 end
        if used > MAX_BOXES then break end
    end
    -- Round 5 (2026-10-25): relative rects are measured up from a bottom
    -- that includes an empty last line, while src:GetHeight() leaves it
    -- out (note B: height 266, first line's bottom at 267), so boxes sat one
    -- line high. Measure from the top of the text instead: the highest rect
    -- top, plus one line per newline the text starts with.
    local topY, lineH = 0, 0
    for _, r in ipairs(rects) do
        if r[2] + r[4] > topY then topY, lineH = r[2] + r[4], r[4] end
    end
    local lead = #(text:match("^\n*") or "")
    topY = topY + lead * lineH
    for i = 1, math.min(used, MAX_BOXES) do
        local l, b, wd, h = rects[i][1], rects[i][2], rects[i][3], rects[i][4]
        local box = GetBox(i)
        box:ClearAllPoints()
        if relativeMode then
            box:SetPoint("BOTTOMLEFT", src, "TOPLEFT", l, b - topY)
        else
            box:SetPoint("BOTTOMLEFT", src, "TOPLEFT", l - mL, b - mT)
        end
        box:SetSize(math.max(1, wd), math.max(1, h))
        if i % 2 == 0 then box:SetColorTexture(0.2, 1, 0.3, 0.35) else box:SetColorTexture(0.2, 0.6, 1, 0.35) end
        box:Show()
    end
    for i = math.min(used, MAX_BOXES) + 1, #boxes do boxes[i]:Hide() end
    local t2 = debugprofilestop()
    Say("text top %.1f (old way: height %.1f), %d leading newlines", topY, src:GetHeight() or 0, lead)
    -- Round 4: note B (pasted from a text file) drifted with no CJK in it.
    -- Hidden characters the box and the mirror may draw differently:
    local _, nCR = text:gsub("\r", "")
    local _, nLF = text:gsub("\n", "")
    local _, nTab = text:gsub("\t", "")
    local _, nHi = text:gsub("[\128-\255]", "")
    Say("text: %d bytes, \\n x%d, \\r x%d, tab x%d, high bytes x%d; mirror height %.1f, edit box height %.1f, mirror width %.1f, edit box width %.1f",
        #text, nLF, nCR, nTab, nHi, src:GetHeight() or 0, eb:GetHeight() or 0, src:GetWidth() or 0, eb:GetWidth() or 0)
    Say("%d words, %d boxes (%s indices, end %s); %d spans gave no rect; mirror %d lines; tokenize %.2f ms, spans + boxes %.2f ms (%.3f ms per word); asked by %s",
        #words, math.min(used, MAX_BOXES), charMode and "character" or "byte", endPlusOne and "last+1" or "last", misses,
        src.GetNumLines and src:GetNumLines() or -1, t1 - t0, t2 - t1, (t2 - t1) / math.max(1, calls),
        #why > 0 and table.concat(why, ", ") or "command")
end

local function Schedule(kind)
    if not on then return end
    triggers[kind] = (triggers[kind] or 0) + 1
    if pending then return end
    pending = true
    C_Timer.After(0.25, Draw)
end

local function AltProbe()
    if not (on and src and IsAltKeyDown() and eb and eb:IsMouseOver()) then return end
    local now = GetTime()
    if now - lastAlt < 0.5 then return end
    lastAlt = now
    local s = src:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx, cy = cx / s, cy / s
    local mL, mT = src:GetLeft(), src:GetTop()
    local okA, absIdx = pcall(src.FindCharacterIndexAtCoordinate, src, cx, cy)
    local okR, relIdx = pcall(src.FindCharacterIndexAtCoordinate, src, cx - mL, mT - cy)
    local text = src:GetText() or ""
    local function show(ok, idx)
        if not ok then return "error " .. tostring(idx) end
        if type(idx) ~= "number" then return tostring(idx) end
        -- The byte at idx in brackets, to see whether idx is 0- or 1-based
        local s = text:sub(math.max(1, idx - 3), idx - 1) .. "[" .. text:sub(idx, idx) .. "]" .. text:sub(idx + 1, idx + 3)
        return string.format("%d '%s'", idx, (s:gsub("|", "||")))
    end
    Say("Alt: screen coords -> %s  |  mirror-relative (x, down) -> %s", show(okA, absIdx), show(okR, relIdx))
end

local function Setup()
    eb, sf = Body()
    if not eb then Say("Open the main window and a note first."); return false end
    if not layer then
        layer = CreateFrame("Frame", nil, sf)
        layer:SetAllPoints(sf)
        layer:SetClipsChildren(true)
        mirror = layer:CreateFontString(nil, "OVERLAY")
        -- The boxes anchor to the mirror, the mirror to the edit box (the
        -- scroll child), so scrolling moves them with the text
        eb:HookScript("OnTextChanged", function(_, user) Schedule(user and "typing" or "text set") end)
        sf:HookScript("OnSizeChanged", function() Schedule("resize") end)
        layer:SetScript("OnUpdate", AltProbe)
    end
    layer:SetFrameLevel(eb:GetFrameLevel() + 5)
    return true
end

-- ── Underline / strikethrough in the rich View mode (2026-10-25) ────────────
-- `/bnbspell html`: what the editor's SimpleHTML view is made of, and whether
-- an invisible link marker (|Hbnbline:u|h...|h, no colour) survives into the
-- FontStrings it draws, so the View mode could find the {u} words the same
-- way the Edit mode does.
local function HtmlProbe()
    local function list(frame, label)
        if not frame then Say("%s: not there (open a rich note in View mode first)", label); return end
        local regions = { frame:GetRegions() }
        local nFS, nSpan, sample = 0, 0, nil
        for _, r in ipairs(regions) do
            if r.GetObjectType and r:GetObjectType() == "FontString" then
                nFS = nFS + 1
                if r.CalculateScreenAreaFromCharacterSpan then nSpan = nSpan + 1 end
                local t = r:GetText()
                if t and t ~= "" and not sample then sample = t end
            end
        end
        local kids = { frame:GetChildren() }
        Say("%s: %s, %d regions, %d FontStrings (%d with the span function), %d child frames; first text: %s",
            label, frame:GetObjectType(), #regions, nFS, nSpan, #kids,
            sample and ("'" .. sample:sub(1, 60):gsub("|", "||") .. "'") or "none")
    end
    list(BigNoteBox and BigNoteBox._editorRenderFrame, "editor View mode")

    -- Round 2 (2026-10-25): the first round's span after the marker gave nil.
    -- What one span answer looks like, plus the FontString's own state
    local function SpanInfo(fs, a, z)
        local ok, res = pcall(fs.CalculateScreenAreaFromCharacterSpan, fs, a, z)
        local what
        if not ok then what = "error " .. tostring(res)
        elseif type(res) ~= "table" then what = tostring(res)
        else
            local r = type(res[1]) == "table" and res[1] or res
            what = string.format("%d rect(s), first left %.1f bottom %.1f w %.1f h %.1f", type(res[1]) == "table" and #res or 1,
                r.left or -1, r.bottom or -1, r.width or -1, r.height or -1)
        end
        return string.format("span(%d,%d) = %s [lines %s, shown %s, w %.0f h %.0f, string w %.0f]", a, z, what,
            tostring(fs.GetNumLines and fs:GetNumLines()), tostring(fs:IsVisible()), fs:GetWidth() or 0,
            fs:GetHeight() or 0, fs:GetStringWidth() or 0)
    end
    local rf = BigNoteBox and BigNoteBox._editorRenderFrame
    if rf and rf:IsVisible() then
        local i = 0
        for _, r in ipairs({ rf:GetRegions() }) do
            if r.GetObjectType and r:GetObjectType() == "FontString" and i < 3 then
                i = i + 1
                Say("  view line %d: %s", i, SpanInfo(r, 1, 4))
            end
        end
    end

    -- A test SimpleHTML with a marked word that wraps over two lines, shown a
    -- full second before it is asked; and a plain FontString with the same
    -- text, to see whether the |H codes or SimpleHTML make the difference
    local AM = BigNoteBox and BigNoteBox.AdvancedMode
    if not (AM and AM.CreateRenderFrame) then Say("AdvancedMode not loaded"); return end
    local TEXT = "Plain words, then |Hbnbline:u|hthese words are marked and wrap onto the next line|h and plain again."
    local f = AM.CreateRenderFrame(nil, UIParent)
    f:SetSize(220, 120)
    f:SetPoint("CENTER")
    f:SetFrameStrata("TOOLTIP")
    f:Show()
    f:SetText("<html><body><p>" .. TEXT .. "</p></body></html>")
    local plain = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    plain:SetWidth(220); plain:SetWordWrap(true)
    plain:SetPoint("CENTER", 0, -150)
    plain:SetText(TEXT)
    C_Timer.After(1, function()
        local found, total = 0, 0
        for _, r in ipairs({ f:GetRegions() }) do
            if r.GetObjectType and r:GetObjectType() == "FontString" then
                total = total + 1
                local t = r:GetText() or ""
                local s, e = t:find("|Hbnbline:u|h", 1, true)
                Say("  test line %d: '%s'%s", total, t:gsub("|", "||"), s and " <- marker" or "")
                Say("    start: %s", SpanInfo(r, 1, 6))
                if s then
                    found = found + 1
                    Say("    after the marker: %s", SpanInfo(r, e + 1, e + 6))
                end
            end
        end
        Say("test SimpleHTML: %d FontStrings, %d with the marker", total, found)
        local _, pe = TEXT:find("|Hbnbline:u|h", 1, true)
        Say("plain FontString, start: %s", SpanInfo(plain, 1, 6))
        Say("plain FontString, after the marker: %s", SpanInfo(plain, pe + 1, pe + 6))
        f:Hide(); plain:Hide()
    end)
end

local function Regions()
    eb = Body()
    if not eb then Say("Open the main window and a note first."); return end
    local regions = { eb:GetRegions() }
    Say("EditBox:GetRegions() gave %d regions", #regions)
    for i, r in ipairs(regions) do
        local kind = r.GetObjectType and r:GetObjectType() or "?"
        local extra = ""
        if kind == "FontString" then
            local txt = r:GetText() or ""
            extra = string.format(" text %d bytes, has span fn: %s, same text as box: %s",
                #txt, tostring(r.CalculateScreenAreaFromCharacterSpan ~= nil), tostring(txt == eb:GetText()))
        end
        Say("  %d: %s%s", i, kind, extra)
    end
    if eb.GetFontString then Say("EditBox:GetFontString exists: %s", tostring(eb:GetFontString())) end
end

local function Bench()
    local seed = { "the", "quick", "brown", "fox", "jumps", "over", "lazy", "dog", "Stormwind",
        "dungeon", "remember", "vendor", "tomorrow", "Thrall", "necessary", "occasion" }
    local parts = {}
    for i = 1, 5000 do
        parts[i] = seed[(i * 7) % #seed + 1]
        if i % 60 == 0 then parts[i] = parts[i] .. "\n" end
    end
    local text = table.concat(parts, " ")
    local fs = UIParent:CreateFontString(nil, "OVERLAY")
    local path, size = (Body() or GameFontNormal):GetFont()
    fs:SetFont(path, size or 13, "")
    fs:SetWidth(500); fs:SetWordWrap(true); fs:SetAlpha(0)
    fs:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    local t0 = debugprofilestop()
    fs:SetText(text)
    local lines = fs.GetNumLines and fs:GetNumLines() or -1
    local t1 = debugprofilestop()
    local words = Words(text)
    local t2 = debugprofilestop()
    local got = 0
    for _, w in ipairs(words) do
        local ok, res = pcall(fs.CalculateScreenAreaFromCharacterSpan, fs, w.first, w.last)
        if ok and res then got = got + 1 end
    end
    local t3 = debugprofilestop()
    Say("5000 words, %d bytes, %d lines: SetText %.1f ms, tokenize %.1f ms, %d spans %.1f ms",
        #text, lines, t1 - t0, t2 - t1, got, t3 - t2)

    -- Round 6: the same words measured one paragraph at a time (the text
    -- split at its newlines, ~60 words each): does a span cost follow the
    -- length of the text it sits in?
    local paras, pWords = 0, 0
    local t8 = debugprofilestop()
    for para in (text .. "\n"):gmatch("([^\n]*)\n") do
        paras = paras + 1
        fs:SetText(para)
        for _, w in ipairs(Words(para)) do
            local ok, res = pcall(fs.CalculateScreenAreaFromCharacterSpan, fs, w.first, w.last + 1)
            if ok and res then pWords = pWords + 1 end
        end
    end
    local t9 = debugprofilestop()
    -- And 30 spans on the whole text, the most a real note would ask for
    fs:SetText(text)
    local t10 = debugprofilestop()
    for i = 1, 30 do
        local w = words[math.floor(i * #words / 31)]
        pcall(fs.CalculateScreenAreaFromCharacterSpan, fs, w.first, w.last + 1)
    end
    local t11 = debugprofilestop()
    fs:Hide()
    Say("per paragraph: %d paragraphs, %d spans %.1f ms (%.3f ms per word); 30 spans on the whole text %.1f ms",
        paras, pWords, t9 - t8, (t9 - t8) / math.max(1, pWords), t11 - t10)

    local function lev(a, b)
        local la, lb = #a, #b
        local prev, cur = {}, {}
        for j = 0, lb do prev[j] = j end
        for i = 1, la do
            cur[0] = i
            local ca = a:byte(i)
            for j = 1, lb do
                local c = (ca == b:byte(j)) and 0 or 1
                local v = prev[j] + 1
                if cur[j - 1] + 1 < v then v = cur[j - 1] + 1 end
                if prev[j - 1] + c < v then v = prev[j - 1] + c end
                cur[j] = v
            end
            prev, cur = cur, prev
        end
        return prev[lb]
    end
    local N = 20000
    local t4 = debugprofilestop()
    for i = 1, N do lev("necesary", seed[i % #seed + 1]) end
    local t5 = debugprofilestop()
    Say("Lua edit distance: %d calls %.1f ms", N, t5 - t4)
    if CalculateStringEditDistance then
        local t6 = debugprofilestop()
        for i = 1, N do CalculateStringEditDistance("necesary", seed[i % #seed + 1]) end
        local t7 = debugprofilestop()
        Say("CalculateStringEditDistance: %d calls %.1f ms, necesary/necessary = %s",
            N, t7 - t6, tostring(CalculateStringEditDistance("necesary", "necessary")))
    else
        Say("CalculateStringEditDistance: not on this client")
    end
end

-- ── Round 7: the test notes, made by `/bnbspell notes` ──────────────────────
-- A and B are _work/spell-test-note.txt / -b.txt (A has Chinese / Korean in
-- line 4, B does not), with a real item link where the file says ITEM.
-- The long note is ~5000 words of guide-like sentences with a typo from TYPOS
-- in place of every third word that has one (about 2 in 100 words).
local NOTE_A = "Spell probe test (ALL-559 KU4 / KU5)\n\n1. Plain words: The quick brown fox jumps over the lazy dog.\n2. Typos on purpose: teh recieve seperate definately occured untill wierd accomodate.\n3. Accents: caf\195\169, na\195\175ve, \195\188ber, Stra\195\159e, ni\195\177o, \195\134r\195\184sk\195\184bing, Pok\195\169mon, d\195\169j\195\160 vu, r\195\169sum\195\169.\n4. Other scripts: \208\191\209\128\208\184\208\178\208\181\209\130 \208\188\208\184\209\128, \206\147\206\181\206\185\206\172 \207\131\206\191\207\133, \228\189\160\229\165\189\228\184\150\231\149\140, \236\149\136\235\133\149\237\149\152\236\132\184\236\154\148.\n5. Link here -> @LINK@ <- then more words after the link: sword shield potion.\n6. Two links in one line: @LINK@ and @LINK@ followed by words.\n7. Apostrophes and contractions: don't can't it's Dukul's o'clock rock'n'roll.\n8. Numbers and mixed: 12 bosses, 3rd floor, v1.26.0, 10am, 5x5, Mk2 armour.\n9. Markup: {icon:inv_misc_note_01} icon word, {{date}} token word, {b}bold{/b} word.\n10. Web and mail: https://dukul.net/addons/bnb www.example.com someone@example.com end.\n11. A very long word with no spaces: Supercalifragilisticexpialidociousandthensomemorelettersuntilitwraps then normal words.\n12. Hyphens and slashes: well-known, up-to-date, Ctrl+Shift+click, /way 45.2 61.8, and/or.\n13. ALL CAPS WORDS and CamelCase BigNoteBox ReferenceBox words.\n\n14. After a blank line: this paragraph wraps over several lines so the boxes must follow the wrap from one line to the next without drifting sideways or down, even at the very end of a long line that breaks in the middle of the window.\n\t15. A line that starts with a tab, then words.\n16.     Several spaces    between     words here.\nLast line with no full stop at the end"
local NOTE_B = "Spell probe test B, no Chinese / Korean (ALL-559 KU4 / KU5)\n\n1. Plain words: The quick brown fox jumps over the lazy dog.\n2. Typos on purpose: teh recieve seperate definately occured untill wierd accomodate.\n3. Accents: caf\195\169, na\195\175ve, \195\188ber, Stra\195\159e, ni\195\177o, \195\134r\195\184sk\195\184bing, Pok\195\169mon, d\195\169j\195\160 vu, r\195\169sum\195\169.\n5. Link here -> @LINK@ <- then more words after the link: sword shield potion.\n6. Two links in one line: @LINK@ and @LINK@ followed by words.\n7. Apostrophes and contractions: don't can't it's Dukul's o'clock rock'n'roll.\n8. Numbers and mixed: 12 bosses, 3rd floor, v1.26.0, 10am, 5x5, Mk2 armour.\n9. Markup: {icon:inv_misc_note_01} icon word, {{date}} token word, {b}bold{/b} word.\n10. Web and mail: https://dukul.net/addons/bnb www.example.com someone@example.com end.\n11. A very long word with no spaces: Supercalifragilisticexpialidociousandthensomemorelettersuntilitwraps then normal words.\n12. Hyphens and slashes: well-known, up-to-date, Ctrl+Shift+click, /way 45.2 61.8, and/or.\n13. ALL CAPS WORDS and CamelCase BigNoteBox ReferenceBox words.\n\n14. After a blank line: this paragraph wraps over several lines so the boxes must follow the wrap from one line to the next without drifting sideways or down, even at the very end of a long line that breaks in the middle of the window.\n\t15. A line that starts with a tab, then words.\n16.     Several spaces    between     words here.\nLast line with no full stop at the end"
local ITEM_LINK = "|cffff8000|Hitem:19019::::::::60:::::|h[Thunderfury, Blessed Blade of the Windseeker]|h|r"

local SENTENCES = {
    "Before you go into the dungeon, make sure your friend has the key and that the whole group knows which boss comes first.",
    "I really believe the vendor in the inn will receive new stock tomorrow, so check again before the weekly reset.",
    "This achievement is weird because you have to separate the adds and kill them at different times.",
    "It is necessary to accommodate the healer, who probably needs a moment to drink after every second pull.",
    "Whether you tank or heal, the beginning of the fight is the most interesting part, and it is definitely the hardest.",
    "Their guild cleared the raid until the last boss, which occurred on the night the server went down.",
    "Remember to buy reagents, repair your gear and empty your bags before the long flight to the other continent.",
    "The quest giver stands next to the flight master, and the item you need drops from the elementals near the lake.",
    "If you are a crafter, keep a few stacks of cloth and ore in the bank so you can make the order without travelling.",
    "My friend wrote a note about the route through the zone, and it is really useful when the map is full of rares.",
    "The second phase begins when the boss reaches half health, and the whole raid has to move to the edge of the room.",
    "Check the auction house in the morning, because the prices are usually lower before most players log in.",
    "Which talents you pick depends on the content: one set for dungeons, a different one for the raid, and one for the world.",
    "I believe the event starts at the top of the hour, so we meet at the portal room a few minutes before.",
    "The pet trainer near the stables will teach you the basics, and the first few battles are easy enough to win alone.",
    "We wiped again on the last pull because the patrol came around the corner just as the tank pulled the pack.",
}

local function LongText()
    local parts, count, seen, nTypos, nSent = {}, 0, {}, 0, 0
    local i = 0
    while count < 5000 do
        i = i + 1
        local s = SENTENCES[(i * 7) % #SENTENCES + 1]
        local out = s:gsub("%a+", function(word)
            count = count + 1
            local wrong = TYPOS[word:lower()]
            if wrong then
                seen[word] = (seen[word] or 0) + 1
                if seen[word] % 3 == 0 then
                    nTypos = nTypos + 1
                    return word:match("^%u") and (wrong:gsub("^%l", string.upper)) or wrong
                end
            end
        end)
        parts[#parts + 1] = out
        nSent = nSent + 1
        parts[#parts + 1] = (nSent % 5 == 0) and "\n\n" or " "
    end
    return "Spell probe test: about 5000 words (ALL-559)\n\n" .. table.concat(parts), count, nTypos
end

local TEST_TAG = "spelltest"

-- A rich note with every markup tag (Dukul, 2026-10-25: "a rich note with all
-- our stylings for testing"): headers, paragraphs and their alignments, line
-- break, colour, icons, atlas, picture, links, tokens, a game link, and
-- underline / strikethrough (single, wrapped, nested, unclosed)
local RICH_ALL = [=[{h1}Header 1{/h1}
{h1:c}Header 1 centered{/h1}
{h1:r}Header 1 right{/h1}
{h2}Header 2{/h2}
{h3}Header 3{/h3}
{p}A paragraph with a line break here{br}and the text after it.{/p}
{p:l}A left aligned paragraph.{/p}
{p:c}A centered paragraph.{/p}
{p:r}A right aligned paragraph.{/p}
Bare text outside any block, then {col:ff8800}orange text{/col} and {col:66bb6a}green text{/col}.
An icon in the text {icon:INV_Misc_Note_01:16} and a bigger one {icon:INV_Misc_Spyglass_03:24}.
{icon:INV_Misc_Bag_08:32:c}
An atlas {atlas:UI-Frame-Neutral-ExitButtonBorder:16} in the text.
{img:Interface\AddOns\BigNoteBox\Assets\icon:64:64:c}
A web link {link*https://dukul.net*Dukul.net} and a BigNoteBox link {link*bnbui:oracle*the Oracle bar}.
A game link: @LINK@ in the text.
Tokens: today is {{date}}, you are in {{zone}}.
{u}Underlined words{/u} and {s}struck through words{/s} on one line.
{u}A long underlined sentence that is long enough to wrap onto a second line when the window is not very wide at all.{/u}
{s}Struck {u}and underlined{/u} together{/s}, nested.
{h2}{u}An underlined header{/u}{/h2}
{col:ff8800}{u}Orange and underlined{/u}{/col}, then {s}{col:66bb6a}green and struck{/col}{/s}.
{u}An underline left open runs to the end of this line
and stops here.]=]

local function MakeNotes()
    local BNB = BigNoteBox
    if not (BNB and BNB.CreateNote and BNB.NotesDB) then Say("BigNoteBox is not loaded."); return end
    local have = {}
    for _, n in pairs(BNB.NotesDB().notes or {}) do
        if type(n) == "table" and n.title then have[n.title] = true end
    end
    local long, nWords, nTypos = LongText()
    local list = {
        { "Spell test A (Chinese / Korean)", (NOTE_A:gsub("@LINK@", function() return ITEM_LINK end)) },
        { "Spell test B", (NOTE_B:gsub("@LINK@", function() return ITEM_LINK end)) },
        { "Spell test: 5000 words", long },
        { "Rich test: every tag", (RICH_ALL:gsub("@LINK@", function() return ITEM_LINK end)), true },
    }
    local made = 0
    for _, e in ipairs(list) do
        if have[e[1]] then
            Say("'%s' is already there (delete it to make it again)", e[1])
        else
            local id = BNB.CreateNote(e[1], e[2])
            if id then
                made = made + 1
                if BNB.UpdateNote then BNB.UpdateNote(id, { tags = { TEST_TAG }, richMode = e[3] or nil }) end
            end
        end
    end
    Say("%d test notes made (one rich, every tag), tag '%s'. The long one: %d words, %d typos. Open a note, then /bnbspell check.",
        made, TEST_TAG, nWords, nTypos)
end

SLASH_BNBSPELLPROBE1 = "/bnbspell"
SlashCmdList.BNBSPELLPROBE = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "regions" then Regions(); return end
    if msg == "bench" then Bench(); return end
    if msg == "notes" then MakeNotes(); return end
    if msg == "html" then HtmlProbe(); return end
    if not Setup() then return end
    if msg == "check" then
        -- Toggles the real-checker view; turns the probe on with it
        typoMode = not (typoMode and on)
        on = true
        Say("%s", typoMode and "real check: only the typos, red underlines, visible part first, 4 ms a frame"
            or "real check off: a box on every word")
    elseif msg == "snap" then
        snapLines = not snapLines
        typoMode, on = true, true
        Say("line snap %s", snapLines and "on (box's line step)" or "off (the span answer as it is)")
    elseif msg == "mirror" then
        showMirror = not showMirror
        Say("mirror %s", showMirror and "shown in red" or "hidden")
        on = true
    elseif msg == "chars" then
        charMode = not charMode
        Say("span indices: %s", charMode and "characters" or "bytes")
        on = true
    elseif msg == "own" then
        useOwn = not useOwn
        relativeMode = nil
        Say("measuring on %s", useOwn and "the edit box's own FontString" or "the mirror")
        on = true
    elseif msg == "font" then
        fontMode = fontMode % #fontModes + 1
        on = true
    elseif msg == "end" then
        endPlusOne = not endPlusOne
        Say("span end: %s", endPlusOne and "last letter + 1" or "last letter")
        on = true
    else
        on = not on
        Say("probe %s%s", on and "on" or "off", on and " (hold Alt over the body for the letter under the mouse)" or "")
    end
    layer:SetShown(on)
    forceDraw = true
    if on then Draw() else HideBoxes() end
end

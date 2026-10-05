-- BigNoteBox_Dev Labs/SearchLayoutTool.lua -- the search bar themes' layout tool
-- (ALL-69), /bnb searchlayout in debug mode. Moved out of BigNoteBox's
-- UI/SearchChrome.lua (ARCH-04); it reads that file's private pieces through
-- BNB._SearchKit.

-- Queued for BigNoteBox's Core/DevTools.lua, which runs it once BigNoteBox
-- has loaded (this addon loads first, ARCH-04). The body is not indented.
BigNoteBoxDevLabs = BigNoteBoxDevLabs or {}
BigNoteBoxDevLabs[#BigNoteBoxDevLabs + 1] = function()

local BNB = BigNoteBox
local K = BNB._SearchKit
local PIECES, ORNAMENTS, NATIVE = K.PIECES, K.ORNAMENTS, K.NATIVE
local IsBackdrop, PlacePiece = K.IsBackdrop, K.PlacePiece
local ThemeLayout, ThemePanel = K.ThemeLayout, K.ThemePanel

--------------------------------------------------------------------------------
-- LAYOUT TOOL (debug mode only)
--------------------------------------------------------------------------------
-- A tall panel on the left of the screen, grouped: the search bar's pieces,
-- the results panel's pieces (its own copy, placed apart from the bar's),
-- the selected piece, and the tool buttons. The preview is the whole Oracle
-- in the middle of the screen: the bar plus a results panel with fake rows
-- (UI/Oracle.lua DrawPreview), so a theme is judged on what players see.
-- The Move anchor drags the whole preview (right-click: back to the centre).
local tool

local TOOL_W, TOOL_H = 300, 824
local TOOL_PAD = 10
local WHITE = "Interface\\Buttons\\WHITE8x8"

-- The results panel's placement under the bar (panelPos) is not art; it is
-- selected and moved like a piece of the panel.
local PLACE = "placement"
-- Where the results sit inside the panel (panelPad): selected and moved
-- like the placement. Neither is a piece of art.
local CONTENT = "content"
local function Special(sel) return sel == PLACE or sel == CONTENT end

-- Short button labels where the key is long.
local LABEL = {
    topornament = "top mid", bottomornament = "bottom mid",
    pornament1 = "ornament 1", pornament2 = "ornament 2",
    pornament3 = "ornament 3", pornament4 = "ornament 4",
}

-- Where a piece goes when it is added to a theme that does not use it yet.
-- Anything else starts from the bar's own piece (on the panel) or the
-- default theme's layout (on the bar).
local ADD_DEFAULT = {
    top2           = { a1 = "TOP",         x1 =  32, y1 =  0, a2 = "TOPRIGHT",    x2 = -32, y2 = -32 },
    bottom2        = { a1 = "BOTTOM",      x1 =  32, y1 = 32, a2 = "BOTTOMRIGHT", x2 = -32, y2 =   0 },
    topornament    = { a1 = "TOP",         x1 = -32, y1 =  0, a2 = "TOP",         x2 =  32, y2 = -32 },
    bottomornament = { a1 = "BOTTOM",      x1 = -32, y1 = 32, a2 = "BOTTOM",      x2 =  32, y2 =   0 },
    pornament1     = { a1 = "TOPLEFT",     x1 = -16, y1 = 16, a2 = "TOPLEFT",     x2 =  16, y2 = -16 },
    pornament2     = { a1 = "TOPRIGHT",    x1 = -16, y1 = 16, a2 = "TOPRIGHT",    x2 =  16, y2 = -16 },
    pornament3     = { a1 = "BOTTOMLEFT",  x1 = -16, y1 = 16, a2 = "BOTTOMLEFT",  x2 =  16, y2 = -16 },
    pornament4     = { a1 = "BOTTOMRIGHT", x1 = -16, y1 = 16, a2 = "BOTTOMRIGHT", x2 =  16, y2 = -16 },
}
-- Pieces that can never be removed.
local KEEP = { bg = true, text = true }

-- Which pieces belong on which side.
local function OnSide(side, def)
    if side == "panel" then return not def.barOnly end
    return not def.panelOnly
end

local function CopyPiece(p)
    return { a1 = p.a1, x1 = p.x1, y1 = p.y1, a2 = p.a2, x2 = p.x2, y2 = p.y2, layer = p.layer }
end

local function CopyLayout(src)
    local out = {}
    for k, p in pairs(src) do out[k] = CopyPiece(p) end
    return out
end

-- The working copy lives in BNB.LabDB(), one per theme, so a /reload
-- keeps it. It starts as a copy of the theme's built-in layouts. removed /
-- panelRemoved list pieces taken out in the tool, so built-in ones stay out.
local function Work()
    local db = BNB.LabDB()
    db.devSearchLayout, db.devSearchSize = nil, nil   -- pre-theme keys (never shipped)
    db.devSearch = db.devSearch or {}
    local d = BNB.GetSearchTheme(tool.theme)
    local tl, ts = ThemeLayout(d)
    local pl, ps = ThemePanel(d)
    local w = db.devSearch[tool.theme]
    if not w then
        w = { layout = CopyLayout(tl),
              size = { w = ts.w, h = ts.h, border = ts.border, borderY = ts.borderY } }
        db.devSearch[tool.theme] = w
    end
    w.removed, w.panelRemoved = w.removed or {}, w.panelRemoved or {}
    if not w.panelLayout then
        w.panelLayout = CopyLayout(pl)
        w.panelSize = { border = ps.border, borderY = ps.borderY }
    end
    for k, p in pairs(tl) do   -- a piece added to the theme later
        if not w.layout[k] and not w.removed[k] then w.layout[k] = CopyPiece(p) end
    end
    for k, p in pairs(pl) do
        if not w.panelLayout[k] and not w.panelRemoved[k] then w.panelLayout[k] = CopyPiece(p) end
    end
    w.size.borderY = w.size.borderY or w.size.border
    w.panelSize.borderY = w.panelSize.borderY or w.panelSize.border
    -- A theme with a panelPad of its own starts from it; otherwise
    -- panelPad stays nil until the content is moved, so it keeps following
    -- the panel border until then (WorkPad).
    if w.panelPad == nil and type(BNB.GetSearchTheme(tool.theme).panelPad) == "table" then
        w.panelPad = BNB.GetSearchPanelPad(tool.theme)
    end
    if not w.panelPos then
        local pp = BNB.GetSearchPanelPos(tool.theme)
        w.panelPos = { left = pp.left, right = pp.right, gap = pp.gap, under = pp.under }
    end
    return w
end

-- The content inset in use: the working copy's, else the default for the
-- working panel border. edit = true makes it the working copy's own.
local function WorkPad(w, edit)
    if w.panelPad then return w.panelPad end
    local d = BNB.GetSearchPanelPad(nil, w.panelSize)
    if edit then w.panelPad = d end
    return d
end

-- The selected-result colour in use: the working copy's (set with the
-- tool's Highlight swatch), else the theme's own. edit = true makes it the
-- working copy's own.
local function WorkHL(w, edit)
    if w.highlight then return w.highlight end
    local r, g, b, a = BNB.GetSearchHighlight(tool.theme)
    local h = { r, g, b, a }
    if edit then w.highlight = h end
    return h
end

-- layout, size and removed list of one side of the working copy.
local function Side(side)
    local w = Work()
    if side == "panel" then return w.panelLayout, w.panelSize, w.panelRemoved, w end
    return w.layout, w.size, w.removed, w
end

-- Whole numbers print bare, anything else with two decimals.
local function Num(n)
    if n == math.floor(n) then return string.format("%d", n) end
    return string.format("%.2f", n)
end

-- Pieces that share a size when "Same size for matching pieces" is ticked
-- (on the same side only).
local GROUPS = {
    top = "tb", bottom = "tb", top2 = "tb", bottom2 = "tb", left = "lr", right = "lr",
    topleft = "c", topright = "c", bottomleft = "c", bottomright = "c",
    topornament = "mid", bottomornament = "mid",
    pornament1 = "po", pornament2 = "po", pornament3 = "po", pornament4 = "po",
}

local function PieceDef(key)
    for _, def in ipairs(PIECES) do
        if def.key == key then return def end
    end
end

-- Every used piece as { side, key }, bar first, then the panel and its
-- placement: Tab walks these.
local function UsedList()
    local out = {}
    for _, side in ipairs({ "bar", "panel" }) do
        local layout = Side(side)
        for _, def in ipairs(PIECES) do
            if OnSide(side, def) and layout[def.key] then out[#out + 1] = { side, def.key } end
        end
    end
    out[#out + 1] = { "panel", PLACE }
    out[#out + 1] = { "panel", CONTENT }
    return out
end

-- The selection, moved to the first used piece when the current one is not
-- used (a theme switch, or the piece was removed).
local function ValidSel()
    if Special(tool.sel) then return end
    if Side(tool.side)[tool.sel] then return end
    local first = UsedList()[1]
    tool.side, tool.sel = first[1], first[2]
end

-- Which edge of a piece stays put when its size is typed in: the side both
-- of its points hang off. nil = the piece stretches with its frame on that axis.
local function FixedSide(p, axis)
    if p.a1 == p.a2 then return (axis == "h") and "TOP" or "LEFT" end
    local A, B = (axis == "h") and "TOP" or "LEFT", (axis == "h") and "BOTTOM" or "RIGHT"
    if p.a1:find(A) and p.a2:find(A) then return A end
    if p.a1:find(B) and p.a2:find(B) then return B end
end

-- Size of a piece on screen in px, or nil on a stretching axis.
local function PieceSize(p, axis, k)
    if not FixedSide(p, axis) then return nil end
    if axis == "h" then return (p.y1 - p.y2) * k end
    return (p.x2 - p.x1) * k
end

-- Where frame point pt sits, from the frame's top-left, in screen px.
local function PointXY(pt, w, h)
    local x = pt:find("LEFT") and 0 or pt:find("RIGHT") and w or w / 2
    local y = pt:find("TOP") and 0 or pt:find("BOTTOM") and -h or -h / 2
    return x, y
end

-- Size on screen, in px, of a piece that stretches on axis: where its two
-- points land on host at the host's current size.
local function StretchSize(p, axis, k, host)
    local w, h = host:GetSize()
    local x1, y1 = PointXY(p.a1, w, h)
    local x2, y2 = PointXY(p.a2, w, h)
    if axis == "h" then return (y1 + p.y1 * k) - (y2 + p.y2 * k) end
    return (x2 + p.x2 * k) - (x1 + p.x1 * k)
end

-- Grows or shrinks a stretching piece to px on axis, evenly on both sides
-- so it stays centred. It still hangs off both points, so it keeps
-- following its frame (Dukul, 2026-09-27).
local function SetStretchSize(p, axis, px, k, host)
    local d = (px - StretchSize(p, axis, k, host)) / k / 2
    if axis == "h" then p.y1 = p.y1 + d; p.y2 = p.y2 - d
    else p.x1 = p.x1 - d; p.x2 = p.x2 + d end
end

local function SetPieceSize(p, axis, px, k)
    local v, side = px / k, FixedSide(p, axis)
    if side == "TOP" then p.y2 = p.y1 - v
    elseif side == "BOTTOM" then p.y1 = p.y2 + v
    elseif side == "LEFT" then p.x2 = p.x1 + v
    elseif side == "RIGHT" then p.x1 = p.x2 - v end
end

-- A files override as Lua source, one piece per entry.
local function FilesText(files)
    local keys = {}
    for k in pairs(files) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do
        local v = files[k]
        parts[#parts + 1] = string.format("%s = %s", k, v == false and "false" or string.format("%q", tostring(v)))
    end
    return "{ " .. table.concat(parts, ", ") .. " }"
end

-- The whole Register call: both layouts, sizes and the panel placement from
-- the working copy, everything else (files, panelFiles, panelBg, highlight)
-- as registered.
local function ExportText()
    local w = Work()
    local d = BNB.GetSearchTheme(tool.theme)
    local lines = { "Register({",
        string.format("    name   = %q,", d.name),
        d.folder and string.format("    folder = %q,", d.folder) or string.format("    path   = %q,", d.art) }
    local function LayoutLines(name, side, layout)
        lines[#lines + 1] = "    " .. name .. " = {"
        for _, def in ipairs(PIECES) do
            local p = OnSide(side, def) and layout[def.key]   -- nil: not used
            if p then
                lines[#lines + 1] = string.format(
                    "        %-14s = { a1 = %q, x1 = %s, y1 = %s, a2 = %q, x2 = %s, y2 = %s%s },",
                    def.key, p.a1, Num(p.x1), Num(p.y1), p.a2, Num(p.x2), Num(p.y2),
                    p.layer and string.format(", layer = %q", p.layer) or "")
            end
        end
        lines[#lines + 1] = "    },"
    end
    LayoutLines("layout", "bar", w.layout)
    lines[#lines + 1] = string.format("    size = { w = %d, h = %d, border = %d, borderY = %d },",
        w.size.w, w.size.h, w.size.border, w.size.borderY)
    LayoutLines("panelLayout", "panel", w.panelLayout)
    lines[#lines + 1] = string.format("    panelSize = { border = %d, borderY = %d },",
        w.panelSize.border, w.panelSize.borderY)
    lines[#lines + 1] = string.format("    panelPos = { left = %s, right = %s, gap = %s, under = %s },",
        Num(w.panelPos.left), Num(w.panelPos.right), Num(w.panelPos.gap), tostring(w.panelPos.under ~= false))
    if w.panelPad then
        lines[#lines + 1] = string.format("    panelPad = { left = %s, right = %s, top = %s, bottom = %s },",
            Num(w.panelPad.left), Num(w.panelPad.right), Num(w.panelPad.top), Num(w.panelPad.bottom))
    end
    if type(d.files) == "table" and next(d.files) then
        lines[#lines + 1] = "    files = " .. FilesText(d.files) .. ","
    end
    if type(d.panelFiles) == "table" and next(d.panelFiles) then
        lines[#lines + 1] = "    panelFiles = " .. FilesText(d.panelFiles) .. ","
    end
    if d.panelBg then lines[#lines + 1] = string.format("    panelBg = %q,", d.panelBg) end
    local h = w.highlight or d.highlight
    if type(h) == "table" then
        lines[#lines + 1] = string.format("    highlight = { %s, %s, %s, %s },",
            Num(h[1] or 1), Num(h[2] or 0.82), Num(h[3] or 0), Num(h[4] or 0.14))
    end
    lines[#lines + 1] = "})"
    return table.concat(lines, "\n")
end

-- Moves the highlight over the selected piece, or over the whole results
-- panel when its placement is selected.
local function PlaceHighlight()
    local hl = tool.hl
    local host = (tool.side == "panel") and tool.panel or tool.bar
    hl:SetParent(host)
    hl:ClearAllPoints()
    if tool.sel == PLACE then
        hl:SetAllPoints(host)
    elseif tool.sel == CONTENT then
        local pad = WorkPad(Work())
        hl:SetPoint("TOPLEFT", host, "TOPLEFT", pad.left, -pad.top)
        hl:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -pad.right, pad.bottom)
    else
        local layout, size = Side(tool.side)
        local p = layout[tool.sel]
        -- Over a "top" ornament too, which sits on the over frame.
        if ORNAMENTS[tool.sel] and p.layer == "top" and host._searchOver then hl:SetParent(host._searchOver) end
        PlacePiece(hl, host, p, size.border / NATIVE, size.borderY / NATIVE)
    end
    hl:SetDrawLayer("OVERLAY", 7)
    hl:SetShown(tool.showHL)
end

-- Ornament depth: the button steps through these (see ORNAMENTS).
local DEPTHS = { "own", "back", "top" }
local DEPTH_NAME = { own = "Over borders", back = "Behind borders", top = "Over everything" }

-- A results-panel piece hung from TOP points whose middle sits in the
-- panel's lower half: it keeps its distance from the top, so it drifts into
-- the results as they grow (Horde 2026-09-26, Molten Core 2026-09-27).
local function HangsWrong(p)
    if tool.side ~= "panel" or not p or Special(tool.sel) then return false end
    if not (p.a1:find("TOP") and p.a2:find("TOP")) then return false end
    local _, size = Side("panel")
    local ky = size.borderY / NATIVE
    local w, h = tool.panel:GetSize()
    local _, y1 = PointXY(p.a1, w, h)
    local _, y2 = PointXY(p.a2, w, h)
    return ((y1 + p.y1 * ky) + (y2 + p.y2 * ky)) / 2 < -h / 2
end

local function Refresh()
    local w = Work()
    ValidSel()
    local bar, panel = tool.bar, tool.panel
    BNB.ApplySearchChrome(bar, tool.theme, w.layout, w.size)
    panel._size = BNB.ApplySearchChrome(panel, tool.theme, w.panelLayout, w.panelSize, { panel = true })
    BNB.PlaceSearchPanel(panel, bar, tool.theme, w.panelPos)
    panel._pad = WorkPad(w)
    panel._hl = WorkHL(w)
    if BNB.Oracle and BNB.Oracle.DrawPreview then BNB.Oracle.DrawPreview(panel, tool.theme, tool.rows) end
    tool.title:SetText("Search bar layout (ALL-69)\n|cffffffff" .. BNB.GetSearchTheme(tool.theme).name .. "|r")
    PlaceHighlight()
    tool.anchor:SetShown(tool.showAnchor)

    -- Every piece has a button; one the theme does not use is dimmed, and
    -- clicking it adds the piece.
    for _, b in ipairs(tool.pieceBtns) do
        local used = Special(b.key) or Side(b.side)[b.key] ~= nil
        b:SetAlpha(used and 1 or 0.4)
        b.sel:SetShown(b.side == tool.side and b.key == tool.sel)
    end
    tool.removeBtn:SetEnabled(not Special(tool.sel) and not KEEP[tool.sel])
    local orn = ORNAMENTS[tool.sel] and Side(tool.side)[tool.sel]
    tool.depthBtn:SetEnabled(orn and true or false)
    tool.depthBtn:SetText("Depth: " .. (orn and DEPTH_NAME[orn.layer or "own"] or "-"))
    local ap = not Special(tool.sel) and Side(tool.side)[tool.sel]
    local fixed = ap and ap.a1 == ap.a2
    tool.anchorBtn:SetEnabled(fixed and true or false)
    local warn = HangsWrong(ap)
    tool.anchorBtn:SetText(fixed and ((warn and "|cffff4040" or "") .. ap.a1 .. (warn and "|r" or ""))
        or "Anchor: 2 points")

    local layout, size = Side(tool.side)
    local p = layout[tool.sel]
    for axis, eb in pairs(tool.sizeBoxes) do
        local v
        if tool.sel == PLACE then
            v = (axis == "w") and (w.size.w - w.panelPos.left - w.panelPos.right) or nil
        elseif tool.sel == CONTENT then
            local pad = WorkPad(w)
            v = (axis == "w") and (panel:GetWidth() - pad.left - pad.right) or nil
        else
            local k = ((axis == "h") and size.borderY or size.border) / NATIVE
            v = PieceSize(p, axis, k)
                or (p and StretchSize(p, axis, k, (tool.side == "panel") and panel or bar))
        end
        if not eb:HasFocus() then eb:SetText(v and Num(v) or (Special(tool.sel) and "auto" or "stretch")) end
        eb:SetEnabled(v ~= nil)
        eb:SetTextColor(v and 1 or 0.5, v and 1 or 0.5, v and 1 or 0.5)
    end
    for _, box in ipairs(tool.valueBoxes) do
        if not box.eb:HasFocus() then box.eb:SetText(Num(box.get())) end
    end
    tool.underCb:SetChecked(w.panelPos.under ~= false)
    tool.hlSwatch:SetColorTexture(WorkHL(w)[1], WorkHL(w)[2], WorkHL(w)[3], 1)

    local where = (tool.side == "panel") and "Results panel" or "Search bar"
    if tool.sel == PLACE then
        tool.info:SetText(string.format(
            "|cffffd100%s: placement|r\nLeft %s   Right %s   Gap %s   Width %s\n"
            .. "Left / Right: in from the bar's edges (negative = wider).\nGap: space under the bar (negative = overlap).",
            where, Num(w.panelPos.left), Num(w.panelPos.right), Num(w.panelPos.gap),
            Num(w.size.w - w.panelPos.left - w.panelPos.right)))
    elseif tool.sel == CONTENT then
        local pad = WorkPad(w)
        tool.info:SetText(string.format(
            "|cffffd100%s: content|r\nLeft %s   Right %s   Top %s   Bottom %s\n"
            .. "Where the result rows sit inside the panel art, in from its edges.\n"
            .. "Arrows move them, Alt: top-left edges, Ctrl: bottom-right edges.",
            where, Num(pad.left), Num(pad.right), Num(pad.top), Num(pad.bottom)))
    else
        tool.info:SetText(string.format(
            "|cffffd100%s: %s|r\nTOPLEFT -> %s %s, %s\nBOTTOMRIGHT -> %s %s, %s\n%s",
            where, tool.sel, p.a1, Num(p.x1), Num(p.y1), p.a2, Num(p.x2), Num(p.y2),
            HangsWrong(p)
                and "|cffff4040Hangs from TOP but sits low: will not follow the results. Anchor it to a BOTTOM point.|r"
                or string.format("Art px x border / 32.  Zoom %dx", tool.zoom)))
    end
end

-- mode: nil = move both points, "p1" = top-left only, "p2" = bottom-right only.
-- Placement: both edges, left only (p1) or right only (p2); up / down = gap.
local function Nudge(dx, dy, mode)
    if tool.sel == PLACE then
        local pos = Work().panelPos
        if mode ~= "p2" then pos.left = pos.left + dx end
        if mode ~= "p1" then pos.right = pos.right - dx end
        pos.gap = pos.gap - dy
    elseif tool.sel == CONTENT then
        local pad = WorkPad(Work(), true)
        if mode ~= "p2" then pad.left = pad.left + dx; pad.top = pad.top - dy end
        if mode ~= "p1" then pad.right = pad.right - dx; pad.bottom = pad.bottom + dy end
    else
        local p = Side(tool.side)[tool.sel]
        if mode ~= "p2" then p.x1 = p.x1 + dx; p.y1 = p.y1 + dy end
        if mode ~= "p1" then p.x2 = p.x2 + dx; p.y2 = p.y2 + dy end
    end
    Refresh()
end

local function ModMode()
    if IsAltKeyDown() then return "p1" end
    if IsControlKeyDown() then return "p2" end
    return nil
end

-- Click on a piece button: select it, adding it first when that side does
-- not use it yet.
local function SelectOrAdd(side, key)
    if not Special(key) then
        local layout, _, removed, w = Side(side)
        if not layout[key] then
            local def = BNB.SEARCH_THEMES[BNB.SEARCH_DEFAULT_THEME]
            local src = ADD_DEFAULT[key]
                or (side == "panel" and w.layout[key])
                or (def and def.layout and def.layout[key])
                or { a1 = "CENTER", x1 = -16, y1 = 16, a2 = "CENTER", x2 = 16, y2 = -16 }
            layout[key] = CopyPiece(src)
            removed[key] = nil
        end
    end
    tool.side, tool.sel = side, key
    Refresh()
end

local function CycleDepth()
    local p = ORNAMENTS[tool.sel] and Side(tool.side)[tool.sel]
    if not p then return end
    local cur = p.layer or "own"
    for i, d in ipairs(DEPTHS) do
        if d == cur then cur = DEPTHS[i % #DEPTHS + 1]; break end
    end
    p.layer = (cur ~= "own") and cur or nil
    Refresh()
end

-- Hangs the selected fixed-size piece (both points on one frame point)
-- from the next frame point, with its offsets changed so it stays put.
local ANCHORS = { "TOPLEFT", "TOP", "TOPRIGHT", "RIGHT", "BOTTOMRIGHT", "BOTTOM", "BOTTOMLEFT", "LEFT", "CENTER" }
local function CycleAnchor()
    if Special(tool.sel) then return end
    local layout, size = Side(tool.side)
    local p = layout[tool.sel]
    if not p or p.a1 ~= p.a2 then return end
    local nxt = ANCHORS[1]
    for i, a in ipairs(ANCHORS) do
        if a == p.a1 then nxt = ANCHORS[i % #ANCHORS + 1]; break end
    end
    local host = (tool.side == "panel") and tool.panel or tool.bar
    local w, h = host:GetSize()
    local ox, oy = PointXY(p.a1, w, h)
    local nx, ny = PointXY(nxt, w, h)
    local kx, ky = size.border / NATIVE, size.borderY / NATIVE
    local dx, dy = (ox - nx) / kx, (oy - ny) / ky
    p.x1, p.x2, p.y1, p.y2 = p.x1 + dx, p.x2 + dx, p.y1 + dy, p.y2 + dy
    p.a1, p.a2 = nxt, nxt
    Refresh()
end

local function RemoveSelected()
    if Special(tool.sel) or KEEP[tool.sel] then return end
    local layout, _, removed = Side(tool.side)
    layout[tool.sel] = nil
    removed[tool.sel] = true
    Refresh()
end

-- Border thickness of one side: 2 px a click, 1 px with Shift.
local function Border(side, dir)
    local _, size = Side(side)
    local d = dir * (IsShiftKeyDown() and 1 or 2)
    size.border = math.max(4, math.min(64, size.border + d))
    size.borderY = math.max(4, math.min(64, size.borderY + d))
    Refresh()
end

-- Mouse drag on the bar or the results panel moves the selected piece
-- (Alt/Ctrl as the arrows).
local function HookDrag(frame)
    frame:EnableMouse(true)
    frame:SetScript("OnMouseDown", function(self, btn)
        if btn ~= "LeftButton" then return end
        local s = self:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        self._drag = { x = cx / s, y = cy / s, mode = ModMode(), dx = 0, dy = 0 }
    end)
    frame:SetScript("OnMouseUp", function(self) self._drag = nil end)
    frame:SetScript("OnUpdate", function(self)
        local d = self._drag
        if not d then return end
        local s = self:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        local tx = math.floor(cx / s - d.x + 0.5)
        local ty = math.floor(cy / s - d.y + 0.5)
        if tx ~= d.dx or ty ~= d.dy then
            Nudge(tx - d.dx, ty - d.dy, d.mode)
            d.dx, d.dy = tx, ty
        end
    end)
end

local function BuildTool()
    local f = CreateFrame("Frame", "BNBSearchLayoutTool", UIParent, "BackdropTemplate")
    f:SetSize(TOOL_W, TOOL_H)
    f:SetPoint("LEFT", UIParent, "LEFT", 20, 0)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    f:SetBackdropColor(0.05, 0.05, 0.07, 0.92)
    f:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    tool = f
    f.side, f.sel, f.zoom, f.showHL, f.showAnchor = "bar", "topleft", 1, true, false
    f.theme = BNB.SEARCH_DEFAULT_THEME
    -- Preview result count: 8 is what the Oracle shows on an empty box.
    f.rows = 8

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", TOOL_PAD, -8)
    title:SetWidth(TOOL_W - TOOL_PAD * 2 - 20)
    title:SetJustifyH("LEFT")
    f.title = title

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() f:Hide() end)

    -- The preview: the bar where the Oracle opens, the results panel under
    -- it. Shown and hidden with the tool.
    local bar = CreateFrame("Frame", nil, UIParent)
    bar:SetFrameStrata("DIALOG")
    -- Room below the bar, so the panel can draw under it (panelPos.under).
    bar:SetFrameLevel(BNB.SEARCH_BAR_LEVEL)
    bar:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    bar:SetMovable(true)
    bar:Hide()
    f.bar = bar
    local panel = CreateFrame("Frame", nil, bar)
    f.panel = panel
    HookDrag(bar)
    HookDrag(panel)

    local hl = bar:CreateTexture(nil, "OVERLAY", nil, 7)
    hl:SetColorTexture(1, 0.82, 0, 0.25)
    f.hl = hl

    -- Move anchor above the bar: drags the whole preview, right-click puts
    -- it back in the centre. Toggled with the Move button.
    local anchor = CreateFrame("Button", nil, bar, "BackdropTemplate")
    anchor:SetSize(24, 24)
    anchor:SetPoint("BOTTOM", bar, "TOP", 0, 8)
    anchor:SetFrameLevel(bar:GetFrameLevel() + 20)
    anchor:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    anchor:SetBackdropColor(0, 0, 0, 0.7)
    anchor:SetBackdropBorderColor(1, 0.82, 0, 1)
    local aIcon = anchor:CreateTexture(nil, "ARTWORK")
    aIcon:SetPoint("TOPLEFT", 3, -3)
    aIcon:SetPoint("BOTTOMRIGHT", -3, 3)
    aIcon:SetTexture("Interface\\CURSOR\\UI-Cursor-Move")
    anchor:RegisterForDrag("LeftButton")
    anchor:RegisterForClicks("RightButtonUp")
    anchor:SetScript("OnDragStart", function() bar:StartMoving() end)
    anchor:SetScript("OnDragStop", function() bar:StopMovingOrSizing() end)
    anchor:SetScript("OnClick", function(_, btn)
        if btn ~= "RightButton" then return end
        bar:ClearAllPoints()
        bar:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end)
    anchor:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Move the preview", 1, 1, 1)
        GameTooltip:AddLine("Drag: move bar and results together.\nRight-click: back to the centre.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    anchor:SetScript("OnLeave", function() GameTooltip:Hide() end)
    anchor:Hide()
    f.anchor = anchor

    ------------------------------------------------------------------ layout
    local y = -44
    local INNER_W = TOOL_W - TOOL_PAD * 2

    -- A titled box around a group of controls. Returns a function that
    -- closes the box at the current y.
    local function Group(text)
        local box = CreateFrame("Frame", nil, f, "BackdropTemplate")
        box:SetPoint("TOPLEFT", f, "TOPLEFT", TOOL_PAD - 4, y + 4)
        box:SetWidth(INNER_W + 8)
        box:SetFrameLevel(f:GetFrameLevel())
        box:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        box:SetBackdropColor(1, 1, 1, 0.03)
        box:SetBackdropBorderColor(0.35, 0.35, 0.42, 0.9)
        local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("TOPLEFT", TOOL_PAD, y - 1)
        fs:SetText(text)
        local top = y + 4
        y = y - 20
        return function()
            y = y - 2
            box:SetHeight(top - y)
            y = y - 10
        end
    end

    -- Piece buttons, three to a row.
    local BTN_W = math.floor((INNER_W - 8) / 3)
    f.pieceBtns = {}
    local function PieceButtons(side, keys)
        for n, key in ipairs(keys) do
            local b = CreateFrame("Button", nil, f, BNB.PanelButtonTemplate())
            b:SetSize(BTN_W, 18)
            b:SetPoint("TOPLEFT", TOOL_PAD + ((n - 1) % 3) * (BTN_W + 4), y - math.floor((n - 1) / 3) * 20)
            b:SetNormalFontObject("GameFontHighlightSmall")
            b:SetHighlightFontObject("GameFontHighlightSmall")
            b:SetText(LABEL[key] or key)
            b.side, b.key = side, key
            b.sel = b:CreateTexture(nil, "OVERLAY")
            b.sel:SetPoint("TOPLEFT", -2, 2)
            b.sel:SetPoint("BOTTOMRIGHT", 2, -2)
            b.sel:SetColorTexture(1, 0.82, 0, 0.35)
            b:SetScript("OnClick", function() SelectOrAdd(side, key) end)
            f.pieceBtns[#f.pieceBtns + 1] = b
        end
        y = y - math.ceil(#keys / 3) * 20 - 4
    end

    -- Number boxes: Enter applies a number, Esc puts the value back.
    -- allowNeg: placement offsets may be negative.
    f.valueBoxes = {}
    local function NumBox(anchorTo, x, apply, allowNeg)
        local bg = CreateFrame("Frame", nil, f, "BackdropTemplate")
        bg:SetSize(44, 20)
        bg:SetPoint("LEFT", anchorTo, "RIGHT", x, 0)
        BNB.SetBackdropDark(bg)
        local eb = CreateFrame("EditBox", nil, bg)
        eb:SetAllPoints()
        eb:SetFontObject("GameFontHighlightSmall")
        eb:SetTextInsets(5, 5, 0, 0)
        eb:SetAutoFocus(false)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); Refresh() end)
        eb:SetScript("OnEditFocusLost", function() Refresh() end)
        eb:SetScript("OnEnterPressed", function(self)
            local v = tonumber(self:GetText())
            self:ClearFocus()
            if v and (allowNeg or v > 0) then apply(v) end
            Refresh()
        end)
        return eb, bg
    end
    -- A box showing get() and setting it with set(v).
    local function ValueBox(anchorTo, x, get, set, allowNeg)
        local eb, bg = NumBox(anchorTo, x, set, allowNeg)
        f.valueBoxes[#f.valueBoxes + 1] = { eb = eb, get = get }
        return bg
    end
    local function Label(text, anchorTo, x)
        local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        if anchorTo then fs:SetPoint("LEFT", anchorTo, "RIGHT", x, 0)
        else fs:SetPoint("TOPLEFT", TOOL_PAD + 2, y - 4) end
        fs:SetText(text)
        return fs
    end
    local function SmallBtn(text, anchorTo, x, fn)
        local b = CreateFrame("Button", nil, f, BNB.PanelButtonTemplate())
        b:SetSize(22, 20)
        b:SetPoint("LEFT", anchorTo, "RIGHT", x, 0)
        b:SetText(text)
        b:SetScript("OnClick", fn)
        return b
    end
    local function Row() y = y - 24 end
    local function SizeField(side, key, lo)
        return function() local _, size = Side(side); return size[key] end,
               function(v) local _, size = Side(side); size[key] = math.max(lo, math.floor(v + 0.5)) end
    end
    -- Border W / H of one side, with - and +.
    local function BorderRow(side)
        local l = Label("Border W")
        local g, s = SizeField(side, "border", 4)
        local bx = ValueBox(l, 6, g, s)
        l = Label("H", bx, 8)
        g, s = SizeField(side, "borderY", 4)
        bx = ValueBox(l, 6, g, s)
        local minus = SmallBtn("-", bx, 8, function() Border(side, -1) end)
        SmallBtn("+", minus, 2, function() Border(side, 1) end)
        Row()
    end

    local function Check(text, checked, onClick)
        local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        cb:SetSize(22, 22)
        cb:SetPoint("TOPLEFT", TOOL_PAD, y)
        cb:SetChecked(checked)
        cb:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
        local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        fs:SetText(text)
        y = y - 22
        return cb
    end

    -- Group: the search bar.
    local close1 = Group("Search bar")
    local barKeys = {}
    for _, def in ipairs(PIECES) do
        if OnSide("bar", def) then barKeys[#barKeys + 1] = def.key end
    end
    PieceButtons("bar", barKeys)
    local l = Label("Size     W")
    local g, s = SizeField("bar", "w", 64)
    local bx = ValueBox(l, 6, g, s)
    l = Label("H", bx, 8)
    g, s = SizeField("bar", "h", 16)
    ValueBox(l, 6, g, s)
    Row()
    BorderRow("bar")
    close1()

    -- Group: the results panel, its own pieces and where it sits.
    local close2 = Group("Results panel")
    local panelKeys = { PLACE, CONTENT }
    for _, def in ipairs(PIECES) do
        if OnSide("panel", def) then panelKeys[#panelKeys + 1] = def.key end
    end
    PieceButtons("panel", panelKeys)
    BorderRow("panel")
    local function PosField(key)
        return function() return Work().panelPos[key] end,
               function(v) Work().panelPos[key] = v end
    end
    l = Label("Place   L")
    g, s = PosField("left")
    bx = ValueBox(l, 4, g, s, true)
    l = Label("R", bx, 6)
    g, s = PosField("right")
    bx = ValueBox(l, 4, g, s, true)
    l = Label("Gap", bx, 6)
    g, s = PosField("gap")
    ValueBox(l, 4, g, s, true)
    Row()
    local function PadField(key)
        return function() return WorkPad(Work())[key] end,
               function(v) WorkPad(Work(), true)[key] = v end
    end
    l = Label("Content L")
    g, s = PadField("left")
    bx = ValueBox(l, 4, g, s, true)
    l = Label("R", bx, 6)
    g, s = PadField("right")
    bx = ValueBox(l, 4, g, s, true)
    l = Label("T", bx, 6)
    g, s = PadField("top")
    bx = ValueBox(l, 4, g, s, true)
    l = Label("B", bx, 6)
    g, s = PadField("bottom")
    ValueBox(l, 4, g, s, true)
    Row()
    f.underCb = Check("Results under the search bar where they overlap", true, function(v)
        Work().panelPos.under = v
        Refresh()
    end)
    -- Selected-result colour (the theme's highlight): swatch for the
    -- colour, box for its alpha (0-1). Shown on the preview's first row.
    l = Label("Highlight")
    local sw = CreateFrame("Button", nil, f, "BackdropTemplate")
    sw:SetSize(44, 18)
    sw:SetPoint("LEFT", l, "RIGHT", 6, 0)
    sw:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    sw:SetBackdropColor(0, 0, 0, 1)
    sw:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    f.hlSwatch = sw:CreateTexture(nil, "ARTWORK")
    f.hlSwatch:SetPoint("TOPLEFT", 2, -2)
    f.hlSwatch:SetPoint("BOTTOMRIGHT", -2, 2)
    sw:SetScript("OnClick", function()
        local h = WorkHL(Work(), true)
        local old = { h[1], h[2], h[3] }
        BNB.OpenColorPicker(h[1], h[2], h[3],
            function(r, g, b) h[1], h[2], h[3] = r, g, b; Refresh() end,
            function() h[1], h[2], h[3] = old[1], old[2], old[3]; Refresh() end)
    end)
    l = Label("Alpha", sw, 10)
    ValueBox(l, 4, function() return WorkHL(Work())[4] end,
        function(v) WorkHL(Work(), true)[4] = math.max(0, math.min(1, v)) end)
    Row()
    close2()

    -- Group: the selected piece.
    local close3 = Group("Selected piece")
    local info = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    info:SetPoint("TOPLEFT", TOOL_PAD + 2, y)
    info:SetWidth(INNER_W - 4)
    info:SetHeight(56)
    info:SetJustifyH("LEFT")
    info:SetJustifyV("TOP")
    f.info = info
    y = y - 60

    -- Size in screen pixels. The edge that hangs off the frame stays put; on
    -- a stretching axis the piece grows from its centre and keeps stretching. Placement: the panel's
    -- width (its right edge moves), height is automatic.
    f.sizeBoxes, f.linkSizes = {}, true
    local function PieceApply(axis)
        return function(px)
            if tool.sel == PLACE then
                local w = Work()
                if axis == "w" then w.panelPos.right = w.size.w - w.panelPos.left - px end
                return
            end
            -- Content: the width, evenly from both sides.
            if tool.sel == CONTENT then
                if axis == "w" then
                    local pad = WorkPad(Work(), true)
                    local d = (tool.panel:GetWidth() - pad.left - pad.right - px) / 2
                    pad.left, pad.right = pad.left + d, pad.right + d
                end
                return
            end
            local layout, size = Side(tool.side)
            local k = ((axis == "h") and size.borderY or size.border) / NATIVE
            -- An ornament with Keep square: both sides take px and it grows
            -- from its centre, so it stays put while it changes size.
            local ep = layout[tool.sel]
            local def = PieceDef(tool.sel)
            local isOrnament = tool.sel == "ornament" or (def and def.panelOnly)
            if isOrnament and f.keepSquare and FixedSide(ep, "w") and FixedSide(ep, "h") then
                local kx, ky = size.border / NATIVE, size.borderY / NATIVE
                local cx, cy = (ep.x1 + ep.x2) / 2, (ep.y1 + ep.y2) / 2
                local hw, hh = px / kx / 2, px / ky / 2
                ep.x1, ep.x2, ep.y1, ep.y2 = cx - hw, cx + hw, cy + hh, cy - hh
                return
            end
            -- A stretching piece (the background, an edge along its
            -- length): only this one, from its centre.
            if not FixedSide(ep, axis) then
                SetStretchSize(ep, axis, px, k, (tool.side == "panel") and tool.panel or tool.bar)
                return
            end
            local grp = GROUPS[tool.sel]
            for key, pp in pairs(layout) do
                if key == tool.sel or (f.linkSizes and grp and GROUPS[key] == grp) then
                    if FixedSide(pp, axis) then SetPieceSize(pp, axis, px, k) end
                end
            end
        end
    end
    l = Label("Size     W")
    local e
    e, bx = NumBox(l, 6, PieceApply("w"));    f.sizeBoxes.w = e
    l = Label("H", bx, 8)
    e, bx = NumBox(l, 6, PieceApply("h"));    f.sizeBoxes.h = e
    local rm = CreateFrame("Button", nil, f, BNB.PanelButtonTemplate())
    rm:SetSize(64, 20)
    rm:SetPoint("LEFT", bx, "RIGHT", 8, 0)
    rm:SetText("Remove")
    rm:SetScript("OnClick", RemoveSelected)
    f.removeBtn = rm
    Row()
    -- Two half-width buttons: the ornament's depth and the point a piece
    -- hangs from.
    local HALF = math.floor((INNER_W - 4) / 2)
    local function HalfBtn(x, fn, tipTitle, tip)
        local b = CreateFrame("Button", nil, f, BNB.PanelButtonTemplate())
        b:SetSize(HALF, 20)
        b:SetPoint("TOPLEFT", TOOL_PAD + x, y)
        b:SetNormalFontObject("GameFontHighlightSmall")
        b:SetHighlightFontObject("GameFontHighlightSmall")
        b:SetDisabledFontObject("GameFontDisableSmall")
        b:SetScript("OnClick", fn)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(tipTitle, 1, 1, 1)
            GameTooltip:AddLine(tip, 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return b
    end
    f.depthBtn = HalfBtn(0, CycleDepth, "Ornament depth",
        "Over borders: the piece's own place.\nBehind borders: over the background only."
        .. "\nOver everything: over the other frame, the text and the rows too.")
    f.anchorBtn = HalfBtn(HALF + 4, CycleAnchor, "Anchor",
        "The frame point the piece hangs from. It stays where it is when you change it. "
        .. "Hang a piece from the edge it should follow: a results ornament near the bottom "
        .. "from a BOTTOM point, or it moves as the results grow and shrink.")
    Row()

    Check("Same size for matching pieces", true, function(v) f.linkSizes = v end)
    f.keepSquare = true
    Check("Ornaments: keep square", true, function(v) f.keepSquare = v end)
    close3()

    local help = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", TOOL_PAD, y)
    help:SetWidth(INNER_W)
    help:SetJustifyH("LEFT")
    help:SetText("Arrows / drag: move.  Alt: top-left point only, Ctrl: bottom-right point "
        .. "only (resize).  Shift: 5 px.  Tab: next piece.  Dimmed button: not used, click to add.  "
        .. "Placement: arrows move the panel, Alt / Ctrl one edge, up / down the gap.  "
        .. "Content: where the rows sit inside the panel; W sets their width.  "
        .. "Rows: check that results pieces follow the panel as it grows.")

    -- Tool buttons, four to a row from the bottom up.
    local BW = math.floor((INNER_W - 12) / 4)
    local btnN = 0
    local function Btn(label, fn)
        local b = CreateFrame("Button", nil, f, BNB.PanelButtonTemplate())
        b:SetSize(BW, 20)
        local row, col = math.floor(btnN / 4), btnN % 4
        b:SetPoint("BOTTOMLEFT", TOOL_PAD + col * (BW + 4), 8 + (1 - row) * 24)
        b:SetText(label)
        b:SetScript("OnClick", fn)
        btnN = btnN + 1
        return b
    end
    -- Theme: steps through BNB.SEARCH_THEME_ORDER; each keeps its own copy.
    -- Backdrop themes have no pieces to place and are skipped (ALL-69.5).
    local function DrawnThemes()
        local order = {}
        for _, id in ipairs(BNB.SEARCH_THEME_ORDER) do
            if not IsBackdrop(BNB.SEARCH_THEMES[id]) then order[#order + 1] = id end
        end
        return order
    end
    local themeBtn = Btn("Theme", function()
        local order = DrawnThemes()
        for i, id in ipairs(order) do
            if id == f.theme then f.theme = order[i % #order + 1]; break end
        end
        Refresh()
    end)
    themeBtn:SetEnabled(#DrawnThemes() > 1)
    Btn("Zoom", function()
        f.zoom = (f.zoom % 3) + 1
        bar:SetScale(f.zoom)
        Refresh()
    end)
    Btn("Highlight", function() f.showHL = not f.showHL; Refresh() end)
    Btn("Move", function() f.showAnchor = not f.showAnchor; Refresh() end)
    local ROW_STEPS = { 8, 5, 3, 1 }
    local rowsBtn
    rowsBtn = Btn("Rows: 8", function()
        for i, n in ipairs(ROW_STEPS) do
            if n == f.rows then f.rows = ROW_STEPS[i % #ROW_STEPS + 1]; break end
        end
        rowsBtn:SetText("Rows: " .. f.rows)
        Refresh()
    end)
    Btn("Reset", function()
        local db = BNB.LabDB()
        if db.devSearch then db.devSearch[f.theme] = nil end
        Refresh()
    end)
    Btn("Export", function() BNB.ShowClipboardHint(ExportText(), f, true) end)

    -- Keys: handled ones are swallowed, the rest propagate.
    BNB.RegisterKeyboardFrame(f)
    f:EnableKeyboard(true)
    f:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end
        local step = IsShiftKeyDown() and 5 or 1
        local mode = ModMode()
        local _, size = Side("bar")
        local handled = true
        if key == "LEFT" then Nudge(-step, 0, mode)
        elseif key == "RIGHT" then Nudge(step, 0, mode)
        elseif key == "UP" then Nudge(0, step, mode)
        elseif key == "DOWN" then Nudge(0, -step, mode)
        elseif key == "TAB" then
            -- Next (Shift: previous) used piece: the bar's, then the panel's.
            local used = UsedList()
            for i, it in ipairs(used) do
                if it[1] == f.side and it[2] == f.sel then
                    local nx = used[IsShiftKeyDown() and (i - 2) % #used + 1 or i % #used + 1]
                    f.side, f.sel = nx[1], nx[2]
                    break
                end
            end
            Refresh()
        elseif key == "HOME" then size.w = math.max(64, size.w - step * 10); Refresh()
        elseif key == "END" then size.w = size.w + step * 10; Refresh()
        elseif key == "PAGEDOWN" then size.h = math.max(32, size.h - step); Refresh()
        elseif key == "PAGEUP" then size.h = size.h + step; Refresh()
        elseif key == "ESCAPE" then f:Hide()
        else handled = false end
        self:SetPropagateKeyboardInput(not handled)
    end)

    -- Sample text in the input region, so its placement can be judged too.
    local sample = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    sample:SetJustifyH("LEFT")
    sample:SetText("Search notes...")
    local w0 = Work()
    BNB.ApplySearchChrome(bar, f.theme, w0.layout, w0.size)
    sample:SetPoint("LEFT", bar._searchPieces.text, "LEFT", 0, 0)
    sample:SetPoint("RIGHT", bar._searchPieces.text, "RIGHT", 0, 0)

    f:SetScript("OnShow", function() bar:Show(); Refresh() end)
    f:SetScript("OnHide", function() bar:Hide() end)
    f:Hide()   -- so the first Show runs OnShow
end

function BNB.ToggleSearchLayoutTool()
    if not tool then
        BuildTool()
        tool:Show()
        return
    end
    tool:SetShown(not tool:IsShown())
end

end

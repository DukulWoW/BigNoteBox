-- BigNoteBox UI/HelpBook.lua - the help book (ALL-554)
--
-- The help topics (UI/HelpData.lua, the same text as the Help folder) in a
-- window of their own, so a new player has somewhere to start: the table of
-- contents on the narrow parchment, the page on the wide one, a cover first
-- (logo.tga), Previous / Next along the bottom. Decided with Dukul,
-- 2026-10-23: Blizzard's Neutral frame kit (the wood "table" tile behind,
-- UI-Frame-Neutral-CardParchment / -CardParchmentWider, the vertical edge as
-- the divider, the Neutral nine-slice border and title), fixed size ("the doc
-- window shouldn't be resizeable"). Skin mode has its own version (Dukul,
-- 2026-10-23): a skin window, Contents and page as two skin panels, white
-- text, accent headings; the same pages and controls. Retail and
-- Forever first; Classic waits on Dukul's art check. Later stages: chapters
-- from doc-mode folders, the "?" icons and help links open it, the patch
-- notes move in.
--
-- The page is dark ink on parchment: the topic markup is the same as in a
-- note, so the book swaps the light link colours for darker ones and tints
-- the white Assets art (toolbar, explorer, doc icons) brown (Parchment).
--
-- Public API:
--   BNB.HelpBook.Open(key)   opens the book at that topic (nil = the cover)
--   BNB.HelpBook.Close()
--   BNB.HelpBook.Toggle()

local BNB = BigNoteBox
local L   = BNB.L

local HB = {}
BNB.HelpBook = HB

local LOGO = "Interface\\AddOns\\BigNoteBox\\Assets\\logo"

-- Sizes in window pixels. The parchments keep the shape of their art
local PARCH_H  = 500
local TOC_W    = math.floor(254 / 439 * PARCH_H + 0.5)   -- CardParchment 254 x 439
local PAGE_W   = math.floor(515 / 438 * PARCH_H + 0.5)   -- CardParchmentWider 515 x 438
local ROW_H    = 22
local SEARCH_H = 22

-- Where things sit, per look. Book: inside the wooden border and the burnt
-- parchment edges, under the shaded tops. Skin: a skin window's title strip
-- and plain panels, smaller (Dukul, 2026-10-23: Contents only as wide as its
-- longest topic, "No need having it as big"). search = the search box's top,
-- tocHead = "Contents" under it, tocList = the list
local LAYOUTS = {
    book = { side = 26, gap = 16, top = 100, bottom = 26,
             tocW = TOC_W, pageW = PAGE_W, paneH = PARCH_H,
             search = -60, tocHead = -92, tocList = -124, tocX = 30, tocR = -40, tocB = 34,
             pageX = 44, pageTop = -64, pageR = -56, pageB = 54,
             footX = 44, footR = -52, footY = 22, noY = 27, logo = 220, logoY = -48 },
    skin = { side = 10, gap = 10, top = 38, bottom = 10,
             tocW = 190, pageW = 500, paneH = 440,
             search = -10, tocHead = -42, tocList = -72, tocX = 12, tocR = -24, tocB = 10,
             pageX = 18, pageTop = -18, pageR = -30, pageB = 44,
             footX = 12, footR = -12, footY = 10, noY = 15, logo = 180, logoY = -36 },
}
local LAY            -- the layout in use, set at build
local C = {}         -- the colours in use (head, title, body, pick, hover), set at build

-- Darker than a note's text: the top of each parchment is shaded (first
-- test, 2026-10-23: "text is hard to read")
local INK_HEAD = { 0.22, 0.11, 0.02 }
-- "Contents" and the page titles sit on the shaded top of the parchment:
-- a red-brown that stands out there (second test, 2026-10-23: "too dark")
local INK_TITLE = { 0.48, 0.11, 0.02 }
-- The title plate's text: warm parchment gold, the wood's colour (the BNB
-- header green did not match it, Dukul 2026-10-23)
local PLATE_TEXT = { 0.98, 0.86, 0.58 }
-- Scroll bars in the wood's brown (the game's blue-grey bar did not match)
local BAR_TINT = { 0.55, 0.36, 0.18 }
local INK_BODY = { 0.13, 0.08, 0.03 }
local INK_PICK = { 0.52, 0.08, 0.00 }

-- Blizzard's WoodenNeutralFrameTemplate (Blizzard_SharedXML/Mainline/
-- NineSliceLayouts.lua, used by the Chromie Time window), copied so a client
-- without that entry still gets it: full size, corners 6 px outside, the
-- bottom and right edges have their own art (not mirrored)
local BORDER = {
    mirrorLayout = true,
    TopLeftCorner     = { atlas = "Neutral-NineSlice-Corner", x = -6, y = 6 },
    TopRightCorner    = { atlas = "Neutral-NineSlice-Corner", x = 6,  y = 6 },
    BottomLeftCorner  = { atlas = "Neutral-NineSlice-Corner", x = -6, y = -6 },
    BottomRightCorner = { atlas = "Neutral-NineSlice-Corner", x = 6,  y = -6 },
    TopEdge    = { atlas = "_Neutral-NineSlice-EdgeTop" },
    BottomEdge = { atlas = "_Neutral-NineSlice-EdgeBottom", mirrorLayout = false },
    LeftEdge   = { atlas = "!Neutral-NineSlice-EdgeLeft" },
    RightEdge  = { atlas = "!Neutral-NineSlice-EdgeRight", mirrorLayout = false },
}

-- Link colours on parchment: the note colours are made for a dark page
local INK_SWAP = {
    ["|cff66d966"] = "|cff1d5e12",   -- waypoints, plain links: green
    ["|cff6cb4ee"] = "|cff1a4f8a",   -- note links: blue
    ["|cffffcc33"] = "|cff7a4a00",   -- BigNoteBox links: gold
    ["|cff808080"] = "|cff6b6157",   -- a link to a place this setup does not have
}
-- Assets folders whose art is white (drawn brown here); the rest has its own colours
local WHITE_ART = { Toolbar = true, Explorer = true, Documentation = true }

local frame, coverFont
local topics = {}
local hay = {}             -- hay[i] = topics[i]'s title and text, plain and lower case (search)
local current = 0          -- 0 = the cover, i = topics[i]
local gen = { n = 0 }      -- drops a render a newer page replaced

-- The quest log's text font: made for dark ink on parchment, and the
-- client's own font in every language
local function BookFont()
    return _G.QuestFont or BNBFontNormal
end
local function TitleFont()
    return _G.QuestTitleFont or BNBFontNormalLarge
end

-- The page's own font objects, made once from the quest log font: no shadow,
-- never the note font (heavy on parchment, second test 2026-10-23). Bound to
-- the render frame once at build, never per render (FOR-30)
local pageFonts
local function PageFonts()
    if pageFonts then return pageFonts end
    pageFonts = {}
    for tag, size in pairs({ p = 14, h1 = 21, h2 = 18, h3 = 16 }) do
        local fo = CreateFont("BNBHelpBookFont_" .. tag)
        fo:CopyFontObject(BookFont())
        local path, _, flags = fo:GetFont()
        if path then fo:SetFont(path, size, flags or "") end
        fo:SetShadowOffset(0, 0)
        pageFonts[tag] = fo
    end
    return pageFonts
end

-- The colours of the look in use: dark ink on parchment, or the skin's
-- white text and accent headings
local function SetLook(skin)
    LAY = skin and LAYOUTS.skin or LAYOUTS.book
    if skin then
        local hr, hg, hb = BNB.HeaderColor()
        local wr, wg, wb = BNB.TextWhite(0.90)
        C.head, C.title, C.pick = { hr, hg, hb }, { hr, hg, hb }, { hr, hg, hb }
        C.body = { wr, wg, wb }
        C.hover = { 1, 1, 1, 0.08 }
    else
        C.head, C.title, C.pick, C.body = INK_HEAD, INK_TITLE, INK_PICK, INK_BODY
        C.hover = { 0.45, 0.28, 0.10, 0.10 }
    end
    C.skin = skin
end

local function Ink(fs, c)
    fs:SetTextColor(c[1], c[2], c[3])
    fs:SetShadowOffset(0, 0)
end

local function Parchment(html)
    html = html:gsub("|c(%x%x%x%x%x%x%x%x)", function(c)
        return INK_SWAP["|c" .. c:lower()]
    end)
    html = html:gsub("|T(Interface\\AddOns\\BigNoteBox\\Assets\\(%a+)\\[^:|]+):(%d+):(%d+)|t",
        function(path, folder, h, w)
            if not WHITE_ART[folder] then return nil end
            return string.format("|T%s:%s:%s:0:0:64:64:0:64:0:64:90:58:26|t", path, h, w)
        end)
    return html
end

-- ── Art ──────────────────────────────────────────────────────────────────────

-- The wooden border, by Blizzard's own nine-slice code (the shrunken
-- hand-made one showed seams, first test 2026-10-23). Over the parchments
local function BuildBorder(f)
    local ns = CreateFrame("Frame", nil, f)
    ns:SetAllPoints(f)
    ns:SetFrameLevel(f:GetFrameLevel() + 20)
    if NineSliceUtil and NineSliceUtil.ApplyLayout then
        pcall(NineSliceUtil.ApplyLayout, ns, BORDER)
    end
    return ns
end

-- The title plate across the top, as the Chromie Time window has it: the two
-- ends at their own size, the middle tiled under them, 60 px into each end
local function BuildTitle(f)
    local tf = CreateFrame("Frame", nil, f)
    tf:SetHeight(85)
    tf:SetPoint("TOPLEFT",  f, "TOPLEFT",  30, -25)
    tf:SetPoint("TOPRIGHT", f, "TOPRIGHT", -30, -25)
    tf:SetFrameLevel(f:GetFrameLevel() + 25)
    local lft = tf:CreateTexture(nil, "BACKGROUND")
    lft:SetAtlas("UI-Frame-Neutral-TitleLeft", true)
    lft:SetPoint("LEFT", tf, "LEFT")
    local rgt = tf:CreateTexture(nil, "BACKGROUND")
    rgt:SetAtlas("UI-Frame-Neutral-TitleRight", true)
    rgt:SetPoint("RIGHT", tf, "RIGHT")
    local mid = tf:CreateTexture(nil, "BACKGROUND", nil, -1)
    mid:SetAtlas("_UI-Frame-Neutral-TitleMiddle")
    mid:SetHorizTile(true)
    mid:SetHeight(85)
    mid:SetPoint("LEFT",  lft, "RIGHT", -60, 0)
    mid:SetPoint("RIGHT", rgt, "LEFT",  60,  0)

    local fs = tf:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(_G.SystemFont_Large or BNBFontNormalLarge)
    fs:SetPoint("CENTER", mid, "CENTER", 0, 0)
    fs:SetTextColor(PLATE_TEXT[1], PLATE_TEXT[2], PLATE_TEXT[3])
    f._artTitle = fs
    fs:SetText(L["HELP_BOOK_TITLE"])
    return tf
end

local function Parch(f, atlas, w)
    local p = CreateFrame("Frame", nil, f)
    p:SetSize(w, PARCH_H)
    local bg = p:CreateTexture(nil, "BACKGROUND", nil, 2)
    bg:SetAllPoints(p)
    bg:SetAtlas(atlas)
    return p
end

-- ── Table of contents ────────────────────────────────────────────────────────

-- The row in list slot `slot` (0 = the top); row._i is the page it opens
local function TocRow(slot)
    local toc = frame._tocChild
    local row = frame._rows[slot + 1]
    if row then return row end
    row = CreateFrame("Button", nil, toc)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT",  toc, "TOPLEFT",  0, -slot * ROW_H)
    row:SetPoint("TOPRIGHT", toc, "TOPRIGHT", 0, -slot * ROW_H)
    -- Hover only: the open topic is marked by its colour (a fill drew a hard
    -- edge on the shaded parchment, first test 2026-10-23)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(row)
    hl:SetColorTexture(C.hover[1], C.hover[2], C.hover[3], C.hover[4])
    row._fs = row:CreateFontString(nil, "OVERLAY")
    row._fs:SetFontObject(BookFont())
    row._fs:SetPoint("LEFT", row, "LEFT", 6, 0)
    row._fs:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row._fs:SetJustifyH("LEFT")
    row._fs:SetWordWrap(false)
    row._i = 0
    row:SetScript("OnClick", function(self) HB.ShowPage(self._i) end)
    frame._rows[slot + 1] = row
    return row
end

-- A topic's searchable text: title and body without markup, lower case
local function Haystack(t)
    local title, body = BNB.HelpTopicText(t)
    local s = (title or "") .. "\n" .. (body or "")
    s = s:gsub("|T.-|t", " ")
         :gsub("|H.-|h(.-)|h", "%1")
         :gsub("|c%x%x%x%x%x%x%x%x", "")
         :gsub("|r", "")
         :gsub("{[^}]*}", " ")
    return s:lower()
end

-- The search box's words, lower case; empty = no search
local function SearchWords()
    local eb = frame._search
    local q = eb and eb.GetRealText and eb:GetRealText() or ""
    local words = {}
    for w in q:lower():gmatch("%S+") do words[#words + 1] = w end
    return words
end

-- Every word must be in the topic, anywhere in its title or text
local function Matches(i, words)
    local h = hay[i]
    if not h then h = Haystack(topics[i]); hay[i] = h end
    for _, w in ipairs(words) do
        if not h:find(w, 1, true) then return false end
    end
    return true
end

local MarkToc

-- The list: every topic, or while searching only the topics that have the
-- words (Dukul, 2026-10-23). No Cover row: the book opens on the cover, and
-- Previous on the first topic goes back to it (Dukul: "remove Cover")
local function FillToc()
    local words = SearchWords()
    local pages = {}
    for i = 1, #topics do
        if #words == 0 or Matches(i, words) then pages[#pages + 1] = i end
    end
    for slot, i in ipairs(pages) do
        local row = TocRow(slot - 1)
        row._i = i
        row._fs:SetText((BNB.HelpTopicText(topics[i])))
        row:Show()
    end
    for k = #pages + 1, #frame._rows do frame._rows[k]:Hide() end
    frame._noMatch:SetShown(#words > 0 and #pages == 0)
    frame._tocPages = pages
    frame._tocChild:SetHeight(math.max(1, #pages * ROW_H))
    frame._tocScroll:SetVerticalScroll(0)
    MarkToc()
end

function MarkToc()
    local slot
    for k, row in ipairs(frame._rows) do
        local on = row:IsShown() and row._i == current
        if on then slot = k - 1 end
        Ink(row._fs, on and C.pick or C.body)
    end
    -- Keep the open topic in view, when the list shows it
    if not slot then return end
    local sf = frame._tocScroll
    local y, viewH = slot * ROW_H, sf:GetHeight()
    local s = sf:GetVerticalScroll()
    if y < s then sf:SetVerticalScroll(y)
    elseif y + ROW_H > s + viewH then sf:SetVerticalScroll(math.max(0, y + ROW_H - viewH)) end
end

-- ── The page ─────────────────────────────────────────────────────────────────

-- Next frame: a SimpleHTML's width is never set while the client lays out
-- (FOR-30), and a newer page drops this one
local function RenderTopic(t)
    gen.n = gen.n + 1
    local my = gen.n
    C_Timer.After(0, function()
        if my ~= gen.n or not frame:IsShown() then return end
        local AM = BNB.AdvancedMode
        local sf, hold, rf, pfs = frame._pageScroll, frame._hold, frame._rf, frame._pfs
        local w = sf:GetWidth()
        if not (w and w > 0) then w = LAY.pageW - 100 end
        hold:SetWidth(w)
        local _, body = BNB.HelpTopicText(t)
        if t.rich and AM then
            pfs:Hide(); rf:Show()
            rf:SetWidth(w)
            local rawST = getmetatable(rf).__index.SetText
            local html = AM.ToHTML(body)
            if not C.skin then html = Parchment(html) end
            rawST(rf, html)
            local h = rf:GetContentHeight()
            rf:SetHeight(h)
            hold:SetHeight(h + 8)
        else
            -- A plain topic (Rich notes, Note tokens): its markup shows as typed
            rf:Hide(); pfs:Show()
            pfs:SetWidth(w)
            pfs:SetText(body)
            hold:SetHeight(pfs:GetStringHeight() + 8)
        end
        sf:SetVerticalScroll(0)
    end)
end

function HB.ShowPage(i)
    if not frame then return end
    local n = #topics
    current = math.max(0, math.min(i or 0, n))
    local cover = current == 0
    frame._cover:SetShown(cover)
    frame._topic:SetShown(not cover)
    if cover then
        gen.n = gen.n + 1
        frame._pageNo:SetText(L["HELP_BOOK_COVER"])
        frame:SetWindowTitle(L["HELP_BOOK_TITLE"])
    else
        local t = topics[current]
        -- The topic's name goes on the title plate, not on the page (Dukul,
        -- 2026-10-23: "Writing Notes - BigNoteBox Help")
        frame:SetWindowTitle(string.format(L["HELP_BOOK_TITLE_FMT"], (BNB.HelpTopicText(t))))
        frame._pageNo:SetText(string.format(L["HELP_BOOK_PAGE_FMT"], current, n))
        RenderTopic(t)
    end
    frame._prev:SetEnabled(current > 0)
    frame._next:SetEnabled(current < n)
    MarkToc()
end

-- A help topic by key; false when this client has no such topic
function HB.ShowKey(key)
    for i, t in ipairs(topics) do
        if t.key == key then HB.ShowPage(i); return true end
    end
    return false
end

-- ── Build ────────────────────────────────────────────────────────────────────

local function BuildCover(page)
    local cv = CreateFrame("Frame", nil, page)
    cv:SetAllPoints(page)
    local logo = cv:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(LOGO)
    logo:SetSize(LAY.logo, LAY.logo)
    logo:SetPoint("TOP", cv, "TOP", 0, LAY.logoY)

    if not coverFont then
        coverFont = CreateFont("BNBHelpBookCoverFont")
        coverFont:CopyFontObject(TitleFont())
        local path, _, flags = coverFont:GetFont()
        if path then coverFont:SetFont(path, 30, flags or "") end
    end
    local name = cv:CreateFontString(nil, "OVERLAY")
    name:SetFontObject(coverFont)
    name:SetPoint("TOP", logo, "BOTTOM", 0, -10)
    name:SetText("BigNoteBox")
    Ink(name, C.head)

    local sub = cv:CreateFontString(nil, "OVERLAY")
    sub:SetFontObject(TitleFont())
    sub:SetPoint("TOP", name, "BOTTOM", 0, -6)
    sub:SetText(L["HELP_BOOK_SUB"])
    Ink(sub, C.body)

    local ver = cv:CreateFontString(nil, "OVERLAY")
    ver:SetFontObject(BookFont())
    ver:SetPoint("TOP", sub, "BOTTOM", 0, -8)
    ver:SetText(string.format(L["HELP_BOOK_VERSION_FMT"], tostring(BNB.ADDON_VERSION or "")))
    Ink(ver, C.body)

    local hint = cv:CreateFontString(nil, "OVERLAY")
    hint:SetFontObject(BookFont())
    hint:SetPoint("TOP", ver, "BOTTOM", 0, -24)
    hint:SetWidth(LAY.pageW - 140)
    hint:SetJustifyH("CENTER")
    Ink(hint, C.body)
    cv._hint = hint
    return cv
end

local function BuildTopic(page)
    local tp = CreateFrame("Frame", nil, page)
    tp:SetAllPoints(page)
    -- The text starts under the parchment's shaded top
    local sf = BNB.CreateScrollFrame(nil, tp)
    sf:SetPoint("TOPLEFT",     tp, "TOPLEFT",     LAY.pageX, LAY.pageTop)
    sf:SetPoint("BOTTOMRIGHT", tp, "BOTTOMRIGHT", LAY.pageR, LAY.pageB)
    local bar = sf.ScrollBar
    if bar then
        -- Skin mode: CreateScrollFrame tinted it to the skin already
        if not C.skin and BNB.TintScrollBarFixed then BNB.TintScrollBarFixed(bar, BAR_TINT[1], BAR_TINT[2], BAR_TINT[3]) end
        bar:SetAlpha(0)
        sf:HookScript("OnScrollRangeChanged", function(_, _, yRange)
            bar:SetAlpha((yRange or 0) > 1 and 1 or 0)
        end)
    end
    local hold = CreateFrame("Frame", nil, sf)
    hold:SetSize(LAY.pageW - 100, 1)
    sf:SetScrollChild(hold)

    local rf = BNB.AdvancedMode.CreateRenderFrame(nil, hold)
    rf:SetPoint("TOPLEFT", hold, "TOPLEFT", 0, 0)
    rf:SetWidth(LAY.pageW - 100)
    rf:SetHeight(1)
    for tag, fo in pairs(PageFonts()) do
        rf:SetFontObject(tag, fo)
        local c = tag == "p" and C.body or C.head
        rf:SetTextColor(tag, c[1], c[2], c[3])
        if rf.SetSpacing then pcall(rf.SetSpacing, rf, tag, 3) end
    end
    -- Links between topics turn the page instead of opening the main window
    local orig = rf:GetScript("OnHyperlinkClick")
    rf:SetScript("OnHyperlinkClick", function(self, link, text, button)
        if button == "LeftButton" and type(link) == "string" then
            local key = link:match("^bnbnote:sys%-help%-(.+)$") or link:match("^bnbui:help%.(.+)$")
            if key and HB.ShowKey(key) then return end
        end
        if orig then orig(self, link, text, button) end
    end)

    local pfs = hold:CreateFontString(nil, "OVERLAY")
    pfs:SetFontObject(PageFonts().p)
    pfs:SetSpacing(3)
    pfs:SetPoint("TOPLEFT", hold, "TOPLEFT", 0, 0)
    pfs:SetJustifyH("LEFT")
    pfs:SetJustifyV("TOP")
    pfs:SetWordWrap(true)
    Ink(pfs, C.body)

    frame._pageScroll, frame._hold, frame._rf, frame._pfs = sf, hold, rf, pfs
    return tp
end

-- The skin window's backdrop draws its colour 3 px in from the edge, and so
-- does the title strip's: the side panel starts where the strip's colour ends
local SKIN_INSET = 3

-- A pane: a parchment (book). Skin (Dukul, 2026-10-23): Contents is a side
-- panel from the title strip down to the bottom and the left edge, darker than
-- the window ("so it doesn't blend with the title bar"); the page has no
-- panel of its own, it is the window
local function Pane(f, atlas, w, side)
    if C.skin and side then
        local p = CreateFrame("Frame", nil, f)
        p:SetPoint("TOPLEFT",    f, "TOPLEFT",    SKIN_INSET, -(BNB.TOOL_SKIN_TITLE_H - SKIN_INSET))
        p:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", SKIN_INSET, SKIN_INSET)
        p:SetWidth(LAY.side + w - SKIN_INSET)
        local shade = p:CreateTexture(nil, "BACKGROUND")
        shade:SetAllPoints(p)
        shade:SetColorTexture(0, 0, 0, 0.28)
        return p
    elseif C.skin then
        local p = CreateFrame("Frame", nil, f)
        p:SetSize(w, LAY.paneH)
        return p
    end
    return Parch(f, atlas, w)
end

-- The search box over Contents: dark in skin mode, a faint brown wash with
-- dark ink on parchment
local function BuildSearch(toc)
    local bg = BNB.CreateBackdropFrame("Frame", nil, toc)
    if C.skin then
        BNB.SetBackdropDark(bg)
    else
        BNB.SetBackdrop(bg, 0.45, 0.28, 0.10, 0.12, 0.40, 0.24, 0.08, 0.9)
    end
    bg:SetPoint("TOPLEFT",  toc, "TOPLEFT",  LAY.tocX, LAY.search)
    bg:SetPoint("TOPRIGHT", toc, "TOPRIGHT", LAY.tocR + 18, LAY.search)
    bg:SetHeight(SEARCH_H)
    local eb = CreateFrame("EditBox", nil, bg)
    eb:SetAllPoints()
    eb:SetTextInsets(7, 22, 0, 0)
    eb:SetFontObject(BookFont())
    eb:SetShadowOffset(0, 0)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(64)
    BNB.AddPlaceholder(eb, L["HELP_BOOK_SEARCH"], 0.45, 0.45, 0.45)
    if not C.skin then eb.SetRealColor(eb, { r = C.body[1], g = C.body[2], b = C.body[3] }) end
    -- Enter opens the first topic found
    eb:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        local pages = frame._tocPages
        if pages and pages[1] and #SearchWords() > 0 then HB.ShowPage(pages[1]) end
    end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- The X empties the search (Dukul, 2026-10-23: "it's missing a X to
    -- clear it"); shown only while there is something to clear
    local x = BNB.CreateIconButton(bg, 16, "close", {
        skin = C.skin, tip = L["CFG_SEARCH_CLEAR"],
        onClick = function() eb:ClearFocus(); eb.SetRealText(eb, "") end,
    })
    x:SetPoint("RIGHT", bg, "RIGHT", -4, 0)
    x:SetFrameLevel(eb:GetFrameLevel() + 2)
    x:Hide()

    eb:SetScript("OnTextChanged", function(self)
        x:SetShown(not self._showingPlaceholder and self:GetText() ~= "")
        if self._showingPlaceholder then return end
        FillToc()
    end)
    return eb
end

local function Build()
    if frame then return frame end
    -- Skin mode is read once: switching it reloads the UI
    SetLook(BigNoteBoxDB and BigNoteBoxDB.skinMode and true or false)
    local winW = LAY.side + LAY.tocW + LAY.gap + LAY.pageW + LAY.side
    local winH = LAY.top + LAY.paneH + LAY.bottom
    local f = BNB.CreateToolWindow({
        name = "BigNoteBoxHelpBook", w = winW, h = winH, art = not C.skin,
        title = L["HELP_BOOK_TITLE"], toplevel = true, escClose = true, keyEsc = true,
        -- The main window's strata: clicking either brings it to the front
        -- (Dukul, 2026-10-23: "the window shouldn't always on top")
        strata = "MEDIUM",
    })
    frame = f
    f._rows = {}

    if not C.skin then
        -- The table: the wood tile under everything, inset as Chromie Time's
        local tbl = f:CreateTexture(nil, "BACKGROUND", nil, -2)
        tbl:SetPoint("TOPLEFT", f, "TOPLEFT", 9, -9)
        tbl:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -9, 9)
        tbl:SetAtlas("UI-Frame-Neutral-BackgroundTile")
        tbl:SetHorizTile(true)
        tbl:SetVertTile(true)

        BuildBorder(f)
        BuildTitle(f)

        -- Close: our X in the kit's ring, on the top right corner (Chromie Time's spot)
        local close = BNB.CreateIconButton(f, 24, "close", {
            skin = false, tip = L["CLOSE"], onClick = function() f._onClose() end })
        close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
        close:SetFrameLevel(f:GetFrameLevel() + 30)
        local ring = close:CreateTexture(nil, "OVERLAY", nil, 7)
        ring:SetAtlas("UI-Frame-Neutral-ExitButtonBorder", true)
        ring:SetPoint("CENTER", close, "CENTER", 0, 0)
    end

    -- Left: the table of contents
    local toc = Pane(f, "UI-Frame-Neutral-CardParchment", LAY.tocW, true)
    if not C.skin then toc:SetPoint("TOPLEFT", f, "TOPLEFT", LAY.side, -LAY.top) end
    local head = toc:CreateFontString(nil, "OVERLAY")
    head:SetFontObject(TitleFont())
    head:SetPoint("TOP", toc, "TOP", 0, LAY.tocHead)
    head:SetText(L["HELP_BOOK_CONTENTS"])
    Ink(head, C.title)
    f._search = BuildSearch(toc)
    local tsf = BNB.CreateScrollFrame(nil, toc)
    tsf:SetPoint("TOPLEFT",     toc, "TOPLEFT",     LAY.tocX, LAY.tocList)
    tsf:SetPoint("BOTTOMRIGHT", toc, "BOTTOMRIGHT", LAY.tocR, LAY.tocB)
    local tbar = tsf.ScrollBar
    if tbar then
        if not C.skin and BNB.TintScrollBarFixed then BNB.TintScrollBarFixed(tbar, BAR_TINT[1], BAR_TINT[2], BAR_TINT[3]) end
        tbar:SetAlpha(0)
        tsf:HookScript("OnScrollRangeChanged", function(_, _, yRange)
            tbar:SetAlpha((yRange or 0) > 1 and 1 or 0)
        end)
    end
    local tchild = CreateFrame("Frame", nil, tsf)
    local paneW = C.skin and (LAY.side + LAY.tocW - SKIN_INSET) or LAY.tocW
    tchild:SetSize(paneW - LAY.tocX + LAY.tocR, 1)
    tsf:SetScrollChild(tchild)
    f._tocScroll, f._tocChild = tsf, tchild
    local none = tsf:CreateFontString(nil, "OVERLAY")
    none:SetFontObject(BookFont())
    none:SetPoint("TOPLEFT",  tsf, "TOPLEFT",  6, -4)
    none:SetPoint("TOPRIGHT", tsf, "TOPRIGHT", -4, -4)
    none:SetJustifyH("LEFT")
    none:SetText(L["HELP_BOOK_NO_MATCH"])
    Ink(none, C.body)
    none:SetAlpha(0.7)
    none:Hide()
    f._noMatch = none

    -- The divider between the pages: the kit's edge at half size (so it
    -- tiles at its own scale). Skin: the side panel's own edge is the divider
    if not C.skin then
        local dv = CreateFrame("Frame", nil, f)
        dv:SetScale(0.5)
        dv:SetSize(30, PARCH_H / 0.5)
        dv:SetPoint("TOP", toc, "TOPRIGHT", (LAY.gap / 2) / 0.5, 0)
        dv:SetFrameLevel(f:GetFrameLevel() + 10)
        local dtx = dv:CreateTexture(nil, "ARTWORK")
        dtx:SetAtlas("!Neutral-NineSlice-EdgeLeft")
        dtx:SetVertTile(true)
        dtx:SetAllPoints(dv)
    end

    -- Right: the page
    local page = Pane(f, "UI-Frame-Neutral-CardParchmentWider", LAY.pageW)
    if C.skin then
        page:SetPoint("TOPLEFT", f, "TOPLEFT", LAY.side + LAY.tocW + LAY.gap, -LAY.top)
    else
        page:SetPoint("TOPLEFT", toc, "TOPRIGHT", LAY.gap, 0)
    end
    f._cover = BuildCover(page)
    f._topic = BuildTopic(page)

    f._prev = BNB.CreateIconButton(page, 22, "left", {
        skin = C.skin, tip = L["HELP_BOOK_PREV"], onClick = function() HB.ShowPage(current - 1) end })
    f._prev:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", LAY.footX, LAY.footY)
    f._next = BNB.CreateIconButton(page, 22, "right", {
        skin = C.skin, tip = L["HELP_BOOK_NEXT"], onClick = function() HB.ShowPage(current + 1) end })
    f._next:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", LAY.footR, LAY.footY)
    local no = page:CreateFontString(nil, "OVERLAY")
    no:SetFontObject(BookFont())
    no:SetPoint("BOTTOM", page, "BOTTOM", -4, LAY.noY)
    Ink(no, C.body)
    f._pageNo = no

    f:HookScript("OnHide", function() gen.n = gen.n + 1 end)
    return f
end

-- ── Public ───────────────────────────────────────────────────────────────────

function HB.Open(key)
    local f = Build()
    topics = BNB.HelpTopics and BNB.HelpTopics() or {}
    hay = {}
    -- A new open starts with no search
    if f._search:HasFocus() then f._search:ClearFocus() end
    f._search.SetRealText(f._search, "")
    FillToc()
    local hint = L["HELP_BOOK_HINT"]
    if #topics == 0 then hint = L["HELP_BOOK_EMPTY"] end
    f._cover._hint:SetText(hint)
    BNB.SeatWindow(f, f._strata)
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    f:Show()
    f:Raise()
    if not (key and HB.ShowKey(key)) then HB.ShowPage(0) end
end

function HB.Close()
    if frame then frame:Hide() end
end

function HB.Toggle()
    if frame and frame:IsShown() then HB.Close() else HB.Open() end
end

-- BigNoteBox UI/HelpBook.lua - the help book (ALL-554)
--
-- The help topics (UI/HelpData.lua, the same text as the Help folder) in a
-- window of their own, so a new player has somewhere to start: the table of
-- contents on the narrow parchment, the page on the wide one, a cover first
-- (logo.tga), Previous / Next along the bottom (the cover has one button to
-- the first topic instead, Dukul, 2026-10-23). Decided with Dukul,
-- 2026-10-23: Blizzard's Neutral frame kit (the wood "table" tile behind,
-- UI-Frame-Neutral-CardParchment / -CardParchmentWider, the vertical edge as
-- the divider, the Neutral nine-slice border and title), fixed size ("the doc
-- window shouldn't be resizeable"). Skin mode has its own version (Dukul,
-- 2026-10-23): a skin window, Contents and page as two skin panels, white
-- text, accent headings; the same pages and controls. Retail and
-- Forever first; Classic waits on Dukul's art check. Later stages: the "?"
-- icons and help links open it, the patch notes move in.
--
-- Chapters (stage 2, decided with Dukul 2026-10-23): each doc-mode folder is
-- a chapter (BNB.HelpChapters, UI/Help.lua). The pages run: the cover, the
-- topics in no chapter, then per chapter its own cover and its topics. A
-- chapter cover has the chapter's number and name, its Cover note's picture
-- and intro, and its topics as links; Previous / Next stay, and the page
-- number's spot holds a button to its first topic (the main cover has only
-- that button). Contents: chapter names as headers (click = its cover), its
-- topics indented under them, never folded; a search keeps the header of a
-- chapter with a match.
--
-- The page is dark ink on parchment: the topic markup is the same as in a
-- note, so the book swaps the light link colours for darker ones and tints
-- the white Assets art (toolbar, explorer, doc icons) brown (Parchment).
--
-- Patch notes (ALL-614, Dukul, 2026-10-29): a third tab right of Features,
-- one page per release (BNB.WhatsNew.Releases, newest first, no cover), the
-- version numbers in Contents; it replaced the Patch notes system folder and
-- the "What's New?" window. The update toast opens its release here.
--
-- Public API:
--   BNB.HelpBook.Open(key, which)   opens the book at that topic (nil = the
--                            cover); which = "features" / "patches" opens that tab
--   BNB.HelpBook.OpenFeatures()
--   BNB.HelpBook.OpenPatchNotes(version)   the Patch notes tab at that
--                            release (nil = the newest)
--   BNB.HelpBook.Close()
--   BNB.HelpBook.Toggle()

local BNB = BigNoteBox
local L   = BNB.L

local HB = {}
BNB.HelpBook = HB

local LOGO = "Interface\\AddOns\\BigNoteBox\\Assets\\logo"

-- Sizes in window pixels. The page parchment keeps the shape of its art; the
-- Contents one is a little narrower than its art (Dukul, 2026-10-23: "make
-- the left side a little smaller"). 440 high, down from 500, near the skin
-- window's size (Dukul, 2026-10-23: "Do the same in Normal mode")
local PARCH_H  = 440
local TOC_W    = math.floor(254 / 439 * PARCH_H * 0.88 + 0.5)   -- CardParchment 254 x 439
local PAGE_W   = math.floor(515 / 438 * PARCH_H + 0.5)          -- CardParchmentWider 515 x 438
local ROW_H    = 22
local HEAD_GAP = 6    -- space above a chapter header in Contents
local INDENT   = 14   -- a chapter's topics in Contents
local PIC      = 64   -- a chapter cover's picture
local SEARCH_H = 22
local START_W, START_H = 200, 32   -- the cover's Getting started button

-- Where things sit, per look. Book: inside the wooden border and the burnt
-- parchment edges, under the shaded tops. Skin: a skin window's title strip
-- and plain panels, smaller (Dukul, 2026-10-23: Contents only as wide as its
-- longest topic, "No need having it as big"). search = the search box's top,
-- tocHead = "Contents" under it, tocList = the list
local LAYOUTS = {
    book = { side = 26, gap = 16, top = 100, bottom = 26,
             tocW = TOC_W, pageW = PAGE_W, paneH = PARCH_H,
             -- the 500-high places x 0.88, with the parchments
             search = -53, tocHead = -82, tocList = -110, tocX = 26, tocR = -35, tocB = 30,
             pageX = 39, pageTop = -56, pageR = -49, pageB = 52,
             footX = 39, footR = -46, footY = 19, noY = 24, logo = 170, logoY = -40 },
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

local frame, coverFont, chapterFont, chapterRowFont
-- Two books, picked by the tabs under the window (Dukul, 2026-10-24):
-- "docs" = the help topics, "features" = BNB.FEATURE_LIST sorted A-Z by
-- header (UI/FeatureListData.lua; it replaced the Features window). Each
-- has its own pages; Contents, search and page turning work on the open one.
-- The pages after the cover, in order. A topic: { kind = "topic", topic =
-- t, chapterPage = its chapter cover's index or nil }. A chapter cover:
-- { kind = "chapter", chapter = { ch, topics }, no = its number, first =
-- the index of its first topic }. A feature: { kind = "feature", sec = its
-- FEATURE_LIST section }. The Features book has no cover: it starts at 1
-- "patches" = the releases, { kind = "patch", rel = a BNB.WhatsNew.Releases()
-- entry }, no cover either (ALL-614)
local book = "docs"
local sets = { docs = {}, features = {}, patches = {} }
local hays = { docs = {}, features = {}, patches = {} }
local pages = sets.docs
local hay = hays.docs      -- hay[i] = pages[i]'s text, plain and lower case (search)
local current = 0          -- 0 = the cover, i = pages[i]
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
        C.link = { 0x6c / 255, 0xb4 / 255, 0xee / 255 }   -- a note link's blue
    else
        C.head, C.title, C.pick, C.body = INK_HEAD, INK_TITLE, INK_PICK, INK_BODY
        C.hover = { 0.45, 0.28, 0.10, 0.10 }
        C.link = { 0x1a / 255, 0x4f / 255, 0x8a / 255 }   -- the same, darker on parchment (INK_SWAP)
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

-- The housing wood frame (ALL-615, Dukul, 2026-10-29: the Neutral border "is
-- to thick and looks weird"): one picture with a see-through middle, cut in
-- nine so the corners keep their size and the rails stretch, drawn at its own
-- size (448 x 320; the file is the 2x one). Retail and Forever have the file;
-- Classic keeps the Neutral border (Dukul: "The frame exists in Forever, not
-- Classic")
local WOOD      = "Interface\\Housing\\HousingWoodFrame2x"   -- file 7012488
local WOOD_FILE = 1024       -- the file's size
local WOOD_W, WOOD_H = 896, 640   -- the frame in the file, from (1, 1)
local WOOD_CW, WOOD_CH = 120, 90  -- a corner in file pixels (the bottom leaves fit)

local function HasWood()
    if BNB.IsClassic then return false end
    return not (C_UIFileAsset and C_UIFileAsset.IsKnownFile) or C_UIFileAsset.IsKnownFile(WOOD) and true or false
end

local function BuildWood(f)
    local ns = CreateFrame("Frame", nil, f)
    ns:SetAllPoints(f)
    ns:SetFrameLevel(f:GetFrameLevel() + 20)
    local o = 1 / WOOD_FILE
    local xs = { 1, 1 + WOOD_CW, 1 + WOOD_W - WOOD_CW, 1 + WOOD_W }
    local ys = { 1, 1 + WOOD_CH, 1 + WOOD_H - WOOD_CH, 1 + WOOD_H }
    local cw, ch = WOOD_CW / 2, WOOD_CH / 2   -- on screen
    -- Per column: the left and right edge (anchor point on f, x offset);
    -- per row: the top and bottom edge
    local COLS = { { "LEFT", 0, "LEFT", cw }, { "LEFT", cw, "RIGHT", -cw }, { "RIGHT", -cw, "RIGHT", 0 } }
    local ROWS = { { "TOP", 0, "TOP", -ch }, { "TOP", -ch, "BOTTOM", ch }, { "BOTTOM", ch, "BOTTOM", 0 } }
    for r = 1, 3 do
        for c = 1, 3 do
            if r ~= 2 or c ~= 2 then   -- the middle is see-through
                local t = ns:CreateTexture(nil, "BORDER")
                t:SetTexture(WOOD)
                t:SetTexCoord(xs[c] * o, xs[c + 1] * o, ys[r] * o, ys[r + 1] * o)
                local col, row = COLS[c], ROWS[r]
                t:SetPoint("TOPLEFT",     f, row[1] .. col[1], col[2], row[2])
                t:SetPoint("BOTTOMRIGHT", f, row[3] .. col[3], col[4], row[4])
            end
        end
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

    -- Bigger than SystemFont_Large (Dukul, 2026-10-23: "make the text in the
    -- header on the top bigger")
    local plateFont = CreateFont("BNBHelpBookPlateFont")
    plateFont:CopyFontObject(_G.SystemFont_Large or BNBFontNormalLarge)
    local path, _, flags = plateFont:GetFont()
    if path then plateFont:SetFont(path, 22, flags or "") end
    local fs = tf:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(plateFont)
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

-- A chapter header's font in Contents: the quest title font, smaller
local function ChapterRowFont()
    if chapterRowFont then return chapterRowFont end
    chapterRowFont = CreateFont("BNBHelpBookChapterRowFont")
    chapterRowFont:CopyFontObject(TitleFont())
    local path, _, flags = chapterRowFont:GetFont()
    if path then chapterRowFont:SetFont(path, 15, flags or "") end
    chapterRowFont:SetShadowOffset(0, 0)
    return chapterRowFont
end

-- A page's name: the topic's title, or the chapter's name
local function PageName(i)
    local pg = pages[i]
    if not pg then return "" end
    if pg.kind == "chapter" then return (BNB.HelpChapterText(pg.chapter.ch)) end
    if pg.kind == "feature" then return tostring(pg.sec.header or "") end
    if pg.kind == "patch" then return string.format(L["HELP_BOOK_PATCH_ROW_FMT"], pg.rel.version) end
    return (BNB.HelpTopicText(pg.topic))
end

-- The row in list slot `slot` (0 = the top), placed by FillToc; row._i is
-- the page it opens, row._head = a chapter header
local function TocRow(slot)
    local toc = frame._tocChild
    local row = frame._rows[slot + 1]
    if row then return row end
    row = CreateFrame("Button", nil, toc)
    row:SetHeight(ROW_H)
    -- Hover only: the open topic is marked by its colour (a fill drew a hard
    -- edge on the shaded parchment, first test 2026-10-23)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(row)
    hl:SetColorTexture(C.hover[1], C.hover[2], C.hover[3], C.hover[4])
    row._fs = row:CreateFontString(nil, "OVERLAY")
    row._fs:SetFontObject(BookFont())
    row._fs:SetJustifyH("LEFT")
    row._fs:SetWordWrap(false)
    row._i, row._y = 0, 0
    row:SetScript("OnClick", function(self) HB.ShowPage(self._i) end)
    frame._rows[slot + 1] = row
    return row
end

-- Markup out, lower case: what a search looks through
local function Plain(s)
    s = tostring(s or "")
    s = s:gsub("|T.-|t", " ")
         :gsub("|H.-|h(.-)|h", "%1")
         :gsub("|c%x%x%x%x%x%x%x%x", "")
         :gsub("|r", "")
         :gsub("{[^}]*}", " ")
    return s:lower()
end

-- A page's searchable text: a topic's title and body, a chapter's name and intro
local function Haystack(i)
    local pg = pages[i]
    local a, b
    if pg.kind == "chapter" then a, b = BNB.HelpChapterText(pg.chapter.ch)
    elseif pg.kind == "feature" then
        local sec = pg.sec
        a = sec.header
        b = tostring(sec.blurb or "") .. "\n" .. table.concat(type(sec.items) == "table" and sec.items or {}, "\n")
    elseif pg.kind == "patch" then
        a, b = pg.rel.version, table.concat(pg.rel.lines, "\n")
    else a, b = BNB.HelpTopicText(pg.topic) end
    return Plain((a or "") .. "\n" .. (b or ""))
end

-- The search box's words, lower case; empty = no search
local function SearchWords()
    local eb = frame._search
    local q = eb and eb.GetRealText and eb:GetRealText() or ""
    local words = {}
    for w in q:lower():gmatch("%S+") do words[#words + 1] = w end
    return words
end

-- Every word must be in the page, anywhere in its title or text
local function Matches(i, words)
    local h = hay[i]
    if not h then h = Haystack(i); hay[i] = h end
    for _, w in ipairs(words) do
        if not h:find(w, 1, true) then return false end
    end
    return true
end

local MarkToc

-- The list: every page, or while searching only the pages that have the
-- words (Dukul, 2026-10-23), plus the header of a chapter one of whose
-- topics has them. No Cover row: the book opens on the cover, and Previous
-- on the first page goes back to it (Dukul: "remove Cover")
local function FillToc()
    local words = SearchWords()
    local searching = #words > 0
    local show, hits = {}, {}
    for i, pg in ipairs(pages) do
        if not searching or Matches(i, words) then
            show[i] = true
            hits[#hits + 1] = i
            if pg.chapterPage then show[pg.chapterPage] = true end
        end
    end
    local toc = frame._tocChild
    local slot, y = 0, 0
    for i, pg in ipairs(pages) do
        if show[i] then
            local head = pg.kind == "chapter"
            if head and slot > 0 then y = y + HEAD_GAP end
            local row = TocRow(slot)
            slot = slot + 1
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT",  toc, "TOPLEFT",  0, -y)
            row:SetPoint("TOPRIGHT", toc, "TOPRIGHT", 0, -y)
            row._i, row._y, row._head = i, y, head
            local fs = row._fs
            fs:SetFontObject(head and ChapterRowFont() or BookFont())
            fs:ClearAllPoints()
            fs:SetPoint("LEFT",  row, "LEFT",  6 + (pg.chapterPage and INDENT or 0), 0)
            fs:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            fs:SetText(PageName(i))
            row:Show()
            y = y + ROW_H
        end
    end
    for k = slot + 1, #frame._rows do frame._rows[k]:Hide() end
    frame._noMatch:SetShown(searching and #hits == 0)
    frame._tocHits = hits
    frame._tocChild:SetHeight(math.max(1, y))
    frame._tocScroll:SetVerticalScroll(0)
    MarkToc()
end

function MarkToc()
    local mark
    for _, row in ipairs(frame._rows) do
        local on = row:IsShown() and row._i == current
        if on then mark = row end
        Ink(row._fs, on and C.pick or (row._head and C.title or C.body))
    end
    -- Keep the open page in view, when the list shows it
    if not mark then return end
    local sf = frame._tocScroll
    local y, viewH = mark._y, sf:GetHeight()
    local s = sf:GetVerticalScroll()
    if y < s then sf:SetVerticalScroll(y)
    elseif y + ROW_H > s + viewH then sf:SetVerticalScroll(math.max(0, y + ROW_H - viewH)) end
end

-- ── The page ─────────────────────────────────────────────────────────────────

-- The width a page's text gets: its scroll frame's, once laid out
local function TextWidth(sf)
    local w = sf:GetWidth()
    if not (w and w > 0) then w = LAY.pageW - 100 end
    return w
end

-- Draws markup into a page's render frame; -> its height
local function RenderMarkup(rf, text, w)
    rf:SetWidth(w)
    local rawST = getmetatable(rf).__index.SetText
    local html = BNB.AdvancedMode.ToHTML(text, nil, w)
    if not C.skin then html = Parchment(html) end
    rawST(rf, html)
    local h = rf:GetContentHeight()
    rf:SetHeight(h)
    return h
end

-- A feature's "More in the help" links share the topic page's scroll child
local function HideFeatLinks()
    frame._featMore:Hide()
    for _, b in ipairs(frame._featLinks) do b:Hide() end
end

-- Next frame: a SimpleHTML's width is never set while the client lays out
-- (FOR-30), and a newer page drops this one
local function RenderTopic(t)
    gen.n = gen.n + 1
    local my = gen.n
    C_Timer.After(0, function()
        if my ~= gen.n or not frame:IsShown() then return end
        HideFeatLinks()
        local AM = BNB.AdvancedMode
        local sf, hold, rf, pfs = frame._pageScroll, frame._hold, frame._rf, frame._pfs
        local w = TextWidth(sf)
        hold:SetWidth(w)
        local _, body = BNB.HelpTopicText(t)
        if t.rich and AM then
            pfs:Hide(); rf:Show()
            hold:SetHeight(RenderMarkup(rf, body, w) + 8)
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

-- The Documentation page of a help topic key; nil when this client has none
local function DocsIndex(key)
    for i, pg in ipairs(sets.docs) do
        if pg.topic and pg.topic.key == key then return i end
    end
end

-- The links under a feature, from y down: a "More in the help" line, then
-- one row per help topic it names (sec.help) that this client has; -> the y
-- under them. A click turns to the topic in Documentation (HB.ShowKey)
local function FeatureLinks(hold, sec, y)
    local found = {}
    for _, key in ipairs(type(sec.help) == "table" and sec.help or {}) do
        local i = DocsIndex(key)
        if i then found[#found + 1] = { key = key, name = (BNB.HelpTopicText(sets.docs[i].topic)) } end
    end
    if #found == 0 then return y end
    local more = frame._featMore
    more:ClearAllPoints()
    more:SetPoint("TOPLEFT", hold, "TOPLEFT", 0, -(y + 6))
    more:Show()
    y = y + 6 + more:GetStringHeight() + 2
    for n, it in ipairs(found) do
        local b = frame._featLinks[n]
        if not b then
            b = CreateFrame("Button", nil, hold)
            b:SetHeight(ROW_H)
            local fs = b:CreateFontString(nil, "OVERLAY")
            fs:SetFontObject(PageFonts().p)
            fs:SetPoint("LEFT", b, "LEFT", INDENT, 0)
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(false)
            Ink(fs, C.link)
            b._fs = fs
            local hl = b:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints(b)
            hl:SetColorTexture(C.hover[1], C.hover[2], C.hover[3], C.hover[4])
            b:SetScript("OnClick", function(self) HB.ShowKey(self._key) end)
            frame._featLinks[n] = b
        end
        b._key = it.key
        b._fs:SetText("> " .. it.name)
        b:SetWidth(INDENT + math.ceil(b._fs:GetStringWidth()) + 10)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", hold, "TOPLEFT", 0, -y)
        b:Show()
        y = y + ROW_H
    end
    return y
end

-- A feature: its blurb, its items as a list and its help links. Plain text,
-- as a plain topic: through the rich renderer {{date}} would be filled in
local function RenderFeature(pg)
    gen.n = gen.n + 1
    local my = gen.n
    C_Timer.After(0, function()
        if my ~= gen.n or not frame:IsShown() then return end
        HideFeatLinks()
        local sf, hold, rf, pfs = frame._pageScroll, frame._hold, frame._rf, frame._pfs
        local w = TextWidth(sf)
        hold:SetWidth(w)
        local sec = pg.sec
        local lines = {}
        if type(sec.blurb) == "string" and sec.blurb ~= "" then
            lines[1] = sec.blurb
            lines[2] = ""
        end
        for _, item in ipairs(type(sec.items) == "table" and sec.items or {}) do
            lines[#lines + 1] = "-  " .. tostring(item)
        end
        rf:Hide(); pfs:Show()
        pfs:SetWidth(w)
        pfs:SetText(table.concat(lines, "\n"))
        local y = pfs:GetStringHeight() + 8
        hold:SetHeight(FeatureLinks(hold, sec, y) + 8)
        sf:SetVerticalScroll(0)
    end)
end

-- A release (ALL-614): its lines under New / Change / Fixed, as the patch
-- notes were written for a note (BNB.WhatsNew.PatchBody); plain when the
-- rich renderer is missing. Next frame, as a topic
local function RenderPatch(pg)
    gen.n = gen.n + 1
    local my = gen.n
    C_Timer.After(0, function()
        if my ~= gen.n or not frame:IsShown() then return end
        HideFeatLinks()
        local sf, hold, rf, pfs = frame._pageScroll, frame._hold, frame._rf, frame._pfs
        local w = TextWidth(sf)
        hold:SetWidth(w)
        local WN, rel = BNB.WhatsNew, pg.rel
        if BNB.AdvancedMode then
            pfs:Hide(); rf:Show()
            hold:SetHeight(RenderMarkup(rf, WN.PatchBody(rel.version, rel.lines, true), w) + 8)
        else
            rf:Hide(); pfs:Show()
            pfs:SetWidth(w)
            pfs:SetText(WN.PatchBody(rel.version, rel.lines, false))
            hold:SetHeight(pfs:GetStringHeight() + 8)
        end
        sf:SetVerticalScroll(0)
    end)
end

-- A chapter cover: picture, "Chapter N", the name, the intro, its topics as
-- links (the page's link handler turns to them). Next frame, as a topic
local function RenderChapter(pg)
    gen.n = gen.n + 1
    local my = gen.n
    C_Timer.After(0, function()
        if my ~= gen.n or not frame:IsShown() then return end
        local cp = frame._chapter
        local sf, hold = cp._scroll, cp._hold
        local w = TextWidth(sf)
        hold:SetWidth(w)
        local ch = pg.chapter.ch
        local name, body = BNB.HelpChapterText(ch)

        local top = 6
        local pic = cp._pic
        if ch.icon then
            pic:SetTexture(ch.icon)
            -- White Assets art in the page's brown, as in a topic (Parchment)
            local folder = type(ch.icon) == "string" and ch.icon:match("^Interface\\AddOns\\BigNoteBox\\Assets\\(%a+)\\")
            if not C.skin and folder and WHITE_ART[folder] then
                pic:SetVertexColor(90 / 255, 58 / 255, 26 / 255)
            else
                pic:SetVertexColor(1, 1, 1)
            end
            pic:Show()
            top = top + PIC + 12
        else
            pic:Hide()
        end
        local no, nm = cp._no, cp._name
        no:ClearAllPoints()
        no:SetPoint("TOP", hold, "TOP", 0, -top)
        no:SetText(string.format(L["HELP_BOOK_CHAPTER_FMT"], pg.no))
        nm:SetWidth(w - 20)
        nm:SetText(name)
        top = top + no:GetStringHeight() + 4 + nm:GetStringHeight() + 18

        -- The intro, then the chapter's topics: note links to their Help ids,
        -- as docs-build writes a link between topics
        local lines = {}
        if body and body:find("%S") then lines[1] = body end
        for _, t in ipairs(pg.chapter.topics) do
            local title = tostring((BNB.HelpTopicText(t))):gsub("|", "")
            lines[#lines + 1] = string.format("- |cff6cb4ee|Hbnbnote:%s|h%s|h|r", BNB.HelpNoteID(t.key), title)
        end
        local rf = cp._rf
        rf:ClearAllPoints()
        rf:SetPoint("TOPLEFT", hold, "TOPLEFT", 0, -top)
        hold:SetHeight(top + RenderMarkup(rf, table.concat(lines, "\n"), w) + 8)
        sf:SetVerticalScroll(0)
    end)
end

-- The one big button: on the main cover and in a chapter cover's page
-- number spot, named after the page it opens; nil = hidden
local function SetStart(to)
    local b = frame._start
    if not (to and pages[to]) then b:Hide(); return end
    b._to = to
    b:SetText(PageName(to))
    local fs = b:GetFontString()
    local w = fs and fs:GetStringWidth() or 0
    b:SetWidth(math.max(START_W, math.ceil(w) + 48))
    b:Show()
end

-- The first page of the open book: only Documentation has a cover
local function FirstPage()
    return (book ~= "docs" and #pages > 0) and 1 or 0
end

function HB.ShowPage(i)
    if not frame then return end
    local n = #pages
    local lo = FirstPage()
    current = math.max(lo, math.min(i or lo, n))
    local pg = pages[current]
    local kind = pg and pg.kind or "cover"
    local text = kind == "topic" or kind == "feature" or kind == "patch"
    frame._cover:SetShown(kind == "cover")
    frame._topic:SetShown(text)
    frame._chapter:SetShown(kind == "chapter")
    -- The cover has no arrows and no page number: one button to the first
    -- page in their place (Dukul, 2026-10-23). A chapter cover keeps the
    -- arrows; the button to its first topic takes the page number's spot
    frame._prev:SetShown(kind ~= "cover")
    frame._next:SetShown(kind ~= "cover")
    frame._pageNo:SetShown(text)
    if kind == "cover" then
        gen.n = gen.n + 1
        frame:SetWindowTitle(L["HELP_BOOK_TITLE"])
        SetStart(n > 0 and 1 or nil)
    else
        -- The page's name goes on the title plate, not on the page (Dukul,
        -- 2026-10-23: "Writing Notes - BigNoteBox Help")
        local fmt = L["HELP_BOOK_TITLE_FMT"]
        if kind == "feature" then fmt = L["HELP_BOOK_FEAT_TITLE_FMT"]
        elseif kind == "patch" then fmt = L["HELP_BOOK_PATCH_TITLE_FMT"] end
        frame:SetWindowTitle(string.format(fmt, PageName(current)))
        if kind == "chapter" then
            SetStart(pg.first)
            RenderChapter(pg)
        else
            SetStart(nil)
            frame._pageNo:SetText(string.format(L["HELP_BOOK_PAGE_FMT"], current, n))
            if kind == "feature" then RenderFeature(pg)
            elseif kind == "patch" then RenderPatch(pg)
            else RenderTopic(pg.topic) end
        end
    end
    frame._prev:SetEnabled(current > lo)
    frame._next:SetEnabled(current < n)
    MarkToc()
end

-- Opens a book ("docs" / "features" / "patches"): its pages, an empty
-- search, its tab marked. The caller shows a page
local function SetBook(name)
    book = sets[name] and name or "docs"
    pages, hay = sets[book], hays[book]
    local eb = frame._search
    if eb:HasFocus() then eb:ClearFocus() end
    eb.SetRealText(eb, "")
    FillToc()
    local tabs = frame._tabs
    if tabs then
        tabs.docs:SetActive(book == "docs")
        tabs.features:SetActive(book == "features")
        tabs.patches:SetActive(book == "patches")
    end
end

-- A help topic by key, in Documentation (from Features too); false when
-- this client has no such topic
function HB.ShowKey(key)
    local i = DocsIndex(key)
    if not i then return false end
    if book ~= "docs" then SetBook("docs") end
    HB.ShowPage(i)
    return true
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

-- A page's scrolling text area, under the parchment's shaded top; -> the
-- scroll frame and its child
local function PageScroll(parent)
    local sf = BNB.CreateScrollFrame(nil, parent)
    sf:SetPoint("TOPLEFT",     parent, "TOPLEFT",     LAY.pageX, LAY.pageTop)
    sf:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", LAY.pageR, LAY.pageB)
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
    return sf, hold
end

-- A render frame with the page's fonts and ink, bound once (FOR-30)
local function PageRender(hold)
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
    return rf
end

-- A chapter cover: filled by RenderChapter. All of it scrolls, so a long
-- intro or a long chapter still fits
local function BuildChapter(page)
    local cp = CreateFrame("Frame", nil, page)
    cp:SetAllPoints(page)
    local sf, hold = PageScroll(cp)
    cp._scroll, cp._hold = sf, hold

    local pic = hold:CreateTexture(nil, "ARTWORK")
    pic:SetSize(PIC, PIC)
    pic:SetPoint("TOP", hold, "TOP", 0, -6)
    cp._pic = pic

    local no = hold:CreateFontString(nil, "OVERLAY")
    no:SetFontObject(TitleFont())
    Ink(no, C.title)
    cp._no = no

    if not chapterFont then
        chapterFont = CreateFont("BNBHelpBookChapterFont")
        chapterFont:CopyFontObject(TitleFont())
        local path, _, flags = chapterFont:GetFont()
        if path then chapterFont:SetFont(path, 26, flags or "") end
    end
    local nm = hold:CreateFontString(nil, "OVERLAY")
    nm:SetFontObject(chapterFont)
    nm:SetPoint("TOP", no, "BOTTOM", 0, -4)
    nm:SetJustifyH("CENTER")
    nm:SetWordWrap(true)
    Ink(nm, C.head)
    cp._name = nm

    cp._rf = PageRender(hold)
    return cp
end

local function BuildTopic(page)
    local tp = CreateFrame("Frame", nil, page)
    tp:SetAllPoints(page)
    local sf, hold = PageScroll(tp)
    local rf = PageRender(hold)

    local pfs = hold:CreateFontString(nil, "OVERLAY")
    pfs:SetFontObject(PageFonts().p)
    pfs:SetSpacing(3)
    pfs:SetPoint("TOPLEFT", hold, "TOPLEFT", 0, 0)
    pfs:SetJustifyH("LEFT")
    pfs:SetJustifyV("TOP")
    pfs:SetWordWrap(true)
    Ink(pfs, C.body)

    -- A feature's "More in the help" line; its link rows are made by FeatureLinks
    local more = hold:CreateFontString(nil, "OVERLAY")
    more:SetFontObject(PageFonts().h3)
    Ink(more, C.head)
    more:SetText(L["HELP_BOOK_MORE"])
    more:Hide()
    frame._featMore, frame._featLinks = more, {}

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
        -- A light paper field with a brown edge (Dukul, 2026-10-23: "Add a
        -- background to the search box"; the faint wash hardly showed)
        BNB.SetBackdrop(bg, 1.00, 0.96, 0.86, 0.80, 0.40, 0.24, 0.08, 0.9)
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
    -- Enter opens the first page found (not a header shown only for its topics)
    eb:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        local hits = frame._tocHits
        if hits and hits[1] and #SearchWords() > 0 then HB.ShowPage(hits[1]) end
    end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- The X empties the search (Dukul, 2026-10-23: "it's missing a X to
    -- clear it"); shown only while there is something to clear
    local x = BNB.CreateClearX(bg, 16, function() eb:ClearFocus(); eb.SetRealText(eb, "") end,
        L["CFG_SEARCH_CLEAR"])
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

-- Documentation | Features: the rich-note tabs (UI/NoteEditor.lua's
-- _BottomTabKit) hanging under the window's bottom edge, at the left (Dukul,
-- 2026-10-24: "just like rich note tabs in main window, outside at the
-- bottom"). Skin: tucked up under the window, in the strata below it (set on
-- open, HB.Open). Book: just under the bottom wood, which draws over their tops
local function BuildTabs(f)
    local K = BNB._BottomTabKit
    if not K then return end
    local strip = CreateFrame("Frame", nil, f)
    strip:SetSize(1, C.skin and K.SKIN_H or K.H)
    local L1, T1 = L["HELP_BOOK_TAB_DOCS"], L["HELP_BOOK_TAB_DOCS_TIP"]
    local L2, T2 = L["HELP_BOOK_TAB_FEATURES"], L["HELP_BOOK_TAB_FEATURES_TIP"]
    -- Patch notes (ALL-614): the bell, the closest symbol to "news"
    local L3, T3 = L["HELP_BOOK_TAB_PATCH"], L["HELP_BOOK_TAB_PATCH_TIP"]
    local docs, feats, pats, y
    if C.skin then
        docs  = K.Skin(strip, "help", L1, T1)
        feats = K.Skin(strip, "note", L2, T2)
        pats  = K.Skin(strip, "alarm", L3, T3)
        strip:SetPoint("TOPLEFT", f, "BOTTOMLEFT", LAY.side, 0)
        y = K.SKIN_TUCK
        strip._under = true
    elseif K.HasSheet() then
        docs  = K.Forever(strip, "yellow", "help", L1, T1)
        feats = K.Forever(strip, "blue",   "note", L2, T2)
        pats  = K.Forever(strip, "yellow", "alarm", L3, T3)
        -- The Neutral bottom wood reaches 6 px under the frame (BORDER
        -- corners); the thin housing frame ends at the edge, its 3 px rail
        -- over the tabs' tops (ALL-615)
        strip:SetPoint("TOPLEFT", f, "BOTTOMLEFT", LAY.side, HasWood() and 3 or -2)
        strip:SetFrameLevel(f:GetFrameLevel() + 1)   -- under the border (+20)
        y = 0
    else
        -- No tab art on this client: icon buttons, the inactive one dimmed
        local function Btn(sym, tip)
            local b = BNB.CreateIconButton(strip, 32, sym, { tip = tip, tipAnchor = "ANCHOR_TOP" })
            function b:SetActive(on) self:SetDim(not on) end
            return b
        end
        docs, feats, pats = Btn("help", L1), Btn("note", L2), Btn("alarm", L3)
        strip:SetPoint("TOPLEFT", f, "BOTTOMLEFT", LAY.side, -4)
        y = 0
    end
    if docs.SetWidth and feats.GetWidth and not docs.SetDim then   -- text tabs: the widest label's width
        local w = math.max(docs:GetWidth(), feats:GetWidth(), pats:GetWidth())
        docs:SetWidth(w); feats:SetWidth(w); pats:SetWidth(w)
    end
    docs:SetPoint("TOPLEFT", strip, "TOPLEFT", 0, y)
    feats:SetPoint("LEFT", docs, "RIGHT", K.GAP, 0)
    pats:SetPoint("LEFT", feats, "RIGHT", K.GAP, 0)
    -- HookScript: an icon button owns its handlers (windows-widgets.md)
    docs:HookScript("OnClick", function()
        if book ~= "docs" then SetBook("docs"); HB.ShowPage(0) end
    end)
    feats:HookScript("OnClick", function()
        if book ~= "features" then SetBook("features"); HB.ShowPage(1) end
    end)
    pats:HookScript("OnClick", function()
        if book ~= "patches" then SetBook("patches"); HB.ShowPage(1) end
    end)
    f._tabs = { strip = strip, docs = docs, features = feats, patches = pats }
end

local function Build()
    if frame then return frame end
    -- Skin mode is read once: switching it reloads the UI
    SetLook(BigNoteBoxDB and BigNoteBoxDB.skinMode and true or false)
    local winW = LAY.side + LAY.tocW + LAY.gap + LAY.pageW + LAY.side
    local winH = LAY.top + LAY.paneH + LAY.bottom
    local f = BNB.CreateToolWindow({
        name = "BigNoteBoxHelpBook", w = winW, h = winH, art = not C.skin,
        title = L["HELP_BOOK_TITLE"], escClose = true, keyEsc = true,
        -- The main window's strata: clicking either brings it to the front
        -- (Dukul, 2026-10-23: "the window shouldn't always on top")
        strata = "MEDIUM",
    })
    frame = f
    f._rows = {}

    if not C.skin then
        -- The table: the wood tile under everything, inset as Chromie Time's
        -- (under the thin wood frame's rail, ALL-615)
        local wood = HasWood()
        local inset = wood and 2 or 9
        local tbl = f:CreateTexture(nil, "BACKGROUND", nil, -2)
        tbl:SetPoint("TOPLEFT", f, "TOPLEFT", inset, -inset)
        tbl:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, inset)
        tbl:SetAtlas("UI-Frame-Neutral-BackgroundTile")
        tbl:SetHorizTile(true)
        tbl:SetVertTile(true)

        if wood then BuildWood(f) else BuildBorder(f) end
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
        -- On past the parchments, under the bottom wood (the border draws
        -- over it; Dukul, 2026-10-23: "a little further under the wood")
        dv:SetSize(30, (PARCH_H + LAY.bottom) / 0.5)
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
    f._cover   = BuildCover(page)
    f._topic   = BuildTopic(page)
    f._chapter = BuildChapter(page)

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
    -- The cover's way in, named after the first page (Getting started), and
    -- a chapter cover's way to its first topic: set by SetStart. A large
    -- button with large text (Dukul, 2026-10-23: "make the getting started
    -- button bigger too")
    if C.skin then
        f._start = BNB.CreateSkinButton(nil, page, "", START_W, START_H, 16)
    else
        f._start = CreateFrame("Button", nil, page, BNB.PanelButtonTemplate())
        f._start:SetSize(START_W, START_H)
        -- The template's own fonts (its colours), copied at 16
        local function Big(get, set, name)
            local src = f._start[get](f._start)
            if not src then return end
            local fo = CreateFont(name)
            fo:CopyFontObject(src)
            local path, _, flags = fo:GetFont()
            if path then fo:SetFont(path, 16, flags or "") end
            f._start[set](f._start, fo)
        end
        Big("GetNormalFontObject",    "SetNormalFontObject",    "BNBHelpBookStartFont")
        Big("GetHighlightFontObject", "SetHighlightFontObject", "BNBHelpBookStartFontHL")
        Big("GetDisabledFontObject",  "SetDisabledFontObject",  "BNBHelpBookStartFontDis")
    end
    f._start:SetPoint("BOTTOM", page, "BOTTOM", -4, LAY.footY - 1)
    f._start:SetScript("OnClick", function(self) HB.ShowPage(self._to or 1) end)
    f._start:Hide()

    BuildTabs(f)
    f:HookScript("OnHide", function() gen.n = gen.n + 1 end)
    return f
end

-- ── Public ───────────────────────────────────────────────────────────────────

-- Both books' pages. Documentation: the topics in no chapter, then each
-- chapter's cover and topics. Features: the FEATURE_LIST sections A-Z by
-- header (Dukul, 2026-10-24: "make the features alphabetical")
local function BuildPages()
    local docs = {}
    local chapters, loose = {}, {}
    if BNB.HelpChapters then chapters, loose = BNB.HelpChapters()
    elseif BNB.HelpTopics then loose = BNB.HelpTopics() end
    for _, t in ipairs(loose) do docs[#docs + 1] = { kind = "topic", topic = t } end
    for no, c in ipairs(chapters) do
        local at = #docs + 1
        docs[at] = { kind = "chapter", chapter = c, no = no, first = at + 1 }
        for _, t in ipairs(c.topics) do
            docs[#docs + 1] = { kind = "topic", topic = t, chapterPage = at }
        end
    end

    local secs = {}
    for _, sec in ipairs(type(BNB.FEATURE_LIST) == "table" and BNB.FEATURE_LIST or {}) do
        if type(sec) == "table" and sec.header then secs[#secs + 1] = sec end
    end
    table.sort(secs, function(a, b) return tostring(a.header):lower() < tostring(b.header):lower() end)
    local feats = {}
    for i, sec in ipairs(secs) do feats[i] = { kind = "feature", sec = sec } end

    -- Patch notes, newest first (ALL-614)
    local pats = {}
    if BNB.WhatsNew and BNB.WhatsNew.Releases then
        for i, rel in ipairs(BNB.WhatsNew.Releases()) do pats[i] = { kind = "patch", rel = rel } end
    end

    sets.docs, sets.features, sets.patches = docs, feats, pats
    hays.docs, hays.features, hays.patches = {}, {}, {}
end

-- which = "features" / "patches" opens that tab at its first page; else
-- Documentation at the topic `key` (nil = the cover)
function HB.Open(key, which)
    local f = Build()
    BuildPages()
    -- A new open starts with no search
    SetBook(which)
    local hint = L["HELP_BOOK_HINT"]
    if #sets.docs == 0 then hint = L["HELP_BOOK_EMPTY"] end
    f._cover._hint:SetText(hint)
    BNB.SeatWindow(f, f._strata)
    local tabs = f._tabs
    if tabs and tabs.strip._under then
        local below = BNB._BottomTabKit.STRATA_BELOW
        tabs.strip:SetFrameStrata(below[f:GetFrameStrata()] or "LOW")
    end
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    f:Show()
    f:Raise()
    if book ~= "docs" then HB.ShowPage(1)
    elseif not (key and HB.ShowKey(key)) then HB.ShowPage(0) end
end

-- The Features tab (/bnb features, Settings > General, the bnbui:features link)
function HB.OpenFeatures()
    HB.Open(nil, "features")
end

-- The Patch notes tab at a release (the update toast), nil = the newest
-- (the version button, /bnb whatsnew); a version this client has no lines
-- for opens the newest (ALL-614)
function HB.OpenPatchNotes(version)
    HB.Open(nil, "patches")
    if not version then return end
    for i, pg in ipairs(pages) do
        if pg.rel.version == version then HB.ShowPage(i); return end
    end
end

function HB.Close()
    if frame then frame:Hide() end
end

function HB.Toggle()
    if frame and frame:IsShown() then HB.Close() else HB.Open() end
end

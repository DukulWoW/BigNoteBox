-- SkinWidgetsTest.lua
-- Test for ALL-393 (skin-mode scrollbars) and ALL-80 (skin-mode dropdowns),
-- Dukul 2026-10-08: "create a test window which shows what the dropdown and
-- scrollbars (vertical/horizontal) will look like". /bnbskinw toggles it.
-- Dev only, never packaged; nothing in BigNoteBox is changed.
--
-- Three columns, each with a dropdown, a mock of its open list, a vertical
-- scroll area and a horizontal scrollbar:
--   Game    = as the game draws them today
--   Tinted  = the game's own art, desaturated and tinted to the skin preset's
--             border colour (the icon buttons' skin look)
--   Flat    = the game's art hidden, drawn in our skin box style: flat track,
--             solid thumb, the skin button's box for the dropdown
-- The horizontal bar is the minimal scrollbar's own art turned sideways (the
-- game has no horizontal one); the bottom lines print the real bar sizes.
-- The open-list mocks are static pictures; a click on a dropdown still opens
-- the game's real menu in every column (that half is ALL-80's menu hook).
-- Follows the skin preset live (SkinChanged); the slider sets the tint strength.

local function B() return BigNoteBox end

local W, PAD, GAP = 660, 16, 16
local COL_W = math.floor((W - PAD * 2 - GAP * 2) / 3)
local LIST_ROWS = { "Option one", "Option two", "Option three", "Option four" }
local ROW_H = 20
local LONG_LINE = "A long line that does not fit, so the horizontal scrollbar has something to move: "
    .. "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt."

local panel
local strength = 1.6       -- tint multiplier on the border colour
local refreshers = {}      -- re-apply every column's look (preset or strength change)

-- ── Colours ──────────────────────────────────────────────────────────────────
local function Colors()
    local p = B().GetSkinPreset and B().GetSkinPreset()
    if not p then return 0.10, 0.10, 0.12, 0, 0.5, 0.5, 0.5 end
    local br, bg, bb = B().SkinBorderOf(p)
    return p.r, p.g, p.b, p.lift or 0, br, bg, bb
end
local function Tinted(m)
    local _, _, _, _, br, bg, bb = Colors()
    m = (m or 1) * strength
    return math.min(1, br * m), math.min(1, bg * m), math.min(1, bb * m)
end

-- ── Texture walking ──────────────────────────────────────────────────────────
-- Every texture region of a frame (and its children when deep); our own
-- added textures carry _ours and are left out.
local function Textures(frame, out, deep)
    out = out or {}
    for _, r in ipairs({ frame:GetRegions() }) do
        if r.IsObjectType and r:IsObjectType("Texture") and not r._ours then out[#out + 1] = r end
    end
    if deep then
        for _, c in ipairs({ frame:GetChildren() }) do Textures(c, out, true) end
    end
    return out
end
local function TintAll(list, m)
    local r, g, b = Tinted(m)
    for _, t in ipairs(list) do t:SetDesaturated(true); t:SetVertexColor(r, g, b) end
end

-- ── Scrollbar parts ──────────────────────────────────────────────────────────
local function Parts(bar)
    local track = bar.Track
    local thumb = track and track.Thumb or (bar.GetThumb and bar:GetThumb())
    return track, thumb, bar.Back, bar.Forward
end

-- Tinted: the game's art, recoloured (track darker, thumb and arrows lighter)
local function TintBar(bar)
    local track, thumb, back, fwd = Parts(bar)
    local function Run()
        if track then TintAll(Textures(track), 0.7) end
        if thumb then TintAll(Textures(thumb), 1.4) end
        if back then TintAll(Textures(back, nil, true), 1.2) end
        if fwd then TintAll(Textures(fwd, nil, true), 1.2) end
    end
    Run()
    -- The thumb and arrows swap atlases on hover / press: tint again after
    for _, f in ipairs({ thumb, back, fwd }) do
        if f and f.HookScript then
            pcall(f.HookScript, f, "OnEnter", function() C_Timer.After(0, Run) end)
            pcall(f.HookScript, f, "OnLeave", function() C_Timer.After(0, Run) end)
            pcall(f.HookScript, f, "OnMouseUp", function() C_Timer.After(0, Run) end)
        end
    end
    return Run
end

-- Flat: track and thumb art hidden (alpha 0, the template keeps setting atlases),
-- a thin flat track line and a solid thumb drawn; arrows tinted
local function FlatBar(bar, horizontal)
    local track, thumb, back, fwd = Parts(bar)
    local line, solid
    if track then
        line = track:CreateTexture(nil, "BACKGROUND")
        line._ours = true
        if horizontal then
            line:SetPoint("LEFT", 0, 0); line:SetPoint("RIGHT", 0, 0); line:SetHeight(2)
        else
            line:SetPoint("TOP", 0, 0); line:SetPoint("BOTTOM", 0, 0); line:SetWidth(2)
        end
    end
    if thumb then
        solid = thumb:CreateTexture(nil, "ARTWORK")
        solid._ours = true
        solid:SetPoint("TOPLEFT", 1, -1); solid:SetPoint("BOTTOMRIGHT", -1, 1)
    end
    local hover = false
    local function Run()
        local r, g, b, lift = Colors()
        if track then for _, t in ipairs(Textures(track)) do t:SetAlpha(0) end end
        if thumb then for _, t in ipairs(Textures(thumb)) do t:SetAlpha(0) end end
        if line then
            line:SetColorTexture(math.min(1, r + lift * 3), math.min(1, g + lift * 3), math.min(1, b + lift * 3), 1)
        end
        if solid then
            local tr, tg, tb = Tinted(hover and 1.6 or 1.1)
            solid:SetColorTexture(tr, tg, tb, 1)
        end
        if back then TintAll(Textures(back, nil, true), 1.2) end
        if fwd then TintAll(Textures(fwd, nil, true), 1.2) end
    end
    Run()
    if thumb and thumb.HookScript then
        pcall(thumb.HookScript, thumb, "OnEnter", function() hover = true; C_Timer.After(0, Run) end)
        pcall(thumb.HookScript, thumb, "OnLeave", function() hover = false; C_Timer.After(0, Run) end)
    end
    for _, f in ipairs({ back, fwd }) do
        if f and f.HookScript then
            pcall(f.HookScript, f, "OnEnter", function() C_Timer.After(0, Run) end)
            pcall(f.HookScript, f, "OnLeave", function() C_Timer.After(0, Run) end)
            pcall(f.HookScript, f, "OnMouseUp", function() C_Timer.After(0, Run) end)
        end
    end
    return Run
end

-- ── Dropdown ─────────────────────────────────────────────────────────────────
local function MakeDropdown(parent)
    local dd = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    dd:SetWidth(COL_W)
    local picked = 2
    dd:SetupMenu(function(_, root)
        for i, text in ipairs(LIST_ROWS) do
            root:CreateRadio(text, function() return picked == i end, function() picked = i end)
        end
    end)
    return dd
end

local function TintDropdown(dd)
    local function Run() TintAll(Textures(dd, nil, true), 1.4) end
    Run()
    dd:HookScript("OnEnter", function() C_Timer.After(0, Run) end)
    dd:HookScript("OnLeave", function() C_Timer.After(0, Run) end)
    dd:HookScript("OnMouseUp", function() C_Timer.After(0, Run) end)
    return Run
end

-- Flat: built from our own skin pieces (Dukul 2026-10-08: "using our skin
-- button ... the one we use for everything else"): the skin text button
-- (BNB.CreateSkinButton) as the box and a square skin icon button with the
-- "down" symbol (BNB.CreateIconButton) at its right end. Both sit under the
-- real dropdown with the mouse off; the dropdown's hover and press are passed
-- on to them. The game's dropdown art is hidden, its text kept.
local function FlatDropdown(dd, parent)
    local h = dd:GetHeight()
    if not h or h < 10 then h = 26 end
    local vis = B().CreateSkinButton(nil, parent, "", COL_W, h)
    vis:SetAllPoints(dd)
    vis:SetFrameLevel(math.max(0, dd:GetFrameLevel() - 1))
    vis:EnableMouse(false)
    local arrow = B().CreateIconButton(vis, h, "down", { skin = true })
    arrow:SetPoint("RIGHT", vis, "RIGHT", 0, 0)
    arrow:EnableMouse(false)
    local function Pass(frame, script)
        local fn = frame:GetScript(script)
        if fn then pcall(fn, frame) end
    end
    local function Run()
        for _, t in ipairs(Textures(dd, nil, true)) do t:SetAlpha(0) end
        if dd.Text then dd.Text:SetTextColor(1, 1, 1) end
        Pass(arrow, "OnShow")
    end
    Run()
    dd:HookScript("OnEnter", function()
        vis:LockHighlight(); Pass(arrow, "OnEnter"); C_Timer.After(0, Run)
    end)
    dd:HookScript("OnLeave", function()
        vis:UnlockHighlight(); Pass(vis, "OnMouseUp"); Pass(arrow, "OnLeave"); C_Timer.After(0, Run)
    end)
    dd:HookScript("OnMouseDown", function() Pass(vis, "OnMouseDown"); Pass(arrow, "OnMouseDown") end)
    dd:HookScript("OnMouseUp", function()
        Pass(vis, "OnMouseUp"); Pass(arrow, "OnMouseUp"); C_Timer.After(0, Run)
    end)
    return Run
end

-- Static picture of the open list: the game's menu background atlas (tinted
-- or not) or a skin box, rows with the second one hovered and picked
local function MockList(parent, kind)
    local h = #LIST_ROWS * ROW_H + 12
    local f = B().CreateBackdropFrame("Frame", nil, parent)
    f:SetSize(COL_W, h)
    local bgTex = f:CreateTexture(nil, "BACKGROUND")
    bgTex:SetAllPoints()
    local okAtlas = pcall(bgTex.SetAtlas, bgTex, "common-dropdown-bg")
    if not okAtlas then bgTex:SetColorTexture(0.05, 0.05, 0.05, 0.95) end
    local hl = f:CreateTexture(nil, "ARTWORK")
    hl:SetPoint("TOPLEFT", 6, -6 - ROW_H); hl:SetSize(COL_W - 12, ROW_H)
    local tick = f:CreateTexture(nil, "OVERLAY")
    tick:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    tick:SetSize(16, 16); tick:SetPoint("LEFT", hl, "LEFT", 2, 0)
    for i, text in ipairs(LIST_ROWS) do
        local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", 26, -6 - (i - 1) * ROW_H - 4)
        fs:SetText(text)
    end
    local function Run()
        if kind == "flat" then
            bgTex:Hide()
            local r, g, b, lift = Colors()
            local _, _, _, _, br, bg, bb = Colors()
            B().SetBackdrop(f, r, g, b, 0.96, br, bg, bb, 1)
            hl:SetColorTexture(math.min(1, r + lift * 4), math.min(1, g + lift * 4), math.min(1, b + lift * 4), 1)
            tick:SetDesaturated(true); tick:SetVertexColor(Tinted(1.4))
        else
            if f.SetBackdrop then f:SetBackdrop(nil) end
            bgTex:Show()
            hl:SetColorTexture(1, 1, 1, 0.10)
            if kind == "tint" then
                bgTex:SetDesaturated(true); bgTex:SetVertexColor(Tinted(0.9))
                tick:SetDesaturated(true); tick:SetVertexColor(Tinted(1.4))
            end
        end
    end
    Run()
    return f, Run
end

-- ── Scroll areas ─────────────────────────────────────────────────────────────
local function MakeVertical(parent, h)
    local sf = B().CreateScrollFrame(nil, parent)
    sf:SetSize(COL_W - 18, h)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(COL_W - 18, 30 * 16)
    for i = 1, 30 do
        local fs = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", 4, -(i - 1) * 16)
        fs:SetText("Line " .. i .. " of the scroll test")
    end
    sf:SetScrollChild(child)
    return sf
end

-- The horizontal bar: the game has no horizontal minimal template, so it is
-- built here from the vertical MinimalScrollBar's own atlas pieces turned 90
-- degrees (Dukul 2026-10-08: "can't they be used horizontal too?"). Pieces from
-- interface/buttons/minimalscrollbarproportional + minimalscrollbarvertical:
-- track caps 8x8 + middle, thumb top / middle / bottom (+ -over / -down),
-- arrows 17x11. Same keys as the template (Track, Track.Thumb, Back, Forward),
-- so the Tinted / Flat code treats both alike.

-- Draws an atlas turned a quarter left: its top edge on the left, so the
-- "top" arrow points left. Returns the atlas width, height (unturned).
-- keepEnd = only the last keepEnd px of the atlas (its bottom end): the
-- thumb's bottom piece is 36 px with a long dark fade, which turned sideways
-- read as a smeared tail (Dukul 2026-10-08), so only its 8 px end is used.
local function SetAtlasTurned(tex, atlas, keepEnd, otherWay)
    local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
    if not info then return nil end
    tex:SetTexture(info.file or info.filename)
    local l, r, t, b = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
    local h = info.height
    if keepEnd and h and h > keepEnd then
        t = b - (b - t) * keepEnd / h
        h = keepEnd
    end
    -- corners UL, LL, UR, LR of the drawn rect <- texture points; otherWay =
    -- turned a quarter right instead (top edge on the right)
    if otherWay then
        tex:SetTexCoord(l, b, r, b, l, t, r, t)
    else
        tex:SetTexCoord(r, t, l, t, r, b, l, b)
    end
    return info.width, h
end

local THICK, ARROW_LEN, ARROW_H = 8, 11, 17

-- A three-piece run along x: caps at their atlas length, middle stretched
local function Pieces(owner, layer, prefix)
    local p = {
        a = owner:CreateTexture(nil, layer),
        m = owner:CreateTexture(nil, layer),
        z = owner:CreateTexture(nil, layer),
    }
    function p.Set(suffix)
        suffix = suffix or ""
        local _, ha = SetAtlasTurned(p.a, prefix .. "-top" .. suffix)
        SetAtlasTurned(p.m, (prefix:find("track") and "!" or "") .. prefix .. "-middle" .. suffix)
        -- The thumb's art is lighter towards its bottom end (Dukul 2026-10-08:
        -- "The right side of the dragger is tinted wrong"): its right end is
        -- the top cap turned the other way, so both ends match
        local _, hz
        if prefix:find("thumb") then
            _, hz = SetAtlasTurned(p.z, prefix .. "-top" .. suffix, nil, true)
        else
            _, hz = SetAtlasTurned(p.z, prefix .. "-bottom" .. suffix, THICK)
        end
        p.a:ClearAllPoints(); p.a:SetPoint("TOPLEFT"); p.a:SetSize(ha or THICK, THICK)
        p.z:ClearAllPoints(); p.z:SetPoint("TOPRIGHT"); p.z:SetSize(hz or THICK, THICK)
        p.m:ClearAllPoints()
        p.m:SetPoint("TOPLEFT", p.a, "TOPRIGHT"); p.m:SetPoint("BOTTOMRIGHT", p.z, "BOTTOMLEFT")
        p.capLen = (ha or THICK) + (hz or THICK)
    end
    return p
end

local function MakeArrow(bar, atlas)
    local btn = CreateFrame("Button", nil, bar)
    btn:SetSize(ARROW_LEN, ARROW_H)
    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    local over, down = false, false
    local function Draw() SetAtlasTurned(tex, atlas .. (down and "-down" or over and "-over" or "")) end
    btn:SetScript("OnEnter", function() over = true; Draw() end)
    btn:SetScript("OnLeave", function() over = false; down = false; Draw() end)
    btn:SetScript("OnMouseDown", function() down = true; Draw() end)
    btn:SetScript("OnMouseUp", function() down = false; Draw() end)
    Draw()
    return btn
end

local function MakeHorizontal(parent)
    local host = CreateFrame("Frame", nil, parent)
    host:SetSize(COL_W, 44)
    local sf = CreateFrame("ScrollFrame", nil, host)
    sf:SetPoint("TOPLEFT"); sf:SetPoint("TOPRIGHT"); sf:SetHeight(20)
    local child = CreateFrame("Frame", nil, sf)
    local fs = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", 2, 0)
    fs:SetText(LONG_LINE)
    child:SetSize(fs:GetStringWidth() + 8, 20)
    sf:SetScrollChild(child)

    local bar = CreateFrame("Frame", nil, host)
    bar:SetPoint("TOPLEFT", sf, "BOTTOMLEFT", 0, -4)
    bar:SetPoint("TOPRIGHT", sf, "BOTTOMRIGHT", 0, -4)
    bar:SetHeight(ARROW_H)
    bar.Back    = MakeArrow(bar, "minimal-scrollbar-arrow-top")
    bar.Forward = MakeArrow(bar, "minimal-scrollbar-arrow-bottom")
    bar.Back:SetPoint("LEFT")
    bar.Forward:SetPoint("RIGHT")

    local track = CreateFrame("Frame", nil, bar)
    track:SetPoint("LEFT", bar.Back, "RIGHT", 3, 0)
    track:SetPoint("RIGHT", bar.Forward, "LEFT", -3, 0)
    track:SetHeight(THICK)
    bar.Track = track
    local tp = Pieces(track, "BACKGROUND", "minimal-scrollbar-track")
    tp.Set()

    local thumb = CreateFrame("Button", nil, track)
    thumb:SetHeight(THICK)
    track.Thumb = thumb
    local hp = Pieces(thumb, "ARTWORK", "minimal-scrollbar-thumb")
    hp.Set()

    -- Scroll state: pct 0..1 of the range, thumb length from the visible share
    local pct, range = 0, 0
    local function Layout()
        local trackW = track:GetWidth()
        local viewW, fullW = sf:GetWidth(), child:GetWidth()
        range = math.max(0, fullW - viewW)
        local len = math.max(hp.capLen + 4, trackW * math.min(1, viewW / math.max(1, fullW)))
        thumb:SetWidth(len)
        thumb:ClearAllPoints()
        thumb:SetPoint("LEFT", track, "LEFT", pct * math.max(0, trackW - len), 0)
        sf:SetHorizontalScroll(pct * range)
    end
    local function SetPct(v) pct = math.max(0, math.min(1, v)); Layout() end
    bar.Back:HookScript("OnClick", function() SetPct(pct - 0.1) end)
    bar.Forward:HookScript("OnClick", function() SetPct(pct + 0.1) end)
    host:EnableMouseWheel(true)
    host:SetScript("OnMouseWheel", function(_, d) SetPct(pct - d * 0.1) end)

    -- Drag: follow the pointer from where the press started
    local over, drag = false, nil
    local function DrawThumb() hp.Set(drag and "-down" or over and "-over" or "") end
    thumb:SetScript("OnEnter", function() over = true; DrawThumb() end)
    thumb:SetScript("OnLeave", function() over = false; DrawThumb() end)
    thumb:SetScript("OnMouseDown", function()
        drag = { x = GetCursorPosition() / thumb:GetEffectiveScale(), pct = pct }
        DrawThumb()
    end)
    thumb:SetScript("OnMouseUp", function() drag = nil; DrawThumb() end)
    thumb:SetScript("OnUpdate", function()
        if not drag then return end
        local free = track:GetWidth() - thumb:GetWidth()
        if free <= 0 then return end
        local x = GetCursorPosition() / thumb:GetEffectiveScale()
        SetPct(drag.pct + (x - drag.x) / free)
    end)
    host:SetScript("OnSizeChanged", Layout)
    C_Timer.After(0, Layout)
    return host, bar, "the minimal scrollbar's art, turned (no horizontal template in the game)"
end

-- ── Window ───────────────────────────────────────────────────────────────────
local function Build()
    panel = B().CreateToolWindow({
        name = "BNBDevSkinWidgetsTest", w = W, h = 560,
        title = "Skin widgets test (ALL-393 / ALL-80)", toplevel = true, escClose = true,
    })
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    local top = -((panel._isSkin and B().TOOL_SKIN_TITLE_H or 36) + 10)

    local note = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", PAD, top)
    note:SetWidth(W - PAD * 2); note:SetJustifyH("LEFT")
    note:SetText("Open lists are pictures; a click on a dropdown opens the game's real menu. Change the skin preset in Settings and this follows.")
    top = top - 30

    local hUsed, firstBar
    for col, kind in ipairs({ "game", "tint", "flat" }) do
        local x = PAD + (col - 1) * (COL_W + GAP)
        local hdr = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        hdr:SetPoint("TOPLEFT", x, top)
        hdr:SetText(kind == "game" and "Game (today)" or kind == "tint" and "Tinted (game art)" or "Flat (drawn)")
        local y = top - 22

        local dd = MakeDropdown(panel)
        dd:SetPoint("TOPLEFT", x, y)
        if kind == "tint" then refreshers[#refreshers + 1] = TintDropdown(dd)
        elseif kind == "flat" then refreshers[#refreshers + 1] = FlatDropdown(dd, panel) end
        y = y - 30

        local list, listRun = MockList(panel, kind)
        list:SetPoint("TOPLEFT", x, y)
        refreshers[#refreshers + 1] = listRun
        y = y - (#LIST_ROWS * ROW_H + 12) - 14

        local sf = MakeVertical(panel, 150)
        sf:SetPoint("TOPLEFT", x, y)
        if kind == "game" then firstBar = sf.ScrollBar end
        if sf.ScrollBar then
            if kind == "tint" then refreshers[#refreshers + 1] = TintBar(sf.ScrollBar)
            elseif kind == "flat" then refreshers[#refreshers + 1] = FlatBar(sf.ScrollBar) end
        end
        y = y - 150 - 16

        local host, hbar, used = MakeHorizontal(panel)
        host:SetPoint("TOPLEFT", x, y)
        hUsed = used
        if hbar then
            if kind == "tint" then refreshers[#refreshers + 1] = TintBar(hbar)
            elseif kind == "flat" then refreshers[#refreshers + 1] = FlatBar(hbar, true) end
        end
    end

    local hNote = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hNote:SetPoint("BOTTOMLEFT", PAD, 70)
    hNote:SetText("Horizontal bar: " .. tostring(hUsed) .. ". BigNoteBox has no horizontal scrollbar today.")

    -- Real sizes for the handle art (ALL-393): the game column's vertical bar,
    -- read once it has been laid out
    local sizeNote = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sizeNote:SetPoint("BOTTOMLEFT", hNote, "TOPLEFT", 0, 4)
    panel._sizeNote = sizeNote
    panel._measureBar = firstBar

    local slider = B().CreateStackedSlider(panel, 260, {
        label = "Tint strength", min = 0.5, max = 3, step = 0.1, value = strength, default = 1.6,
        onChange = function(v)
            strength = v
            for _, fn in ipairs(refreshers) do pcall(fn) end
        end,
    })
    slider:SetPoint("BOTTOMLEFT", PAD, 16)

    if B().RegisterMessage then
        B().RegisterMessage("BNBDevSkinWidgets", "SkinChanged", function()
            for _, fn in ipairs(refreshers) do pcall(fn) end
        end)
    end
end

SLASH_BNBSKINWIDGETS1 = "/bnbskinw"
SlashCmdList.BNBSKINWIDGETS = function()
    if not BigNoteBox or not BigNoteBox.CreateToolWindow then return end
    if not panel then Build() end
    panel:SetShown(not panel:IsShown())
    if panel:IsShown() then
        panel:Raise()
        for _, fn in ipairs(refreshers) do pcall(fn) end
        C_Timer.After(0.2, function()
            local bar, fs = panel._measureBar, panel._sizeNote
            if not (bar and fs) then return end
            local _, thumb = Parts(bar)
            fs:SetText(string.format("Vertical bar: %d px wide; thumb %s x %s px (client template %s)",
                math.floor(bar:GetWidth() + 0.5),
                thumb and math.floor(thumb:GetWidth() + 0.5) or "?",
                thumb and math.floor(thumb:GetHeight() + 0.5) or "?",
                tostring(SCROLL_FRAME_SCROLL_BAR_TEMPLATE)))
        end)
    end
end

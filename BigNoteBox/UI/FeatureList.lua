-- BigNoteBox UI/FeatureList.lua
--
-- "Features in BigNoteBox" window, opened from the More Features button
-- in Settings > General. Shows all BNB features as scrollable sections.
--
-- PUBLIC API:
--   BNB.FeatureList.Open()   -- opens the window, hides BNB and companions
--   BNB.FeatureList.Close()  -- closes window, restores BNB and companions
--
-- DATA:
--   BNB.FEATURE_LIST  (defined in UI/FeatureListData.lua)
--   Array of { header, blurb, items={} } sections.
--
-- WINDOW SIZING:
--   Width  : FL_W (580px) -- wider than WhatsNew
--   Height : grows with content from FL_MIN_H up to FL_MAX_H
--   When content exceeds max: scrollbar appears
--
-- CHROME:
--   Normal mode : ButtonFrameTemplate
--   Skin mode   : BNB.CreateSkinFrame + BNB.CreateSkinStrip title bar
--
-- CAMERA ORBIT:
--   Uses FO.StartForSetup() / FO.StopForSetup() to bypass IsFocusModeOpen guard.
--
-- OVERLAY:
--   Full-screen cosmetic dimmer behind the window (click-through).
--   Skin-colour tinted when skin mode + focusOverlayUseSkinColor is set.

local BNB = BigNoteBox

BNB.FeatureList = BNB.FeatureList or {}
local FL = BNB.FeatureList

-- ── Tweakable constants ───────────────────────────────────────────────────────
local FL_W          = 580       -- window width
local FL_MIN_H      = 420       -- minimum window height
local FL_MAX_H      = 820       -- maximum window height (clipped by screen if needed)
local PAD           = 18        -- horizontal and vertical padding inside scroll area
local TITLE_H_N     = 28        -- ButtonFrameTemplate title bar height (normal mode)
local TITLE_H_S     = 26        -- skin mode title bar height
local OK_BTN_H      = 44        -- height of the bottom OK button
local OK_BTN_PAD    = 10        -- padding above and below OK button area
local SECTION_GAP   = 18        -- vertical gap between sections
local HEADER_SIZE   = 14        -- section header font size (px)
local BLURB_SIZE    = 12        -- blurb font size (px)
local ITEM_SIZE     = 12        -- bullet item font size (px)
local BLURB_GAP     = 6         -- gap between header and blurb
local ITEMS_GAP     = 6         -- gap between blurb and first item
local ITEM_GAP      = 3         -- gap between bullet items
local FADE_TIME     = 0.25      -- open/close fade duration (seconds)
-- Glow (LibCustomGlow-1.0)
local GLOW_COLOR    = { 0.400, 0.733, 0.416, 1.0 }   -- BNB green
local GLOW_N        = 15
local GLOW_FREQ     = 0.03
local GLOW_SCALE    = 1.5
local GLOW_KEY      = "bnb_featurelist"
-- Bullet prefix
local BULLET        = "|cff66bb6a*|r "

-- ── Module state ──────────────────────────────────────────────────────────────
local _frame   = nil
local _overlay = nil
local _isOpen  = false   -- true between Open() and Close() completing

-- ── FadeTo helper (self-contained, mirrors FocusEditor) ───────────────────────
-- Cancels any running OnUpdate on `target` before starting a new one.
local function FadeTo(target, fromAlpha, toAlpha, duration, onDone)
    target:SetScript("OnUpdate", nil)   -- cancel any in-flight fade first
    local elapsed = 0
    target:SetAlpha(fromAlpha)
    target:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        local t = math.min(elapsed / duration, 1)
        self:SetAlpha(fromAlpha + (toAlpha - fromAlpha) * t)
        if t >= 1 then
            self:SetScript("OnUpdate", nil)
            if onDone then onDone() end
        end
    end)
end

-- ── Glow ─────────────────────────────────────────────────────────────────────
local _lcg = nil
local function GetLCG()
    if not _lcg then _lcg = LibStub and LibStub("LibCustomGlow-1.0", true) end
    return _lcg
end

local function StartGlow(f)
    local lcg = GetLCG()
    if lcg and f then
        pcall(lcg.AutoCastGlow_Start, f, GLOW_COLOR, GLOW_N, GLOW_FREQ, GLOW_SCALE, nil, nil, GLOW_KEY)
    end
end

local function StopGlow(f)
    local lcg = GetLCG()
    if lcg and f then
        pcall(lcg.AutoCastGlow_Stop, f, GLOW_KEY)
    end
end

-- ── Overlay ───────────────────────────────────────────────────────────────────
local function _overlayColor()
    local db = BigNoteBoxDB
    if db and db.skinMode and db.focusOverlayUseSkinColor
       and BNB.GetSkinPreset and BNB.SkinColourOf then
        return BNB.SkinColourOf(BNB.GetSkinPreset(), false)
    end
    return 0, 0, 0
end

local function GetOverlay()
    if _overlay then return _overlay end
    local ov = CreateFrame("Frame", nil, UIParent)
    ov:SetAllPoints()
    ov:SetFrameStrata("DIALOG")
    ov:SetFrameLevel(90)       -- below the window (level 100+)
    ov:EnableMouse(false)      -- click-through; purely cosmetic
    local tex = ov:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints()
    tex:SetColorTexture(0, 0, 0, 1)
    ov._tex = tex
    ov:Hide()
    if BNB.RegisterSkinBackdrop then
        BNB.RegisterSkinBackdrop(function()
            if ov:IsShown() then
                local r, g, b = _overlayColor()
                ov._tex:SetColorTexture(r, g, b, 0.6)
            end
        end)
    end
    _overlay = ov
    return ov
end

local function ShowOverlay()
    local ov = GetOverlay()
    local r, g, b = _overlayColor()
    ov._tex:SetColorTexture(r, g, b, 0.6)
    ov:Show()
    FadeTo(ov, 0, 1, FADE_TIME)
end

local function HideOverlay()
    if _overlay then
        FadeTo(_overlay, _overlay:GetAlpha(), 0, FADE_TIME, function()
            if _overlay then _overlay:Hide() end
        end)
    end
end

-- ── Window snapshot helpers ───────────────────────────────────────────────────
-- Mirrors the pattern in FocusEditor but scoped to only BNB's own frames.
local _snap = nil

local function SnapshotAndHide()
    local function shown(name)
        local f = _G[name]; return f and f:IsShown()
    end
    _snap = {
        mainFrame    = BNB.mainFrame and BNB.mainFrame:IsShown(),
        noteConfig   = shown("BigNoteBoxNoteConfigFrame"),
        config       = shown("BigNoteBoxConfigFrame"),
        trash        = shown("BigNoteBoxTrashFrame"),
        tagManager   = shown("BigNoteBoxTagManagerFrame"),
        historyWin   = shown("BigNoteBoxHistoryFrame"),
        historyPanel = shown("BigNoteBoxNoteHistoryFrame"),
        refBox       = shown("BigNoteBoxReferenceBoxFrame"),
        sendToChat   = shown("BigNoteBoxSendDialog"),
        richPreview  = BNB.RichPreview and BNB.RichPreview.IsOpen(),
    }
    -- Close everything via the standard helper then also hide main
    BNB.CloseCompanionWindows()
    if BNB.mainFrame and BNB.mainFrame:IsShown() then
        BNB.mainFrame:Hide()
    end
    -- Hide stickies
    if BNB.Sticky and BNB.Sticky.HideAll then
        _snap.hadStickies = true
        BNB.Sticky.HideAll()
    end
end

local function RestoreSnapshot()
    if not _snap then return end
    local snap = _snap
    _snap = nil

    if snap.mainFrame and BNB.mainFrame then
        BNB.mainFrame:Show()
    end
    if snap.hadStickies and BNB.Sticky and BNB.Sticky.ShowAll then
        BNB.Sticky.ShowAll()
    end
    C_Timer.After(0.05, function()
        if snap.noteConfig  and BNB.OpenNoteConfig        then BNB.OpenNoteConfig(BNB._currentNoteID)  end
        if snap.trash       then
            local tw = _G["BigNoteBoxTrashFrame"]
            if tw then tw:Show() end
        end
        if snap.tagManager  and BNB.ToggleTagManager      then BNB.ToggleTagManager()                  end
        if snap.historyWin  and BNB.OpenHistoryWindow     then BNB.OpenHistoryWindow()                 end
        if snap.historyPanel and BNB.OpenNoteHistoryPanel then BNB.OpenNoteHistoryPanel(BNB._currentNoteID) end
        if snap.refBox      and BNB.OpenReferenceBox      then BNB.OpenReferenceBox(BNB._currentNoteID) end
        if snap.sendToChat  and BNB.OpenSendToChat        then BNB.OpenSendToChat(BNB._currentNoteID)  end
        if snap.richPreview and BNB.RichPreview           then BNB.RichPreview.Open()                  end
    end)
end

-- ── Window chrome builders ────────────────────────────────────────────────────
local TITLE_TEXT = "Features in BigNoteBox"

local function BuildFrameNormal(onClose)
    local f = CreateFrame("Frame", "BigNoteBoxFeatureListFrame", UIParent, "ButtonFrameTemplate")
    f:SetToplevel(true)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(100)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    ButtonFrameTemplate_HidePortrait(f)
    ButtonFrameTemplate_HideButtonBar(f)
    if f.Inset then f.Inset:Hide() end
    f:SetTitle(TITLE_TEXT)
    if f.CloseButton then f.CloseButton:SetScript("OnClick", onClose) end
    -- ESC handled via OnKeyDown below; do NOT add to UISpecialFrames
    -- (UISpecialFrames calls Hide() directly, bypassing FL.Close())
    f:EnableKeyboard(true)
    f:SetScript("OnKeyDown", function(self, key)
        if key ~= "ESCAPE" then self:SetPropagateKeyboardInput(true); return end
        self:SetPropagateKeyboardInput(false)
        onClose()
    end)
    return f, TITLE_H_N
end

local function BuildFrameSkin(onClose)
    local f = BNB.CreateSkinFrame(UIParent, false, "BigNoteBoxFeatureListFrame", false)
    _G["BigNoteBoxFeatureListFrame"] = f
    f:SetToplevel(true)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(100)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)

    local titleBar = BNB.CreateSkinStrip(f, true, false)
    titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    titleBar:SetHeight(TITLE_H_S)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
    titleBar:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

    local titleLbl = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleLbl:SetPoint("CENTER", titleBar, "CENTER", -12, 0)
    titleLbl:SetTextColor(1, 0.82, 0)
    titleLbl:SetText(TITLE_TEXT)

    local closeBtn = BNB.CreateSkinCloseButton(titleBar, onClose)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -3, 0)

    f:SetScript("OnShow", function()
        if BNB.ApplyMainWindowSkin then BNB.ApplyMainWindowSkin() end
    end)

    -- ESC handled via OnKeyDown; do NOT add to UISpecialFrames
    f:EnableKeyboard(true)
    f:SetScript("OnKeyDown", function(self, key)
        if key ~= "ESCAPE" then self:SetPropagateKeyboardInput(true); return end
        self:SetPropagateKeyboardInput(false)
        onClose()
    end)

    return f, TITLE_H_S
end

-- ── Build window (once; rebuilds if skin mode changed) ────────────────────────
local function BuildWindow()
    local skinMode = BigNoteBoxDB and BigNoteBoxDB.skinMode and true or false

    if _frame and _frame._builtSkin ~= skinMode then
        _frame:Hide()
        _frame:SetParent(nil)
        _frame = nil
    end
    if _frame then return _frame end

    local onClose = function() FL.Close() end

    local f, titleH
    if skinMode and BNB.CreateSkinFrame then
        f, titleH = BuildFrameSkin(onClose)
    else
        f, titleH = BuildFrameNormal(onClose)
    end
    f._titleH    = titleH
    f._builtSkin = skinMode

    -- ── OK button — pinned to bottom ──────────────────────────────────────────
    local okArea = CreateFrame("Frame", nil, f)
    okArea:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  PAD,  PAD)
    okArea:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD)
    okArea:SetHeight(OK_BTN_H + OK_BTN_PAD)
    f._okArea = okArea

    local okBtn
    if skinMode then
        okBtn = BNB.CreateSkinButton(nil, okArea, BNB.RandomOkPhrase(),
                    okArea:GetWidth() or (FL_W - PAD * 2), OK_BTN_H, 16)
    else
        local tpl = "SharedButtonLargeTemplate"
        if not (C_XMLUtil and C_XMLUtil.GetTemplateInfo
                and C_XMLUtil.GetTemplateInfo(tpl)) then
            tpl = "UIPanelDynamicResizeButtonTemplate"
        end
        if not (C_XMLUtil and C_XMLUtil.GetTemplateInfo
                and C_XMLUtil.GetTemplateInfo(tpl)) then
            tpl = "UIPanelButtonTemplate"
        end
        okBtn = CreateFrame("Button", nil, okArea, tpl)
        okBtn:SetSize(okArea:GetWidth() or (FL_W - PAD * 2), OK_BTN_H)
        pcall(function() DynamicResizeButton_Resize(okBtn) end)
        okBtn:SetText(BNB.RandomOkPhrase())
        local bfs = okBtn:GetFontString()
        if bfs then pcall(function() bfs:SetFont("Fonts\\FRIZQT__.TTF", 16, "") end) end
    end
    okBtn:SetPoint("BOTTOM", okArea, "BOTTOM", 0, 0)
    f._okBtn = okBtn
    okBtn:SetScript("OnClick", onClose)

    f:HookScript("OnShow", function()
        local w = okArea:GetWidth()
        if w and w > 0 then okBtn:SetWidth(w) end
    end)

    -- ── Scroll area — between title and OK button ─────────────────────────────
    local BOTTOM_CHROME = OK_BTN_H + OK_BTN_PAD * 2 + PAD

    local sf = CreateFrame("ScrollFrame", nil, f, "ScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     f, "TOPLEFT",  PAD,  -(titleH + PAD))
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -24, BOTTOM_CHROME)
    f._sf = sf

    local bar = sf.ScrollBar
    if bar then bar:SetAlpha(0) end

    local ct = CreateFrame("Frame", nil, sf)
    ct:SetWidth(FL_W - PAD * 2 - 24)
    ct:SetHeight(1)
    sf:SetScrollChild(ct)
    f._ct = ct

    sf:HookScript("OnSizeChanged", function()
        local sfH = sf:GetHeight()
        if sfH < 4 then return end
        local ctH = ct._contentH or 0
        ct:SetHeight(math.max(ctH, sfH))
        if bar then bar:SetAlpha(ctH > sfH + 2 and 1 or 0) end
    end)

    f:Hide()
    _frame = f
    return f
end

-- ── Populate sections into scroll content ─────────────────────────────────────
-- ── Button asset constants ────────────────────────────────────────────────────
local BTN_ASSETS = "Interface\\AddOns\\BigNoteBox\\Assets\\Buttons\\"
local BTN_SZ     = 18   -- arrow button size (matches TagTree and AlarmWindow)
local HEADER_H   = 24   -- height of each accordion header row

-- ── Arrow button factory ──────────────────────────────────────────────────────
-- Creates a texture-based arrow button (bt-right/bt-down) on `parent`.
-- Returns the button and the three texture references for later swapping.
local function MakeArrowBtn(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(BTN_SZ, BTN_SZ)
    btn:SetHighlightTexture("")
    btn:SetPushedTexture("")

    local norm  = btn:CreateTexture(nil, "ARTWORK"); norm:SetAllPoints()
    local hover = btn:CreateTexture(nil, "ARTWORK"); hover:SetAllPoints()
    local press = btn:CreateTexture(nil, "ARTWORK"); press:SetAllPoints()

    norm:SetTexture(BTN_ASSETS  .. "bt-right-normal")
    hover:SetTexture(BTN_ASSETS .. "bt-right-hover");  hover:Hide()
    press:SetTexture(BTN_ASSETS .. "bt-right-press");  press:Hide()

    btn:SetScript("OnEnter",     function() norm:Hide();  hover:Show() end)
    btn:SetScript("OnLeave",     function() hover:Hide(); press:Hide(); norm:Show() end)
    btn:SetScript("OnMouseDown", function() press:Show(); norm:Hide();  hover:Hide() end)
    btn:SetScript("OnMouseUp",   function() press:Hide(); hover:Show() end)

    return btn, norm, hover, press
end

-- Swap all three textures on an arrow button to collapsed or expanded state.
local function SetArrow(norm, hover, press, expanded)
    local n = expanded and BTN_ASSETS .. "bt-down-normal"  or BTN_ASSETS .. "bt-right-normal"
    local h = expanded and BTN_ASSETS .. "bt-down-hover"   or BTN_ASSETS .. "bt-right-hover"
    local p = expanded and BTN_ASSETS .. "bt-down-press"   or BTN_ASSETS .. "bt-right-press"
    norm:SetTexture(n); hover:SetTexture(h); press:SetTexture(p)
    hover:Hide(); press:Hide(); norm:Show()
end

-- ── Populate with accordion ───────────────────────────────────────────────────
local function PopulateContent(ct, sf)
    -- Destroy any previously created child frames (GetRegions only gets
    -- FontStrings/textures; frames must be tracked and hidden separately)
    if ct._accordionFrames then
        for _, f in ipairs(ct._accordionFrames) do
            f:Hide()
            f:SetParent(nil)
        end
    end
    for _, region in ipairs({ ct:GetRegions() }) do
        region:Hide()
        region:SetParent(nil)
    end
    ct._accordionFrames = {}

    local innerW  = ct:GetWidth()
    local textW   = innerW - BTN_SZ - 8   -- text width accounting for arrow
    local sections = BNB.FEATURE_LIST or {}
    local bar      = sf and sf.ScrollBar

    -- ── Pre-measure content heights ───────────────────────────────────────────
    -- Use a hidden measurer frame so GetStringHeight() resolves correctly.
    local measurer = CreateFrame("Frame", nil, ct)
    measurer:SetSize(textW - 8, 400)
    measurer:Hide()
    tinsert(ct._accordionFrames, measurer)

    local function MeasureSection(section)
        local h = 4  -- top padding inside content frame
        -- Blurb
        if section.blurb and section.blurb ~= "" then
            local mfs = measurer:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
            mfs:SetFont("Fonts\\FRIZQT__.TTF", BLURB_SIZE, "")
            mfs:SetWidth(textW - 8)
            mfs:SetWordWrap(true)
            mfs:SetSpacing(2)
            mfs:SetText(section.blurb)
            h = h + math.max(mfs:GetStringHeight(), BLURB_SIZE + 2) + ITEMS_GAP
        end
        -- Items
        for _, item in ipairs(section.items or {}) do
            local mfs = measurer:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
            mfs:SetFont("Fonts\\FRIZQT__.TTF", ITEM_SIZE, "")
            mfs:SetWidth(textW - 16)
            mfs:SetWordWrap(true)
            mfs:SetSpacing(1)
            mfs:SetText(BULLET .. item)
            h = h + math.max(mfs:GetStringHeight(), ITEM_SIZE + 2) + ITEM_GAP
        end
        return h + 8  -- bottom padding
    end

    -- ── Build section data table ───────────────────────────────────────────────
    local secs = {}
    for _, section in ipairs(sections) do
        secs[#secs + 1] = {
            data     = section,
            isOpen   = false,
            contentH = MeasureSection(section),
        }
    end

    -- ── RefreshLayout ─────────────────────────────────────────────────────────
    -- Recalculates y positions for all headers and content frames.
    -- Must be defined before the loop so OnClick closures can reference it.
    local function RefreshLayout()
        local cy = -PAD
        for _, sec in ipairs(secs) do
            -- Reposition header button
            sec.hdrBtn:ClearAllPoints()
            sec.hdrBtn:SetPoint("TOPLEFT",  ct, "TOPLEFT",  0, cy)
            sec.hdrBtn:SetPoint("TOPRIGHT", ct, "TOPRIGHT", 0, cy)
            cy = cy - HEADER_H

            -- Separator line sits at bottom of header
            sec.sep:ClearAllPoints()
            sec.sep:SetPoint("BOTTOMLEFT",  sec.hdrBtn, "BOTTOMLEFT",  0, 0)
            sec.sep:SetPoint("BOTTOMRIGHT", sec.hdrBtn, "BOTTOMRIGHT", 0, 0)

            -- Content frame
            if sec.isOpen then
                sec.content:ClearAllPoints()
                sec.content:SetPoint("TOPLEFT",  ct, "TOPLEFT",  BTN_SZ + 8, cy)
                sec.content:SetPoint("TOPRIGHT", ct, "TOPRIGHT", 0,          cy)
                sec.content:Show()
                cy = cy - sec.contentH - 4
            else
                sec.content:Hide()
            end
        end
        ct:SetHeight(math.abs(cy) + PAD)
        ct._contentH = math.abs(cy) + PAD

        -- Update scrollbar visibility
        if bar then
            C_Timer.After(0.05, function()
                local ctH = ct:GetHeight()
                local sfH = sf:GetHeight()
                bar:SetAlpha(ctH > sfH + 2 and 1 or 0)
            end)
        end
    end

    -- ── Create header buttons and content frames ───────────────────────────────
    for _, sec in ipairs(secs) do
        -- Header button (full width, captures hover and click)
        local hdrBtn = CreateFrame("Button", nil, ct)
        hdrBtn:SetHeight(HEADER_H)
        hdrBtn:RegisterForClicks("LeftButtonUp")
        sec.hdrBtn = hdrBtn
        tinsert(ct._accordionFrames, hdrBtn)

        -- Hover highlight
        local hlTex = hdrBtn:CreateTexture(nil, "HIGHLIGHT")
        hlTex:SetAllPoints()
        hlTex:SetColorTexture(1, 1, 1, 0.05)

        -- Arrow button (forwards clicks to hdrBtn)
        local arBtn, arNorm, arHover, arPress = MakeArrowBtn(hdrBtn)
        arBtn:SetPoint("LEFT", hdrBtn, "LEFT", 0, 0)
        arBtn:SetScript("OnClick", function() hdrBtn:Click() end)
        sec.arNorm = arNorm; sec.arHover = arHover; sec.arPress = arPress

        -- Section header label
        local lbl = hdrBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetFont("Fonts\\FRIZQT__.TTF", HEADER_SIZE, "")
        lbl:SetPoint("LEFT", arBtn, "RIGHT", 4, 0)
        lbl:SetPoint("RIGHT", hdrBtn, "RIGHT", -4, 0)
        lbl:SetJustifyH("LEFT")
        lbl:SetWordWrap(false)
        lbl:SetTextColor(1, 0.82, 0)
        lbl:SetText(sec.data.header or "")

        -- Separator line
        local sep = hdrBtn:CreateTexture(nil, "ARTWORK")
        sep:SetHeight(1)
        sep:SetColorTexture(0.2, 0.2, 0.25, 1)
        sec.sep = sep

        -- Content frame (blurb + bullets)
        local content = CreateFrame("Frame", nil, ct)
        content:SetHeight(sec.contentH)
        content:Hide()
        sec.content = content
        tinsert(ct._accordionFrames, content)

        local cy2 = -4
        if sec.data.blurb and sec.data.blurb ~= "" then
            local blurb = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
            blurb:SetFont("Fonts\\FRIZQT__.TTF", BLURB_SIZE, "")
            blurb:SetPoint("TOPLEFT", content, "TOPLEFT", 0, cy2)
            blurb:SetWidth(textW - 8)
            blurb:SetJustifyH("LEFT")
            blurb:SetWordWrap(true)
            blurb:SetSpacing(2)
            blurb:SetTextColor(0.75, 0.75, 0.75)
            blurb:SetText(sec.data.blurb)
            cy2 = cy2 - math.max(blurb:GetStringHeight(), BLURB_SIZE + 2) - ITEMS_GAP
        end
        for _, item in ipairs(sec.data.items or {}) do
            local fs = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
            fs:SetFont("Fonts\\FRIZQT__.TTF", ITEM_SIZE, "")
            fs:SetPoint("TOPLEFT", content, "TOPLEFT", 8, cy2)
            fs:SetWidth(textW - 16)
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(true)
            fs:SetSpacing(1)
            fs:SetTextColor(0.88, 0.88, 0.88)
            fs:SetText(BULLET .. item)
            cy2 = cy2 - math.max(fs:GetStringHeight(), ITEM_SIZE + 2) - ITEM_GAP
        end

        -- Click: close all others, then toggle this section
        hdrBtn:SetScript("OnClick", function()
            local wasOpen = sec.isOpen
            for _, s in ipairs(secs) do
                s.isOpen = false
                SetArrow(s.arNorm, s.arHover, s.arPress, false)
            end
            sec.isOpen = not wasOpen
            SetArrow(sec.arNorm, sec.arHover, sec.arPress, sec.isOpen)
            RefreshLayout()
        end)
    end

    -- Initial render — all collapsed
    RefreshLayout()

    -- Return total collapsed height (all headers only) for window sizing
    local collapsedH = PAD + #secs * HEADER_H + PAD
    return collapsedH
end

-- ── Size window to fit content ────────────────────────────────────────────────
local function ApplyWindowHeight(f, contentH)
    local chrome = f._titleH + PAD + (OK_BTN_H + OK_BTN_PAD * 2 + PAD) + PAD
    local ideal  = contentH + chrome
    local maxH   = math.min(FL_MAX_H, math.floor(UIParent:GetHeight() * 0.92))
    local final  = math.max(FL_MIN_H, math.min(ideal, maxH))
    f:SetSize(FL_W, final)

    local sf  = f._sf
    local ct  = f._ct
    local bar = sf and sf.ScrollBar
    if sf and ct then
        local sfH = sf:GetHeight()
        if sfH < 4 then
            C_Timer.After(0.05, function()
                sfH = sf:GetHeight()
                ct:SetHeight(math.max(contentH, sfH))
                if bar then bar:SetAlpha(contentH > sfH + 2 and 1 or 0) end
            end)
        else
            ct:SetHeight(math.max(contentH, sfH))
            if bar then bar:SetAlpha(contentH > sfH + 2 and 1 or 0) end
        end
    end
end

-- ── Public: Open ──────────────────────────────────────────────────────────────
function FL.Open()
    if _isOpen then return end
    if not BNB.FEATURE_LIST then return end
    _isOpen = true

    local f = BuildWindow()

    if f._okBtn then f._okBtn:SetText(BNB.RandomOkPhrase()) end

    -- Cancel any in-flight close fade so the frame starts clean
    f:SetScript("OnUpdate", nil)
    f:SetAlpha(0.95)

    -- Snapshot and hide all BNB windows
    SnapshotAndHide()

    -- Populate accordion and size to collapsed height
    local contentH = PopulateContent(f._ct, f._sf)
    f:ClearAllPoints()
    f:SetPoint("CENTER")
    ApplyWindowHeight(f, contentH)

    f:Show()
    f:Raise()
    StartGlow(f)

    -- Overlay: cancel any in-flight hide fade, show fresh
    local ov = GetOverlay()
    ov:SetScript("OnUpdate", nil)
    ShowOverlay()
    ov:SetFrameLevel(math.max(1, f:GetFrameLevel() - 1))

    -- Camera orbit (bypasses IsFocusModeOpen guard)
    C_Timer.After(FADE_TIME, function()
        if _isOpen then
            local FO = BNB.FocusOrbit
            if FO then FO.StartForSetup() end
        end
    end)
end

-- ── Public: Close ─────────────────────────────────────────────────────────────
function FL.Close()
    if not _isOpen then return end
    _isOpen = false

    -- Stop camera orbit
    local FO = BNB.FocusOrbit
    if FO then FO.StopForSetup() end

    -- Cancel any overlay fade and hide immediately
    if _overlay then
        _overlay:SetScript("OnUpdate", nil)
        _overlay:Hide()
    end

    -- Cancel any frame fade and hide immediately
    if _frame then
        StopGlow(_frame)
        _frame:SetScript("OnUpdate", nil)
        _frame:Hide()
        _frame:SetAlpha(0.95)  -- reset alpha for next open
    end

    RestoreSnapshot()
end

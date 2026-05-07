-- BigNoteBox UI/WhatsNew.lua
--
-- "What's New?" popup shown once per version after an update.
-- Also openable at any time via the version button in Settings > General.
--
-- PUBLIC API:
--   BNB.WhatsNew.Open(showOverlay)   -- showOverlay: true = auto-popup, false = manual open
--   BNB.WhatsNew.Close()
--   BNB.WhatsNew.CheckAndShow()      -- called on login; shows if version is new
--
-- DATA:
--   BNB.PATCH_NOTES  (defined in UI/WhatsNewData.lua)
--     .version  string  -- must match BNB.ADDON_VERSION to trigger auto-show
--     .entries  table   -- array of plain strings, one per bullet
--
-- PERSISTENCE:
--   BigNoteBoxDB.lastSeenWhatsNewVersion  -- set to version on close; cleared on version bump
--
-- WINDOW SIZING:
--   Width  : CFG_W (480px) -- same as ConfigWindow
--   Height : grows with content from WN_MIN_H (300px) up to mainFrame:GetHeight() cap
--   When content exceeds cap: scrollbar appears, window stays at cap height
--
-- CHROME:
--   Normal mode : ButtonFrameTemplate (matches ConfigWindow)
--   Skin mode   : BNB.CreateSkinFrame + BNB.CreateSkinStrip title bar
--
-- OVERLAY:
--   Cosmetic full-screen dimmer behind the window (auto-popup only).
--   EnableMouse(false) -- click-through; does not block game interaction.
--   Skin mode + focusOverlayUseSkinColor: tinted with skin preset colour.
--   Dismissed when window closes.

local BNB = BigNoteBox
local L   = BNB.L

BNB.WhatsNew = BNB.WhatsNew or {}
local WN = BNB.WhatsNew

-- ── Layout constants ──────────────────────────────────────────────────────────
local CFG_W       = 480     -- matches ConfigWindow
local WN_MIN_H    = 300     -- window grows from this minimum
local PAD         = 16
local TITLE_H_N   = 28      -- ButtonFrameTemplate title bar (normal mode)
local TITLE_H_S   = 26      -- skin title bar
local OK_BTN_H    = 44      -- height of the OK button
local OK_BTN_PAD  = 10      -- padding above and below OK button area
local ENTRY_PAD_X = 12      -- horizontal padding inside scroll area
local ENTRY_GAP   = 6       -- vertical gap between entries
local ENTRY_FONT_SIZE = 13  -- patch note entry font size in pixels (increase to fit fewer lines, decrease for more)
local BULLET      = "|cff66bb6a·|r "   -- BNB green bullet prefix

-- ── Module state ──────────────────────────────────────────────────────────────
local _frame    = nil   -- the window frame (built once, reused)
local _overlay  = nil   -- the cosmetic dimmer (built once, reused)

-- ── AutoCast glow (LibCustomGlow-1.0) ─────────────────────────────────────────
-- Resolves after PLAYER_LOGIN; nil-safe everywhere via pcall.
local LCG        = nil
local GLOW_KEY   = "bnb_whatsnew"
local GLOW_COLOR = { 0.400, 0.733, 0.416, 1.0 }  -- BNB green
local GLOW_N     = 15
local GLOW_FREQ  = 0.03
local GLOW_SCALE = 1.5

local function StartGlow(f)
    if not f then return end
    if not LCG then
        LCG = LibStub and LibStub("LibCustomGlow-1.0", true)
    end
    if LCG then
        pcall(LCG.AutoCastGlow_Start, f, GLOW_COLOR, GLOW_N, GLOW_FREQ, GLOW_SCALE, nil, nil, GLOW_KEY)
    end
end

local function StopGlow(f)
    if not f or not LCG then return end
    pcall(LCG.AutoCastGlow_Stop, f, GLOW_KEY)
end

-- ── Overlay ───────────────────────────────────────────────────────────────────
local function _overlayColor()
    local db = BigNoteBoxDB
    if db and db.skinMode and db.focusOverlayUseSkinColor
       and BNB.GetSkinPreset and BNB.SkinColourOf then
        local preset = BNB.GetSkinPreset()
        return BNB.SkinColourOf(preset, false)
    end
    return 0, 0, 0
end

local function GetOverlay()
    if _overlay then return _overlay end
    local ov = CreateFrame("Frame", nil, UIParent)
    ov:SetAllPoints()
    ov:SetFrameStrata("DIALOG")  -- window is also DIALOG; lower frame level keeps overlay behind
    ov:SetFrameLevel(1)
    ov:EnableMouse(false)       -- cosmetic only; clicks pass through
    local tex = ov:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints()
    tex:SetColorTexture(0, 0, 0, 1)
    ov._tex = tex
    ov:Hide()
    -- Re-tint when skin changes
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
end

local function HideOverlay()
    if _overlay then _overlay:Hide() end
end

-- ── Height calculation ────────────────────────────────────────────────────────
local function GetMaxHeight()
    if BNB.mainFrame then
        local h = BNB.mainFrame:GetHeight()
        if h and h > 100 then return h end
    end
    -- Fallback: use ConfigWindow helper if available
    if BNB._GetConfigTargetHeight then
        return BNB._GetConfigTargetHeight()
    end
    return math.min(math.max(math.floor(UIParent:GetHeight() * 0.75), WN_MIN_H), 900)
end

-- ── Content height measurement ────────────────────────────────────────────────
-- Measures how tall all entries will be when rendered, so we can size the
-- window before showing it. Uses a hidden measuring FontString.
local _measureFS = nil
local function MeasureContentHeight(entries, availableW)
    if not _measureFS then
        _measureFS = UIParent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        _measureFS:Hide()
    end
    _measureFS:SetFont("Fonts\\FRIZQT__.TTF", ENTRY_FONT_SIZE, "")
    _measureFS:SetWidth(availableW)
    _measureFS:SetWordWrap(true)

    local total = PAD  -- top padding
    for _, entry in ipairs(entries or {}) do
        _measureFS:SetText(BULLET .. entry)
        local h = _measureFS:GetStringHeight()
        total = total + math.max(h, 14) + ENTRY_GAP
    end
    total = total + PAD  -- bottom padding
    return total
end

-- ── Window chrome: normal mode ────────────────────────────────────────────────
local function BuildFrameNormal(onClose)
    local f = CreateFrame("Frame", "BigNoteBoxWhatsNewFrame", UIParent, "ButtonFrameTemplate")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    f:SetAlpha(0.95)
    f:SetFrameStrata("DIALOG")

    ButtonFrameTemplate_HidePortrait(f)
    ButtonFrameTemplate_HideButtonBar(f)
    if f.Inset then f.Inset:Hide() end
    f:SetTitle("What's new in BigNoteBox v" .. (BNB.ADDON_VERSION or "?"))

    if f.CloseButton then
        f.CloseButton:SetScript("OnClick", onClose)
    end

    tinsert(UISpecialFrames, "BigNoteBoxWhatsNewFrame")

    return f, TITLE_H_N
end

-- ── Window chrome: skin mode ──────────────────────────────────────────────────
local function BuildFrameSkin(onClose)
    local f = BNB.CreateSkinFrame(UIParent, false, "BigNoteBoxWhatsNewFrame", false)
    _G["BigNoteBoxWhatsNewFrame"] = f
    f:SetToplevel(true)
    f:SetFrameStrata("DIALOG")
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
    titleLbl:SetText("What's new in BigNoteBox v" .. (BNB.ADDON_VERSION or "?"))

    local closeBtn = BNB.CreateSkinCloseButton(titleBar, onClose)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -3, 0)

    f:SetScript("OnShow", function()
        if BNB.ApplyMainWindowSkin then BNB.ApplyMainWindowSkin() end
    end)

    tinsert(UISpecialFrames, "BigNoteBoxWhatsNewFrame")

    return f, TITLE_H_S
end

-- ── Build the window (once) ───────────────────────────────────────────────────
local function BuildWindow()
    local skinMode = BigNoteBoxDB and BigNoteBoxDB.skinMode and true or false

    -- Rebuild if skin mode changed since the frame was first created
    if _frame and _frame._builtSkin ~= skinMode then
        _frame:Hide()
        _frame:SetParent(nil)
        _frame = nil
    end

    if _frame then return _frame end

    local onClose = function() WN.Close() end

    local f, titleH
    if skinMode and BNB.CreateSkinFrame then
        f, titleH = BuildFrameSkin(onClose)
    else
        f, titleH = BuildFrameNormal(onClose)
    end

    -- Store titleH on frame for content positioning
    f._titleH = titleH

    -- ── OK button area — fixed at bottom, always visible ──────────────────────
    -- Anchored to the bottom of the frame BEFORE the scroll area so it's
    -- always accessible regardless of content length.
    local okArea = CreateFrame("Frame", nil, f)
    okArea:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  PAD,  PAD)
    okArea:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD)
    okArea:SetHeight(OK_BTN_H + OK_BTN_PAD)
    f._okArea = okArea

    local okBtn
    if skinMode then
        okBtn = BNB.CreateSkinButton(nil, okArea, BNB.RandomOkPhrase(), okArea:GetWidth() or (CFG_W - PAD * 2), OK_BTN_H, 16)
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
        okBtn:SetSize(okArea:GetWidth() or (CFG_W - PAD * 2), OK_BTN_H)
        pcall(function() DynamicResizeButton_Resize(okBtn) end)
        okBtn:SetText(BNB.RandomOkPhrase())
        local bfs = okBtn:GetFontString()
        if bfs then pcall(function() bfs:SetFont("Fonts\\FRIZQT__.TTF", 16, "") end) end
    end
    okBtn:SetPoint("BOTTOM", okArea, "BOTTOM", 0, 0)
    f._okBtn = okBtn
    okBtn:SetScript("OnClick", onClose)

    -- The OK area width is not valid at build time (frame not laid out yet).
    -- Re-set it when the frame is shown so the button fills correctly.
    f:HookScript("OnShow", function()
        local w = okArea:GetWidth()
        if w and w > 0 then okBtn:SetWidth(w) end
    end)

    -- ── Scroll area — fills between title bar and OK area ─────────────────────
    local BOTTOM_CHROME = OK_BTN_H + OK_BTN_PAD * 2 + PAD

    local sf = CreateFrame("ScrollFrame", nil, f, "ScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     f,  "TOPLEFT",  PAD,  -(titleH + PAD))
    sf:SetPoint("BOTTOMRIGHT", f,  "BOTTOMRIGHT", -24, BOTTOM_CHROME)
    f._sf = sf

    local bar = sf.ScrollBar
    if bar then bar:SetAlpha(0) end

    local ct = CreateFrame("Frame", nil, sf)
    ct:SetWidth(CFG_W - PAD * 2 - 24)
    ct:SetHeight(1)
    sf:SetScrollChild(ct)
    f._ct = ct

    -- Scrollbar auto-show/hide
    sf:HookScript("OnSizeChanged", function()
        local sfH = sf:GetHeight()
        if sfH < 4 then return end
        local ctH = ct._contentH or 0
        ct:SetHeight(math.max(ctH, sfH))
        if bar then
            bar:SetAlpha(ctH > sfH + 2 and 1 or 0)
        end
    end)

    f:Hide()
    f._builtSkin = skinMode
    _frame = f
    return f
end

-- ── Populate entries into the scroll content frame ────────────────────────────
local function PopulateEntries(ct, entries)
    -- Clear old children
    for _, child in ipairs({ ct:GetRegions() }) do
        child:Hide()
        child:SetParent(nil)
    end

    local availW = ct:GetWidth() - ENTRY_PAD_X * 2
    local y = -PAD
    for _, entry in ipairs(entries or {}) do
        local fs = ct:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        fs:SetFont("Fonts\\FRIZQT__.TTF", ENTRY_FONT_SIZE, "")
        fs:SetPoint("TOPLEFT", ct, "TOPLEFT", ENTRY_PAD_X, y)
        fs:SetWidth(availW)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true)
        fs:SetSpacing(2)
        fs:SetTextColor(0.88, 0.88, 0.88)
        fs:SetText(BULLET .. entry)
        local h = fs:GetStringHeight()
        if h < 14 then h = 14 end
        y = y - h - ENTRY_GAP
    end
    y = y - PAD

    local contentH = math.abs(y)
    ct._contentH = contentH
    return contentH
end

-- ── Size the window to fit content ───────────────────────────────────────────
local function ApplyWindowHeight(f, contentH)
    local maxH  = GetMaxHeight()
    local chrome = f._titleH + PAD + (OK_BTN_H + OK_BTN_PAD * 2 + PAD) + PAD
    local ideal  = contentH + chrome
    local final  = math.max(WN_MIN_H, math.min(ideal, maxH))
    f:SetSize(CFG_W, final)

    -- Update scroll child height and scrollbar visibility
    local sf  = f._sf
    local ct  = f._ct
    local bar = sf and sf.ScrollBar
    if sf and ct then
        local sfH = sf:GetHeight()
        if sfH < 4 then
            -- Not laid out yet; defer one tick
            C_Timer.After(0.05, function()
                sfH = sf:GetHeight()
                ct:SetHeight(math.max(contentH, sfH))
                if bar then
                    bar:SetAlpha(contentH > sfH + 2 and 1 or 0)
                end
            end)
        else
            ct:SetHeight(math.max(contentH, sfH))
            if bar then
                bar:SetAlpha(contentH > sfH + 2 and 1 or 0)
            end
        end
    end
end

-- ── Public: Open ─────────────────────────────────────────────────────────────
-- showOverlay: true  = auto-popup path (dimmer visible)
--              false = manual open from version button (no dimmer)
function WN.Open(showOverlay)
    local data = BNB.PATCH_NOTES
    if not data then return end

    local f = BuildWindow()

    -- Randomize OK button label on each open
    if f._okBtn then f._okBtn:SetText(BNB.RandomOkPhrase()) end

    -- Populate entries and measure
    local contentH = PopulateEntries(f._ct, data.entries)

    -- Position CENTER before sizing so GetHeight() is valid when we check maxH
    f:ClearAllPoints()
    f:SetPoint("CENTER")

    ApplyWindowHeight(f, contentH)
    f:Show()
    f:Raise()
    StartGlow(f)

    -- Ensure overlay strata is just below the window
    if showOverlay then
        ShowOverlay()
        -- Pull overlay just below the window frame level
        local ov = GetOverlay()
        ov:SetFrameLevel(math.max(1, f:GetFrameLevel() - 1))
    else
        HideOverlay()
    end
end

-- ── Public: Close ─────────────────────────────────────────────────────────────
function WN.Close()
    HideOverlay()
    if _frame then
        StopGlow(_frame)
        _frame:Hide()
    end
    -- Mark this version as seen so it won't auto-show again
    local data = BNB.PATCH_NOTES
    if data and data.version and BigNoteBoxDB then
        BigNoteBoxDB.lastSeenWhatsNewVersion = data.version
    end
end

-- ── Public: CheckAndShow ──────────────────────────────────────────────────────
-- Called on PLAYER_LOGIN after Initialize(). Shows with overlay if the
-- current version hasn't been seen yet. No-op otherwise.
function WN.CheckAndShow()
    local data = BNB.PATCH_NOTES
    if not data or not data.version then return end
    local db = BigNoteBoxDB
    if not db then return end
    if db.lastSeenWhatsNewVersion == data.version then return end
    WN.Open(true)
end

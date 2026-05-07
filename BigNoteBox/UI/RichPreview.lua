-- BigNoteBox UI/RichPreview.lua
-- Live preview companion window for rich notes.
--
-- MAIN PREVIEW  (BNB.RichPreview)
--   Standard movable companion window, default right of main window.
--   Height tracks the main window height live (OnSizeChanged hook).
--   Only visible when a rich note is open in EDITOR mode (never in view mode).
--   Opens automatically when a rich note in editor mode is selected and
--   db.richPreviewAutoShow == true (default). Toggle via "Live Preview" button.
--   Skin-aware: ButtonFrameTemplate in normal mode, CreateSkinFrame in skin mode.
--   ESC does NOT close it. Closing the main window closes it.
--   Debounced re-render: 0.6s after last MarkDirty, or on note switch.
--
-- FOCUS PREVIEW  (BNB.RichPreviewFocus)
--   Owned by focus mode. Spawned when focus mode opens if:
--     - db.focusPreviewAlwaysShow == true  (always open for rich notes), OR
--     - main preview was visible at the time focus mode was entered
--   Same width/height as the focus frame (480x640), positioned to its right.
--   Skin-aware: same chrome as main preview.

local BNB = BigNoteBox
local L   = BNB.L

local PREVIEW_W      = 380    -- default width of the main preview window
local PAD            = 8
local CONTENT_PAD    = 14    -- extra horizontal padding for rendered content
local TITLE_H_NORMAL = 28     -- ButtonFrameTemplate title bar
local TITLE_H_SKIN   = 26     -- skin title bar height
local DEBOUNCE_DEFAULT = 0.3
local FRAME_NAME       = "BigNoteBoxRichPreviewFrame"
local FOCUS_FRAME_NAME = "BigNoteBoxRichPreviewFocusFrame"

local function GetDebounceDelay()
    return BigNoteBoxDB and BigNoteBoxDB.previewDebounce or DEBOUNCE_DEFAULT
end

local RP  = {}   -- main preview module
local RPF = {}   -- focus preview module
BNB.RichPreview      = RP
BNB.RichPreviewFocus = RPF

--------------------------------------------------------------------------------
-- SHARED: build a render scroll+SimpleHTML pair inside a parent frame.
-- titleH: pixel offset from frame top to content area start.
-- Returns (scrollFrame, renderFrame).
--------------------------------------------------------------------------------
local function BuildRenderPair(name, parent, titleH)
    local AM = BNB.AdvancedMode
    local rsf = CreateFrame("ScrollFrame", name .. "Scroll", parent, "ScrollFrameTemplate")
    rsf:SetPoint("TOPLEFT",     parent, "TOPLEFT",  CONTENT_PAD, -(titleH + PAD))
    rsf:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -(CONTENT_PAD + 16), PAD)

    local scrollBar = rsf.ScrollBar
    if scrollBar then
        scrollBar:SetAlpha(0)
        rsf:HookScript("OnScrollRangeChanged", function(_, _, yRange)
            scrollBar:SetAlpha((yRange or 0) > 1 and 1.0 or 0)
        end)
    end

    local rf = AM.CreateRenderFrame(name .. "RF", rsf)
    rf:SetWidth(rsf:GetWidth() > 0 and rsf:GetWidth() or (PREVIEW_W - CONTENT_PAD * 2 - 16))
    rf:SetHeight(1)
    rsf:SetScrollChild(rf)

    rsf:HookScript("OnSizeChanged", function(self)
        local w = self:GetWidth()
        if w and w > 0 then rf:SetWidth(w) end
    end)

    return rsf, rf
end

--------------------------------------------------------------------------------
-- SHARED: render a note into a (rsf, rf) pair.
-- gen: caller-owned { n = 0 } — stale deferred ticks are dropped.
-- liveBody (optional): if provided, used instead of note.body. This is needed
-- because note.body only updates on save — during editing, the editbox text
-- is ahead of the saved note object.
-- cursorRatio (optional 0..1): proportional cursor position in the source text.
-- When provided, the scroll frame scrolls to the corresponding position in
-- the rendered output so the user's editing area stays visible.
--------------------------------------------------------------------------------
local function RenderNote(note, rsf, rf, gen, liveBody, cursorRatio)
    if not note or not note.richMode then return end
    local AM = BNB.AdvancedMode
    if not AM then return end

    local bodyText = liveBody or note.body or ""

    local myGen
    if gen then
        gen.n = gen.n + 1
        myGen = gen.n
    end

    C_Timer.After(0, function()
        if gen and gen.n ~= myGen then return end
        if not rsf:IsShown() then return end

        local w = rsf:GetWidth()
        if w and w > 0 then rf:SetWidth(w) end

        local sz = note.fontSize or (BigNoteBoxDB and BigNoteBoxDB.fontSize) or 12
        local fs = BNB.AdvancedMode.OutlineFlagStr(note.fontOutline)
        AM.ApplyFontsToRenderFrame(rf, sz, fs)

        local html = AM.ToHTML(bodyText, sz)
        local rawST = getmetatable(rf).__index.SetText
        rawST(rf, html)
        local contentH = rf:GetContentHeight()
        rf:SetHeight(contentH)

        if cursorRatio and cursorRatio > 0 then
            local viewH = rsf:GetHeight()
            local maxScroll = math.max(0, contentH - viewH)
            rsf:SetVerticalScroll(math.min(maxScroll, maxScroll * cursorRatio))
        else
            rsf:SetVerticalScroll(0)
        end
    end)
end

--------------------------------------------------------------------------------
-- SHARED: build a skin or normal preview frame.
-- Returns (frame, titleH).
--------------------------------------------------------------------------------
local function BuildFrameSkin(frameName, onClose, frameParent)
    frameParent = frameParent or UIParent
    local f = BNB.CreateSkinFrame(frameParent, false, frameName, false)
    _G[frameName] = f
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)

    local titleBar = BNB.CreateSkinStrip(f, true, false)
    titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    titleBar:SetHeight(TITLE_H_SKIN)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
    titleBar:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

    local titleLbl = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleLbl:SetPoint("CENTER", titleBar, "CENTER", -12, 0)
    titleLbl:SetTextColor(1, 0.82, 0)
    titleLbl:SetText(L["RICH_PREVIEW_TITLE"])

    local closeBtn = BNB.CreateSkinCloseButton(titleBar, onClose)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -3, 0)

    f:SetScript("OnShow", function()
        if BNB.ApplyMainWindowSkin then BNB.ApplyMainWindowSkin() end
    end)

    return f, TITLE_H_SKIN
end

local function BuildFrameNormal(frameName, onClose, frameParent)
    frameParent = frameParent or UIParent
    local f = CreateFrame("Frame", frameName, frameParent, "ButtonFrameTemplate")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetResizable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    f:SetAlpha(0.95)

    ButtonFrameTemplate_HidePortrait(f)
    ButtonFrameTemplate_HideButtonBar(f)
    if f.Inset then f.Inset:Hide() end
    f:SetTitle(L["RICH_PREVIEW_TITLE"])

    if f.CloseButton then
        f.CloseButton:SetScript("OnClick", onClose)
    end

    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" then
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
            f:StartSizing("BOTTOMRIGHT")
        end
    end)
    grip:SetScript("OnMouseUp", function(self, btn)
        if btn == "LeftButton" then f:StopMovingOrSizing() end
    end)

    return f, TITLE_H_NORMAL
end

--------------------------------------------------------------------------------
-- MAIN PREVIEW WINDOW
--------------------------------------------------------------------------------
local _mainFrame     = nil
local _mainRSF       = nil
local _mainRF        = nil
local _debounceTimer = nil
local _mainGen       = { n = 0 }
local _heightHooked  = false

local function SyncMainHeight()
    if not _mainFrame then return end
    if not BNB.mainFrame then return end
    local mh = BNB.mainFrame:GetHeight()
    local fh = _mainFrame:GetHeight()
    if mh and mh > 200 and fh and math.abs(fh - mh) > 2 then
        _mainFrame:SetHeight(mh)
    end
end

local function HookMainHeight()
    if _heightHooked then return end
    _heightHooked = true
    if BNB.mainFrame then
        BNB.mainFrame:HookScript("OnSizeChanged", SyncMainHeight)
        BNB.mainFrame:HookScript("OnShow",        SyncMainHeight)
    end
end

local function BuildMainFrame()
    if _mainFrame then return _mainFrame end

    local mh = BNB.mainFrame and BNB.mainFrame:GetHeight()
    local h = (mh and mh > 200) and mh or 580

    local skinMode = BigNoteBoxDB and BigNoteBoxDB.skinMode

    local onClose = function()
        _mainFrame:Hide()
        RP.UpdateToggleBtn()
    end

    local f, titleH
    if skinMode and BNB.CreateSkinFrame then
        f, titleH = BuildFrameSkin(FRAME_NAME, onClose)
    else
        f, titleH = BuildFrameNormal(FRAME_NAME, onClose)
    end

    f:SetSize(PREVIEW_W, h)

    _mainRSF, _mainRF = BuildRenderPair(FRAME_NAME, f, titleH)

    f:Hide()
    _mainFrame = f
    HookMainHeight()
    return f
end

local function GetLiveBody()
    local eb = BNB._editorBody
    if eb and not eb._showingPlaceholder then return eb:GetText() end
    return nil
end

local function GetCursorRatio(eb)
    if not eb then return nil end
    local pos = eb:GetCursorPosition() or 0
    local len = (eb:GetText() or ""):len()
    if len == 0 then return 0 end
    return pos / len
end

local function DoRender()
    _debounceTimer = nil
    if not _mainFrame or not _mainFrame:IsShown() then return end
    local note = BNB._currentNoteID and BNB.GetNote(BNB._currentNoteID)
    local eb = BNB._editorBody
    RenderNote(note, _mainRSF, _mainRF, _mainGen, GetLiveBody(), GetCursorRatio(eb))
end

function RP.ScheduleRender()
    if not _mainFrame then return end
    if _debounceTimer then _debounceTimer:Cancel(); _debounceTimer = nil end
    _debounceTimer = C_Timer.NewTimer(GetDebounceDelay(), DoRender)
end

function RP.RenderNote(note)
    if _debounceTimer then _debounceTimer:Cancel(); _debounceTimer = nil end
    if not _mainFrame or not _mainFrame:IsShown() then return end
    RenderNote(note, _mainRSF, _mainRF, _mainGen)
end

function RP.Open()
    BuildMainFrame()
    SyncMainHeight()

    if not _mainFrame:IsShown() then
        _mainFrame:Show()
        if BNB.mainFrame and BNB.mainFrame:IsShown() then
            _mainFrame:ClearAllPoints()
            _mainFrame:SetPoint("TOPLEFT", BNB.mainFrame, "TOPRIGHT", 8, 0)
        else
            _mainFrame:ClearAllPoints()
            _mainFrame:SetPoint("CENTER")
        end
    end

    RP.UpdateToggleBtn()
    DoRender()
end

function RP.Close()
    if _debounceTimer then _debounceTimer:Cancel(); _debounceTimer = nil end
    if _mainFrame then _mainFrame:Hide() end
    RP.UpdateToggleBtn()
end

function RP.IsOpen()
    return _mainFrame ~= nil and _mainFrame:IsShown()
end

function RP.Toggle()
    if RP.IsOpen() then RP.Close() else RP.Open() end
end

-- Update markup bar toggle buttons on both main and focus bars
function RP.UpdateToggleBtn()
    local open = RP.IsOpen()
    if BNB._markupPreviewBtn then
        BNB._markupPreviewBtn:SetAlpha(open and 1.0 or 0.45)
    end
    -- Focus bar button reflects focus preview state independently
    if BNB._focusMarkupPreviewBtn then
        BNB._focusMarkupPreviewBtn:SetAlpha(RPF.IsOpen() and 1.0 or 0.45)
    end
end

-- Called after a note is selected. Opens/renders only in editor mode.
function RP.OnNoteSelected(note)
    if not note or not note.richMode then
        if RP.IsOpen() then RP.Close() end
        return
    end

    -- Never show preview in view mode
    if BNB._editorInViewMode then
        if RP.IsOpen() then RP.Close() end
        return
    end

    local db = BigNoteBoxDB
    local autoShow = db == nil or db.richPreviewAutoShow ~= false

    if autoShow and not RP.IsOpen() then
        RP.Open()
    elseif RP.IsOpen() then
        RP.RenderNote(note)
    end

    RP.UpdateToggleBtn()
end

function RP.OnNoteCleared()
    if RP.IsOpen() then RP.Close() end
end

function BNB.CloseRichPreview()
    RP.Close()
end

--------------------------------------------------------------------------------
-- FOCUS MODE PREVIEW WINDOW
--------------------------------------------------------------------------------
local _focusFrame = nil
local _focusRSF   = nil
local _focusRF    = nil
local _focusGen   = { n = 0 }

local function BuildFocusPreviewFrame(w, h)
    if not _focusFrame then
        local skinMode = BigNoteBoxDB and BigNoteBoxDB.skinMode

        local onClose = function()
            _focusFrame:Hide()
            if BNB._focusMarkupPreviewBtn then
                BNB._focusMarkupPreviewBtn:SetAlpha(0.45)
            end
        end

        local f, titleH
        if skinMode and BNB.CreateSkinFrame then
            f, titleH = BuildFrameSkin(FOCUS_FRAME_NAME, onClose, WorldFrame)
        else
            f, titleH = BuildFrameNormal(FOCUS_FRAME_NAME, onClose, WorldFrame)
        end

        f:SetFrameStrata("FULLSCREEN_DIALOG")

        _focusRSF, _focusRF = BuildRenderPair(FOCUS_FRAME_NAME, f, titleH)
        f:Hide()
        _focusFrame = f
    end

    _focusFrame:SetSize(w, h)
    return _focusFrame
end

function RPF.Open(focusFrame, simultaneous)
    if not focusFrame then return end
    local note = BNB._currentNoteID and BNB.GetNote(BNB._currentNoteID)
    -- Focus preview: only for rich notes; focus mode has no view mode so no
    -- _editorInViewMode check needed here
    if not note or not note.richMode then return end

    local fw = focusFrame:GetWidth()
    local fh = focusFrame:GetHeight()
    if not fw or fw < 100 then fw = 480 end
    if not fh or fh < 100 then fh = 640 end

    BuildFocusPreviewFrame(fw, fh)

    -- When opening simultaneously with the focus frame, shift both windows so
    -- the pair is centered: editor moves left by half (previewW + gap), preview
    -- anchors to its right. Gap is 8px. previewW == fw (same size as editor).
    -- GetCenter() returns UIParent-space units — no scale conversion needed.
    if simultaneous then
        local shift = math.floor((fw + 8) / 2)
        local cx, cy = focusFrame:GetCenter()
        if cx and cy then
            focusFrame:ClearAllPoints()
            focusFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx - shift, cy)
        end
    end

    _focusFrame:ClearAllPoints()
    _focusFrame:SetPoint("TOPLEFT", focusFrame, "TOPRIGHT", 8, 0)
    _focusFrame:Show()
    _focusFrame:Raise()

    if BNB._focusMarkupPreviewBtn then
        BNB._focusMarkupPreviewBtn:SetAlpha(1.0)
    end

    RenderNote(note, _focusRSF, _focusRF, _focusGen)
end

function RPF.Close()
    _focusGen.n = _focusGen.n + 1
    if _focusDebounceTimer then _focusDebounceTimer:Cancel(); _focusDebounceTimer = nil end
    if _focusFrame then _focusFrame:Hide() end
    if BNB._focusMarkupPreviewBtn then
        BNB._focusMarkupPreviewBtn:SetAlpha(0.45)
    end
end

function RPF.IsOpen()
    return _focusFrame ~= nil and _focusFrame:IsShown()
end

function RPF.Toggle(focusFrame)
    if RPF.IsOpen() then RPF.Close() else RPF.Open(focusFrame) end
end

local function GetFocusLiveBody()
    local eb = BNB._focusEditorBody
    if eb and not eb._showingPlaceholder then return eb:GetText() end
    return nil
end

local _focusDebounceTimer = nil

local function DoFocusRender()
    _focusDebounceTimer = nil
    if not _focusFrame or not _focusFrame:IsShown() then return end
    local note = BNB._currentNoteID and BNB.GetNote(BNB._currentNoteID)
    local eb = BNB._focusEditorBody
    RenderNote(note, _focusRSF, _focusRF, _focusGen, GetFocusLiveBody(), GetCursorRatio(eb))
end

function RPF.ScheduleRefresh()
    if not _focusFrame then return end
    if _focusDebounceTimer then _focusDebounceTimer:Cancel(); _focusDebounceTimer = nil end
    _focusDebounceTimer = C_Timer.NewTimer(GetDebounceDelay(), DoFocusRender)
end

function RPF.Refresh()
    if not _focusFrame or not _focusFrame:IsShown() then return end
    local note = BNB._currentNoteID and BNB.GetNote(BNB._currentNoteID)
    local eb = BNB._focusEditorBody
    RenderNote(note, _focusRSF, _focusRF, _focusGen, GetFocusLiveBody(), GetCursorRatio(eb))
end

--------------------------------------------------------------------------------
-- HOOKS
--------------------------------------------------------------------------------

hooksecurefunc(BNB, "MarkDirty", function()
    RP.ScheduleRender()
    if RPF.IsOpen() then
        RPF.ScheduleRefresh()
    end
end)

-- Entering view mode: hide both preview windows
hooksecurefunc(BNB, "AM_EnterViewMode", function()
    if RP.IsOpen() then RP.Close() end
    if RPF.IsOpen() then RPF.Close() end
end)

-- Entering edit mode: re-show preview if appropriate
hooksecurefunc(BNB, "AM_EnterEditMode", function()
    local note = BNB._currentNoteID and BNB.GetNote(BNB._currentNoteID)
    if not note or not note.richMode then return end

    -- Main preview
    local db = BigNoteBoxDB
    local autoShow = db == nil or db.richPreviewAutoShow ~= false
    if autoShow and not RP.IsOpen() then
        RP.Open()
    elseif RP.IsOpen() then
        RP.ScheduleRender()
    end

    -- Focus preview: re-open if focus mode is active and always-show is on
    if BNB.IsFocusModeOpen and BNB.IsFocusModeOpen() then
        local alwaysShow = db == nil or db.focusPreviewAlwaysShow ~= false
        if alwaysShow and not RPF.IsOpen() then
            local ff = _G["BigNoteBoxFocusFrame"] or _G["BigNoteBoxFocusFrameSkin"]
            RPF.Open(ff)
        elseif RPF.IsOpen() then
            RPF.Refresh()
        end
    end
end)

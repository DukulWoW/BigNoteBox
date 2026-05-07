-- BigNoteBox UI/FocusEditor.lua
-- Focus Mode: a stripped-down window showing only the current note's
-- title, timestamps, body, and Save button.
--
-- Fixed size: width matches ConfigWindow (480px), height matches MainWindow
-- default (640px). Not resizable — clean focused writing surface.
--
-- Opening: appears centred on the main window; main fades out, focus fades in.
-- Closing: main reappears exactly where focus is; focus fades out.

local BNB = BigNoteBox
local L   = BNB.L

local FOCUS_W   = 480   -- matches ConfigWindow width (CFG_W = 480)
local FOCUS_H   = 640   -- matches MainWindow DEFAULT_H
local PAD       = 8
local TSTAMP_H  = 16
local TOOLBAR_H = 36
local TITLE_H   = 54    -- ButtonFrameTemplate title bar height
local FADE_TIME = 0.18  -- seconds for cross-fade

-- Fixed pixel offset for body scroll top anchor (relative to content top):
--   36px titleBg + 1px gap + 1px underline + 2px gap + TSTAMP_H + 4px gap
local BODY_TOP_OFFSET = -(36 + 1 + 1 + 2 + TSTAMP_H + 4)
local FOCUS_MARKUP_H = 24  -- height of the rich note markup toolbar in focus mode

-- Module-level refs (all set inside BuildFocusFrame)
local focusFrame
local focusTitleEb
local focusTitleBg
local focusTitleUl
local focusTsStrip
local focusStatsStrip   -- right-aligned char/word count on the same row
local focusBodyScroll
local focusBodyEb
local focusSaveBtn
local focusSpinBtn      -- orbit toggle button (set in both builders)
local focusDirty = false
local focusMarkupBar    -- rich note markup toolbar

--------------------------------------------------------------------------------
-- FADE HELPER  (local copy of StickyNote.lua FadeTo pattern)
--------------------------------------------------------------------------------
local function FadeTo(target, fromAlpha, toAlpha, duration, onDone)
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

-- Dark overlay behind the focus frame (created once, lives on WorldFrame)
local focusOverlay

local function _overlayColor()
    local db = BigNoteBoxDB
    if db and db.skinMode and db.focusOverlayUseSkinColor
       and BNB.GetSkinPreset and BNB.SkinColourOf then
        local preset = BNB.GetSkinPreset()
        local r, g, b = BNB.SkinColourOf(preset, false)
        return r, g, b
    end
    return 0, 0, 0
end

local function GetFocusOverlay()
    if focusOverlay then return focusOverlay end
    local ov = CreateFrame("Frame", nil, WorldFrame)
    ov:SetAllPoints(UIParent)
    ov:SetFrameStrata("BACKGROUND")
    ov:SetFrameLevel(1)
    local tex = ov:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints()
    tex:SetColorTexture(0, 0, 0, 1)
    ov._tex = tex
    ov:SetAlpha(0)
    ov:Hide()
    -- Hide immediately on combat start
    local ef = CreateFrame("Frame")
    ef:RegisterEvent("PLAYER_REGEN_DISABLED")
    ef:SetScript("OnEvent", function()
        if ov:IsShown() then ov:SetScript("OnUpdate", nil); ov:Hide() end
    end)
    -- Register for skin color refresh
    if BNB.RegisterSkinBackdrop then
        BNB.RegisterSkinBackdrop(function()
            if ov:IsShown() then
                local r, g, b = _overlayColor()
                local db = BigNoteBoxDB
                local alpha = (db and db.focusOverlayAlpha) or 0.6
                ov._tex:SetColorTexture(r, g, b, alpha)
            end
        end)
    end
    focusOverlay = ov
    return ov
end

local function ShowFocusOverlay()
    local db    = BigNoteBoxDB
    local alpha = (db and db.focusOverlayAlpha) or 0.6
    if alpha <= 0 then return end
    local ov  = GetFocusOverlay()
    local r, g, b = _overlayColor()
    ov._tex:SetColorTexture(r, g, b, alpha)
    ov:Show()
    FadeTo(ov, 0, 1, 0.6)  -- fade the frame alpha in over 0.6s
end

local function HideFocusOverlay()
    if not focusOverlay or not focusOverlay:IsShown() then return end
    focusOverlay:Hide()
end

--------------------------------------------------------------------------------
-- AFK OVERLAY
-- A second full-screen overlay that appears ON TOP of the focus overlay and
-- the focus frame when the player goes AFK during focus mode.
-- Protects OLED screens. 90% opacity black (or skin-tinted like focus overlay).
-- Triggered by PLAYER_FLAGS_CHANGED / UnitIsAFK("player").
--------------------------------------------------------------------------------
local _afkOverlay = nil
local HideAfkOverlay  -- forward declaration (defined below)

local function GetAfkOverlay()
    if _afkOverlay then return _afkOverlay end
    local ov = CreateFrame("Frame", nil, UIParent)
    ov:SetAllPoints(UIParent)
    ov:SetFrameStrata("FULLSCREEN_DIALOG")
    ov:SetFrameLevel(200)
    local tex = ov:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints()
    ov._tex = tex
    ov:Hide()

    -- Dismiss on mouse movement (uses frame fields so ShowAfkOverlay can reset them)
    ov:SetScript("OnUpdate", function(self)
        local x, y = GetCursorPosition()
        if self._lastX == nil then
            self._lastX, self._lastY = x, y
        elseif x ~= self._lastX or y ~= self._lastY then
            self._lastX, self._lastY = x, y
            HideAfkOverlay()
        end
    end)

    -- Dismiss on any keypress (ESC stays as overlay-only dismiss, propagates nothing)
    ov:EnableKeyboard(true)
    ov:SetPropagateKeyboardInput(false)
    ov:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            -- ESC: dismiss overlay only, do not close focus mode
            self:SetPropagateKeyboardInput(false)
        else
            -- Any other key: dismiss overlay and let the key through
            self:SetPropagateKeyboardInput(true)
        end
        HideAfkOverlay()
    end)

    _afkOverlay = ov
    return ov
end

local function _afkOverlayColor()
    local db = BigNoteBoxDB
    if db and db.skinMode and db.focusOverlayUseSkinColor
       and BNB.GetSkinPreset and BNB.SkinColourOf then
        local preset = BNB.GetSkinPreset()
        local r, g, b = BNB.SkinColourOf(preset, false)
        return r, g, b
    end
    return 0, 0, 0
end

local function ShowAfkOverlay()
    if not focusFrame or not focusFrame:IsShown() then return end
    local ov = GetAfkOverlay()
    local r, g, b = _afkOverlayColor()
    ov._tex:SetColorTexture(r, g, b, 0.90)
    ov:SetAlpha(0)
    -- Reset cursor tracking so a stationary mouse doesn't dismiss immediately
    ov._lastX, ov._lastY = nil, nil
    ov:Show()
    FadeTo(ov, 0, 1, 3.0)
end

HideAfkOverlay = function()
    if not _afkOverlay or not _afkOverlay:IsShown() then return end
    FadeTo(_afkOverlay, _afkOverlay:GetAlpha(), 0, 0.5, function()
        if _afkOverlay then _afkOverlay:Hide() end
    end)
end

-- Hook PLAYER_FLAGS_CHANGED to show/hide the AFK overlay
local _afkEvt = CreateFrame("Frame")
_afkEvt:RegisterEvent("PLAYER_FLAGS_CHANGED")
_afkEvt:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_FLAGS_CHANGED" and unit == "player" then
        if not focusFrame or not focusFrame:IsShown() then return end
        if UnitIsAFK("player") then
            ShowAfkOverlay()
        else
            HideAfkOverlay()
        end
    end
end)

-- Public: gradual fade-out (called by FocusOrbit on movement start)
function BNB.FadeOutFocusOverlay(duration)
    if not focusOverlay or not focusOverlay:IsShown() then return end
    FadeTo(focusOverlay, focusOverlay:GetAlpha(), 0, duration or 1.0, function()
        if focusOverlay then focusOverlay:Hide() end
    end)
end

-- Public: gradual fade-in (called by FocusOrbit resume timer)
function BNB.FadeInFocusOverlay(duration)
    local db    = BigNoteBoxDB
    local alpha = (db and db.focusOverlayAlpha) or 0.6
    if alpha <= 0 then return end
    local ov  = GetFocusOverlay()
    local r, g, b = _overlayColor()
    ov._tex:SetColorTexture(r, g, b, alpha)
    ov:Show()
    FadeTo(ov, ov:GetAlpha(), 1, duration or 1.5)
end

--------------------------------------------------------------------------------


--------------------------------------------------------------------------------
-- TIMESTAMP FORMATTER
--------------------------------------------------------------------------------
local function FmtTime(ts)
    if not ts or ts == 0 then return "" end
    local db    = BigNoteBoxDB
    local fmt   = db and db.dateFormat or "YYYY-MM-DD"
    local use24 = db == nil or db.use24Hour ~= false
    if fmt == "relative" then
        local diff = time() - ts
        if diff < 60          then return "just now"
        elseif diff < 3600    then return math.floor(diff/60) .. "m ago"
        elseif diff < 86400   then return math.floor(diff/3600) .. "h ago"
        elseif diff < 604800  then return math.floor(diff/86400) .. "d ago"
        elseif diff < 2592000 then return math.floor(diff/604800) .. " weeks ago"
        elseif diff < 31536000 then return math.floor(diff/2592000) .. " months ago"
        else return math.floor(diff/31536000) .. " years ago" end
    end
    local dp
    if fmt == "DD-MM-YYYY" then dp = date("%d-%m-%Y", ts)
    elseif fmt == "MM-DD-YYYY" then dp = date("%m-%d-%Y", ts)
    else dp = date("%Y-%m-%d", ts) end
    local tp
    if use24 then
        tp = date("%H:%M", ts)
    else
        local h = tonumber(date("%H", ts))
        local m = date("%M", ts)
        local ap = h >= 12 and "pm" or "am"
        h = h % 12; if h == 0 then h = 12 end
        tp = h .. ":" .. m .. " " .. ap
    end
    return dp .. " " .. tp
end

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------
local function UpdateFocusStats(text)
    if not focusStatsStrip then return end
    if not text then
        text = (focusBodyEb and not focusBodyEb._showingPlaceholder)
            and focusBodyEb:GetText() or ""
    end
    local chars = #text
    -- word count: split on whitespace sequences
    local words = 0
    for _ in text:gmatch("%S+") do words = words + 1 end
    focusStatsStrip:SetText(chars .. " chars  " .. words .. " words")
end

local function UpdateFocusSaveBtn()
    if not focusSaveBtn then return end
    local en = focusDirty == true
    focusSaveBtn:SetEnabled(en)
    focusSaveBtn:SetAlpha(en and 1.0 or 0.4)
end

local function SaveFocusNote()
    local id = BNB._currentNoteID
    if not id then return end
    local title = (focusTitleEb and not focusTitleEb._showingPlaceholder)
        and focusTitleEb:GetText() or ""
    local body  = (focusBodyEb and not focusBodyEb._showingPlaceholder)
        and focusBodyEb:GetText() or ""
    BNB.UpdateNote(id, { title = title, body = body })
    if BNB._editorTitle then BNB._editorTitle:SetRealText(title) end
    if BNB._editorBody  then BNB._editorBody:SetRealText(body)   end
    if BNB.RefreshNoteList then BNB.RefreshNoteList() end
    focusDirty = false
    BNB._dirty = false
    UpdateFocusSaveBtn()
    if BNB.UpdateSaveButtonState then BNB.UpdateSaveButtonState() end
    if BNB.RichPreviewFocus then BNB.RichPreviewFocus.Refresh() end
end

-- Copy centre position from src to dst (scale-aware). Does NOT copy size —
-- the focus frame is fixed-size; only its centre position is transferred.
local function CopyFrameCenter(src, dst)
    if not src or not dst then return end
    local ss = src:GetEffectiveScale()
    local ds = dst:GetEffectiveScale()
    local x, y = src:GetCenter()
    if not x then return end
    dst:ClearAllPoints()
    dst:SetPoint("CENTER", UIParent, "BOTTOMLEFT",
        (x * ss) / ds, (y * ss) / ds)
end

--------------------------------------------------------------------------------
-- LOAD NOTE INTO FOCUS FRAME
-- Defers SetText one tick so ScrollFrame OnSizeChanged has fired and
-- eb:SetWidth is non-zero before GrowToContent runs.
--------------------------------------------------------------------------------
local function LoadNoteInFocus(id)
    local note = id and BNB.GetNote(id)

    if not note then
        if focusTitleBg    then focusTitleBg:Hide()    end
        if focusTitleUl    then focusTitleUl:Hide()    end
        if focusTsStrip    then focusTsStrip:Hide()    end
        if focusStatsStrip then focusStatsStrip:Hide() end
        if focusBodyScroll then focusBodyScroll:Hide() end
        if focusMarkupBar  then focusMarkupBar:Hide()  end
        focusDirty = false
        UpdateFocusSaveBtn()
        return
    end

    if focusTitleBg    then focusTitleBg:Show()    end
    if focusTitleUl    then focusTitleUl:Show()    end
    if focusTsStrip    then focusTsStrip:Show()    end
    if focusStatsStrip then focusStatsStrip:Show() end
    if focusBodyScroll then focusBodyScroll:Show() end

    -- Show/hide markup bar and adjust body scroll top offset
    local isRich = BNB.AdvancedMode and BNB.AdvancedMode.IsRich(note)
    if isRich and focusMarkupBar then
        focusMarkupBar:Show()
        if focusBodyScroll then
            local pt, rel, rp, xo = focusBodyScroll:GetPoint(1)
            if pt and rel then
                focusBodyScroll:SetPoint(pt, rel, rp, xo,
                    BODY_TOP_OFFSET - FOCUS_MARKUP_H - 2)
            end
        end
    else
        if focusMarkupBar then focusMarkupBar:Hide() end
        if focusBodyScroll then
            local pt, rel, rp, xo = focusBodyScroll:GetPoint(1)
            if pt and rel then
                focusBodyScroll:SetPoint(pt, rel, rp, xo, BODY_TOP_OFFSET)
            end
        end
    end

    -- Apply font first
    local fo = note.fontOverride
    if fo and BNB.GetFontDef then
        local def = BNB.GetFontDef(fo)
        local sz  = BigNoteBoxDB and BigNoteBoxDB.fontSize or 13
        if focusBodyEb  then pcall(function() focusBodyEb:SetFont(def.regular, sz, "") end) end
        if focusTitleEb then pcall(function() focusTitleEb:SetFont(def.bold, 20, "") end) end
    else
        if BNB.GetBodyFont and focusBodyEb then
            local path, sz = BNB.GetBodyFont()
            if path then pcall(function() focusBodyEb:SetFont(path, sz, "") end) end
        end
        if BNB.GetBoldFont and focusTitleEb then
            local path = BNB.GetBoldFont()
            if path then pcall(function() focusTitleEb:SetFont(path, 20, "") end) end
        end
    end

    -- Timestamps can be set immediately
    if focusTsStrip then
        local cr = note.created and ("Created " .. FmtTime(note.created)) or ""
        local up = note.updated and ("  \226\128\162  Edited " .. FmtTime(note.updated)) or ""
        focusTsStrip:SetText(cr .. up)
    end

    -- Defer text by one tick: ScrollFrame needs OnSizeChanged to fire so
    -- eb:SetWidth is valid before SetText triggers GrowToContent.
    C_Timer.After(0, function()
        if not focusFrame or not focusFrame:IsShown() then return end
        if focusTitleEb then focusTitleEb:SetRealText(note.title or "") end
        if focusBodyEb  then
            focusBodyEb:SetRealText(note.body or "")
            if focusBodyScroll then
                focusBodyScroll:SetVerticalScroll(0)
                if focusBodyScroll.UpdateScrollbar then
                    focusBodyScroll:UpdateScrollbar()
                end
            end
        end
        UpdateFocusStats(note.body or "")
        focusDirty = false
        UpdateFocusSaveBtn()
    end)
end

--------------------------------------------------------------------------------
-- PUBLIC: refresh font when global setting changes
--------------------------------------------------------------------------------
function BNB.RefreshFocusFont()
    if not focusFrame or not focusFrame:IsShown() then return end
    local id   = BNB._currentNoteID
    local note = id and BNB.GetNote(id)
    if not note then return end
    local fo = note.fontOverride
    if fo and BNB.GetFontDef then
        local def = BNB.GetFontDef(fo)
        local sz  = BigNoteBoxDB and BigNoteBoxDB.fontSize or 13
        if focusBodyEb  then pcall(function() focusBodyEb:SetFont(def.regular, sz, "") end) end
        if focusTitleEb then pcall(function() focusTitleEb:SetFont(def.bold, 20, "") end) end
    else
        if BNB.GetBodyFont and focusBodyEb then
            local path, sz = BNB.GetBodyFont()
            if path then pcall(function() focusBodyEb:SetFont(path, sz, "") end) end
        end
        if BNB.GetBoldFont and focusTitleEb then
            local path = BNB.GetBoldFont()
            if path then pcall(function() focusTitleEb:SetFont(path, 20, "") end) end
        end
    end
end

--------------------------------------------------------------------------------
-- PUBLIC: refresh spin button texture when orbit state changes externally
--------------------------------------------------------------------------------
function BNB.UpdateFocusSpinBtn(enabled)
    if not focusSpinBtn then return end
    local BTNS = "Interface\\AddOns\\BigNoteBox\\Assets\\Buttons\\"
    local base = enabled and "bt-spinon" or "bt-spinoff"
    focusSpinBtn._n:SetTexture(BTNS .. base .. "-normal")
    focusSpinBtn._h:SetTexture(BTNS .. base .. "-hover")
    focusSpinBtn._p:SetTexture(BTNS .. base .. "-press")
end

--------------------------------------------------------------------------------
-- FOCUS MARKUP BAR  (shared by normal and skin builders)
-- Targets focusBodyEb for tag insertion. Shows only for rich notes.
--------------------------------------------------------------------------------
local function FocusInsertTagPair(open, close)
    local eb = focusBodyEb
    if not eb then return end
    eb:SetFocus()
    local before = eb:GetText() or ""
    local curEnd = eb:GetCursorPosition() or #before
    eb:Insert("")
    local after  = eb:GetText() or ""
    local curStart = eb:GetCursorPosition() or 0
    if #after < #before then
        local selected = before:sub(curStart + 1, curStart + (#before - #after))
        eb:Insert(open .. selected .. close)
        eb:SetCursorPosition(curStart + #open + #selected + #close)
    else
        eb:Insert(open .. close)
        eb:SetCursorPosition(curStart + #open)
    end
    focusDirty = true; BNB._dirty = true; UpdateFocusSaveBtn()
end

local function FocusInsertTag(tag)
    local eb = focusBodyEb
    if not eb then return end
    eb:SetFocus()
    eb:Insert("")
    local cursor = eb:GetCursorPosition() or 0
    eb:Insert(tag)
    eb:SetCursorPosition(cursor + #tag)
    focusDirty = true; BNB._dirty = true; UpdateFocusSaveBtn()
end

local function BuildFocusMarkupBar(parent, anchorBelow)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT",  anchorBelow, "BOTTOMLEFT",  0, -2)
    bar:SetPoint("TOPRIGHT", anchorBelow, "BOTTOMRIGHT", 0, -2)
    bar:SetHeight(FOCUS_MARKUP_H)

    local sep = bar:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("BOTTOMLEFT",  bar, "BOTTOMLEFT",  0, 0)
    sep:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset then
        local p = BNB.GetSkinPreset()
        local br, bg_, bb = BNB.SkinBorderOf(p)
        sep:SetColorTexture(br, bg_, bb, 0.20)
        if BNB.RegisterSkinRule then BNB.RegisterSkinRule(sep, 0.20) end
    else
        sep:SetColorTexture(0.22, 0.22, 0.24, 1)
    end

    local btnX = 4
    local function MkBtn(label, tip, onClick)
        local btn = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
        btn:SetSize(28, 18)
        btn:SetPoint("LEFT", bar, "LEFT", btnX, 0)
        btn:SetText(label)
        local fs = btn:GetFontString()
        if fs then pcall(function() fs:SetFont(fs:GetFont(), 10, "") end) end
        btn:SetScript("OnClick", onClick)
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(tip, 1, 1, 1)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        btnX = btnX + 30
        return btn
    end
    local function Divider()
        local d = bar:CreateTexture(nil, "ARTWORK")
        d:SetSize(1, 14)
        d:SetPoint("LEFT", bar, "LEFT", btnX, 0)
        d:SetColorTexture(0.35, 0.35, 0.38, 1)
        btnX = btnX + 6
    end

    MkBtn("H1", "Header 1", function() FocusInsertTagPair("{h1}", "{/h1}") end)
    MkBtn("H2", "Header 2", function() FocusInsertTagPair("{h2}", "{/h2}") end)
    MkBtn("H3", "Header 3", function() FocusInsertTagPair("{h3}", "{/h3}") end)
    Divider()
    MkBtn("P",  "Paragraph",          function() FocusInsertTagPair("{p}", "{/p}") end)
    MkBtn("Pc", "Centered paragraph", function() FocusInsertTagPair("{p:c}", "{/p}") end)
    MkBtn("Pr", "Right paragraph",    function() FocusInsertTagPair("{p:r}", "{/p}") end)
    MkBtn("Br", "Insert line break: {br}", function() FocusInsertTag("{br}") end)
    Divider()
    -- Color picker state for Col button
    local _fColActive = false
    local _fColCancelled = false
    local _fColR, _fColG, _fColB = 1, 1, 1
    local _fColHooked = false

    MkBtn("Col", "Pick a colour",  function()
        if not focusBodyEb then return end
        _fColActive = true
        _fColCancelled = false
        _fColR, _fColG, _fColB = 1, 1, 1
        if ColorPickerFrame.SetupColorPickerAndShow then
            ColorPickerFrame:SetupColorPickerAndShow({
                swatchFunc = function()
                    _fColR, _fColG, _fColB = ColorPickerFrame:GetColorRGB()
                end,
                cancelFunc = function() _fColCancelled = true end,
                hasOpacity = false, r = 1, g = 1, b = 1,
            })
            if not _fColHooked then
                _fColHooked = true
                ColorPickerFrame:HookScript("OnHide", function()
                    if not _fColActive then return end
                    _fColActive = false
                    if _fColCancelled then return end
                    local hex = string.format("%02x%02x%02x",
                        math.floor(_fColR * 255 + 0.5),
                        math.floor(_fColG * 255 + 0.5),
                        math.floor(_fColB * 255 + 0.5))
                    FocusInsertTagPair("{col:" .. hex .. "}", "{/col}")
                end)
            end
        end
    end)
    MkBtn("Lnk", "Link",       function() BNB.OpenLnkDialog(FocusInsertTag) end)
    MkBtn("Ico", "Icon",       function() BNB.OpenIcoDialog(FocusInsertTag) end)
    MkBtn("Img", "Image",      function() BNB.OpenImgDialog(FocusInsertTag) end)

    -- "Live Preview" toggle — right-aligned, same pattern as main markup bar
    local previewBtn = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    previewBtn:SetSize(72, 18)
    previewBtn:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    previewBtn:SetText(L["MARKUP_PREVIEW_BTN"])
    local pfs = previewBtn:GetFontString()
    if pfs then pcall(function() pfs:SetFont(pfs:GetFont(), 10, "") end) end
    previewBtn:SetAlpha(0.45)
    previewBtn:SetScript("OnClick", function()
        if BNB.RichPreviewFocus then
            BNB.RichPreviewFocus.Toggle(focusFrame)
        end
    end)
    previewBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["MARKUP_PREVIEW_TIP"], 1, 1, 1)
        GameTooltip:Show()
    end)
    previewBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    BNB._focusMarkupPreviewBtn = previewBtn

    bar:Hide()
    focusMarkupBar = bar
    return bar
end

--------------------------------------------------------------------------------
-- BUILD FOCUS FRAME  (NORMAL VERSION -- ButtonFrameTemplate)
--------------------------------------------------------------------------------
local function BuildFocusFrame()
    if focusFrame then return end

    local f = CreateFrame("Frame", "BigNoteBoxFocusFrame", WorldFrame, "ButtonFrameTemplate")
    f:SetSize(FOCUS_W, FOCUS_H)
    f:SetPoint("CENTER")
    f:SetToplevel(true)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetResizable(false)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)

    ButtonFrameTemplate_HidePortrait(f)
    ButtonFrameTemplate_HideButtonBar(f)
    if f.Inset then f.Inset:Hide() end
    f:SetAlpha(0.95)
    f:SetTitle(L["FOCUS_MODE_TITLE"])

    if f.CloseButton then
        f.CloseButton:SetScript("OnClick", function() BNB.CloseFocusModeAndBNB() end)
        f.CloseButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:AddLine(L["FOCUS_RESTORE_TIP"], 1, 1, 1)
            GameTooltip:Show()
        end)
        f.CloseButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    local restoreBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    restoreBtn:SetSize(64, 22)
    restoreBtn:SetPoint("RIGHT", f.CloseButton, "LEFT", -4, 0)
    restoreBtn:SetFrameLevel(f.CloseButton:GetFrameLevel())
    restoreBtn:SetText(L["FOCUS_RESTORE_BTN"])
    restoreBtn:SetScript("OnClick", function() BNB.CloseFocusMode() end)
    restoreBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L["FOCUS_RESTORE_TIP"], 1, 1, 1)
        GameTooltip:Show()
    end)
    restoreBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Spin (orbit) toggle button — left of Restore
    do
        local BTNS  = "Interface\\AddOns\\BigNoteBox\\Assets\\Buttons\\"
        local db    = BigNoteBoxDB
        local isOn  = db and db.focusOrbitEnabled ~= false
        local spinBase = isOn and "bt-spinon" or "bt-spinoff"
        local sb = CreateFrame("Button", nil, f)
        sb:SetSize(18, 18)
        sb:SetPoint("RIGHT", restoreBtn, "LEFT", -4, 0)
        sb:SetFrameLevel(restoreBtn:GetFrameLevel())
        sb:SetHighlightTexture(""); sb:SetPushedTexture("")
        local sn = sb:CreateTexture(nil, "ARTWORK"); sn:SetAllPoints()
        sn:SetTexture(BTNS .. spinBase .. "-normal")
        local sh = sb:CreateTexture(nil, "ARTWORK"); sh:SetAllPoints()
        sh:SetTexture(BTNS .. spinBase .. "-hover"); sh:Hide()
        local sp = sb:CreateTexture(nil, "ARTWORK"); sp:SetAllPoints()
        sp:SetTexture(BTNS .. spinBase .. "-press"); sp:Hide()
        sb:SetScript("OnMouseDown", function(self) if self:IsEnabled() then sp:Show(); sn:Hide(); sh:Hide() end end)
        sb:SetScript("OnMouseUp",   function(self) sp:Hide(); sn:Show(); sh:Hide() end)
        sb:SetScript("OnEnter", function(self)
            sn:Hide(); sh:Show()
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            local db = BigNoteBoxDB
            local tip = (db and db.focusOrbitEnabled ~= false)
                and L["CFG_FOCUS_ORBIT_TIP_OFF"] or L["CFG_FOCUS_ORBIT_TIP_ON"]
            GameTooltip:AddLine(tip, 1, 1, 1)
            GameTooltip:Show()
        end)
        sb:SetScript("OnLeave", function() sp:Hide(); sh:Hide(); sn:Show(); GameTooltip:Hide() end)
        sb:SetScript("OnClick", function()
            if BNB.FocusOrbit then BNB.FocusOrbit.Toggle() end
        end)
        sb._n, sb._h, sb._p = sn, sh, sp
        focusSpinBtn = sb
    end

    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT",     f, "TOPLEFT",     PAD, -TITLE_H)
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, TOOLBAR_H)

    local titleBg = BNB.CreateBackdropFrame("Frame", nil, content)
    titleBg:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, 0)
    titleBg:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
    titleBg:SetHeight(36)
    BNB.SetBackdrop(titleBg, 0.06, 0.06, 0.09, 0, 0.30, 0.30, 0.32, 0)
    focusTitleBg = titleBg

    local titleEb = CreateFrame("EditBox", nil, titleBg)
    titleEb:SetPoint("TOPLEFT",     titleBg, "TOPLEFT",     6, 0)
    titleEb:SetPoint("BOTTOMRIGHT", titleBg, "BOTTOMRIGHT", -6, 0)
    local boldPath = BNB.GetBoldFont and BNB.GetBoldFont()
    if boldPath then
        pcall(function() titleEb:SetFont(boldPath, 20, "") end)
    else
        local font, _, flags = GameFontNormalHuge:GetFont()
        if font then titleEb:SetFont(font, 20, flags or "")
        else titleEb:SetFontObject("GameFontNormalLarge") end
    end
    titleEb:SetAutoFocus(false)
    titleEb:SetMaxLetters(200)
    titleEb:SetTextInsets(2, 2, 2, 2)
    titleEb:SetScript("OnEditFocusGained", function()
        if titleBg.SetBackdropColor then
            titleBg:SetBackdropColor(0.06, 0.06, 0.09, 0.85)
            titleBg:SetBackdropBorderColor(0.35, 0.35, 0.38, 1)
        end
    end)
    titleEb:SetScript("OnEditFocusLost", function()
        if titleBg.SetBackdropColor then
            titleBg:SetBackdropColor(0.06, 0.06, 0.09, 0)
            titleBg:SetBackdropBorderColor(0.30, 0.30, 0.32, 0)
        end
    end)
    BNB.AddPlaceholder(titleEb, L["NOTE_TITLE_HINT"], 0.35, 0.35, 0.35)
    titleEb:SetScript("OnEscapePressed", function(self)
        self:ClearFocus(); BNB.CloseFocusMode()
    end)
    titleEb:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if focusBodyEb then focusBodyEb:SetFocus() end
    end)
    titleEb:SetScript("OnTextChanged", function(self, userInput)
        if userInput and not self._showingPlaceholder then
            focusDirty = true; BNB._dirty = true; UpdateFocusSaveBtn()
        end
    end)
    focusTitleEb = titleEb

    local underline = content:CreateTexture(nil, "ARTWORK")
    underline:SetHeight(1)
    underline:SetPoint("TOPLEFT",  titleBg, "BOTTOMLEFT",  0, -1)
    underline:SetPoint("TOPRIGHT", titleBg, "BOTTOMRIGHT", 0, -1)
    underline:SetColorTexture(0.28, 0.28, 0.30, 1)
    focusTitleUl = underline

    local tsStrip = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tsStrip:SetPoint("TOPLEFT",  underline, "BOTTOMLEFT",  2, -2)
    tsStrip:SetPoint("TOPRIGHT", underline, "BOTTOMRIGHT", -2, -2)
    tsStrip:SetHeight(TSTAMP_H)
    tsStrip:SetJustifyH("LEFT")
    tsStrip:SetTextColor(0.38, 0.38, 0.38)
    tsStrip:SetText("")
    focusTsStrip = tsStrip

    local statsStrip = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statsStrip:SetPoint("TOPLEFT",  underline, "BOTTOMLEFT",  2, -2)
    statsStrip:SetPoint("TOPRIGHT", underline, "BOTTOMRIGHT", -2, -2)
    statsStrip:SetHeight(TSTAMP_H)
    statsStrip:SetJustifyH("RIGHT")
    statsStrip:SetTextColor(0.38, 0.38, 0.38)
    statsStrip:SetText("")
    focusStatsStrip = statsStrip

    -- Markup bar for rich notes (anchored below timestamp strip)
    BuildFocusMarkupBar(content, tsStrip)

    local bodyPath, bodySize
    if BNB.GetBodyFont then bodyPath, bodySize = BNB.GetBodyFont() end
    bodySize = bodySize or (BigNoteBoxDB and BigNoteBoxDB.fontSize) or 13

    local sf, eb = BNB.CreateScrolledEditBox("BigNoteBoxFocusBodyScroll", content, bodySize)
    if bodyPath then pcall(function() eb:SetFont(bodyPath, bodySize, "") end) end

    sf:SetPoint("TOPLEFT",     content, "TOPLEFT",     0, BODY_TOP_OFFSET)
    sf:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -20, 0)

    BNB.AddPlaceholder(eb, L["NOTE_BODY_HINT"], 0.35, 0.35, 0.35)
    eb:SetScript("OnEscapePressed", function(self)
        self:ClearFocus(); BNB.CloseFocusMode()
    end)
    eb:SetScript("OnTextChanged", function(self, userInput)
        if userInput and not self._showingPlaceholder then
            focusDirty = true; BNB._dirty = true; UpdateFocusSaveBtn()
            if sf.UpdateScrollbar then sf:UpdateScrollbar() end
            UpdateFocusStats(self:GetText())
            -- Notify focus live preview
            if BNB.RichPreviewFocus and BNB.RichPreviewFocus.ScheduleRefresh then
                BNB.RichPreviewFocus.ScheduleRefresh()
            end
            local id = BNB._currentNoteID
            if id and not BNB._undoActive then
                local idleDelay = (BigNoteBoxDB and BigNoteBoxDB.undoIdleDelay)     or 0.8
                local forcedInt = (BigNoteBoxDB and BigNoteBoxDB.undoForcedInterval) or 3.0
                if not BNB._focusUndoTimers  then BNB._focusUndoTimers  = {} end
                if not BNB._focusUndoForced  then BNB._focusUndoForced  = {} end
                local ft = BNB._focusUndoTimers
                local ff = BNB._focusUndoForced
                if not BNB._undoSnap[id] or BNB._undoStack[id] == nil then
                    BNB.UndoPush(id, self:GetText() or "", self:GetCursorPosition() or 0)
                else
                    if ft[id] then ft[id]:Cancel(); ft[id] = nil end
                    ft[id] = C_Timer.NewTimer(idleDelay, function()
                        ft[id] = nil
                        if ff[id] then ff[id]:Cancel(); ff[id] = nil end
                        if not BNB._undoActive then
                            BNB.UndoPush(id, self:GetText() or "", self:GetCursorPosition() or 0)
                        end
                    end)
                    if not ff[id] then
                        ff[id] = C_Timer.NewTimer(forcedInt, function()
                            ff[id] = nil
                            if ft[id] then ft[id]:Cancel(); ft[id] = nil end
                            if not BNB._undoActive then
                                BNB.UndoPush(id, self:GetText() or "", self:GetCursorPosition() or 0)
                            end
                        end)
                    end
                end
            end
        end
    end)

    eb:SetScript("OnKeyDown", function(self, key)
        local ctrl  = IsControlKeyDown()
        local shift = IsShiftKeyDown()
        if ctrl and key == "Z" and not shift then
            self:SetPropagateKeyboardInput(false)
            local id = BNB._currentNoteID
            if id and BNB.UndoCanUndo(id) then
                local ft = BNB._focusUndoTimers
                local ff = BNB._focusUndoForced
                if ft and ft[id] then ft[id]:Cancel(); ft[id] = nil end
                if ff and ff[id] then ff[id]:Cancel(); ff[id] = nil end
                BNB._undoActive = true
                local text, cursor = BNB.UndoStep(id)
                if text then
                    self:SetText(text)
                    C_Timer.After(0, function() self:SetCursorPosition(cursor or 0) end)
                    focusDirty = true; BNB._dirty = true; UpdateFocusSaveBtn()
                end
                BNB._undoActive = false
            end
        elseif ctrl and ((key == "Z" and shift) or key == "Y") then
            self:SetPropagateKeyboardInput(false)
            local id = BNB._currentNoteID
            if id and BNB.UndoCanRedo(id) then
                local ft = BNB._focusUndoTimers
                local ff = BNB._focusUndoForced
                if ft and ft[id] then ft[id]:Cancel(); ft[id] = nil end
                if ff and ff[id] then ff[id]:Cancel(); ff[id] = nil end
                BNB._undoActive = true
                local text, cursor = BNB.RedoStep(id)
                if text then
                    self:SetText(text)
                    C_Timer.After(0, function() self:SetCursorPosition(cursor or 0) end)
                    focusDirty = true; BNB._dirty = true; UpdateFocusSaveBtn()
                end
                BNB._undoActive = false
            end
        end
    end)

    focusBodyScroll = sf
    focusBodyEb     = eb
    BNB._focusEditorBody = eb

    if BNB.WireDropTarget       then BNB.WireDropTarget(eb)       end
    if BNB.WireInsertInfoTarget  then BNB.WireInsertInfoTarget(eb) end

    local hintLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hintLbl:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  PAD, TOOLBAR_H + 4)
    hintLbl:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, TOOLBAR_H + 4)
    hintLbl:SetJustifyH("CENTER")
    hintLbl:SetTextColor(0.30, 0.30, 0.30, 1)
    hintLbl:SetText("Ctrl+Z = Undo  --  Ctrl+Y = Redo")

    local toolbar = CreateFrame("Frame", nil, f)
    toolbar:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  0, 0)
    toolbar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    toolbar:SetHeight(TOOLBAR_H)

    local toolSep = BNB.CreateDivider(f, "HORIZONTAL", 0.28, 0.28, 0.30, 1)
    toolSep:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  PAD, TOOLBAR_H)
    toolSep:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, TOOLBAR_H)

    local ASSETS = "Interface\\AddOns\\BigNoteBox\\Assets\\"
    local sBtn = CreateFrame("Button", nil, toolbar)
    sBtn:SetSize(26, 26)
    sBtn:SetPoint("LEFT", toolbar, "LEFT", PAD + 6, 0)
    local sTx = sBtn:CreateTexture(nil, "ARTWORK"); sTx:SetAllPoints()
    sTx:SetTexture(ASSETS .. "Actionbar\\ab-save")
    local sHi = sBtn:CreateTexture(nil, "HIGHLIGHT"); sHi:SetAllPoints()
    sHi:SetColorTexture(1, 1, 1, 0.25)
    sBtn:SetEnabled(false); sBtn:SetAlpha(0.4)
    sBtn:SetScript("OnClick", function() SaveFocusNote() end)
    sBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["BTN_SAVE_NOTE"], 1, 1, 1)
        GameTooltip:Show()
    end)
    sBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    focusSaveBtn = sBtn

    f:SetPropagateKeyboardInput(false)
    f:EnableKeyboard(true)
    f:SetScript("OnKeyDown", function(self, key)
        if key ~= "ESCAPE" then self:SetPropagateKeyboardInput(true); return end
        self:SetPropagateKeyboardInput(false)
        -- If AFK overlay is up, ESC only dismisses it — focus mode stays open
        if _afkOverlay and _afkOverlay:IsShown() then
            HideAfkOverlay()
            return
        end
        BNB.CloseFocusMode()
    end)

    f:SetScript("OnShow", function()
        if BNB.ApplyMainWindowSkin then BNB.ApplyMainWindowSkin() end
    end)

    f:SetScript("OnHide", function()
        if focusDirty then SaveFocusNote() end
    end)

    focusFrame = f
    f:Hide()
end
-- Matches the look of MainWindowSkin. Called when BigNoteBoxDB.skinMode == true.
-- Uses SkinSystem.lua public API — BNB.CreateSkinFrame, BNB.CreateSkinStrip,
-- BNB.RegisterSkinTarget — so ApplyMainWindowSkin recolours it on preset change.
--------------------------------------------------------------------------------
local SK_FOCUS_TITLE_H = 28
local SK_FOCUS_PAD     = PAD

local function BuildFocusFrameSkin()
    if focusFrame then return end

    local f = BNB.CreateSkinFrame(WorldFrame, false, nil, false)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    _G["BigNoteBoxFocusFrame"] = f
    f:SetSize(FOCUS_W, FOCUS_H)
    f:SetPoint("CENTER")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetResizable(false)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    f:SetAlpha(0.95)

    -- ── Title bar strip ───────────────────────────────────────────────────────
    local titleBar = BNB.CreateSkinStrip(f, true, false)
    titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    titleBar:SetHeight(SK_FOCUS_TITLE_H)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
    titleBar:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

    local titleLbl = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleLbl:SetPoint("CENTER", titleBar, "CENTER", -40, 0)
    titleLbl:SetTextColor(1, 0.82, 0)
    titleLbl:SetText(L["FOCUS_MODE_TITLE"])

    -- Close (X) button
    local closeBtn = BNB.CreateSkinCloseButton(titleBar, function() BNB.CloseFocusModeAndBNB() end)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -3, 0)
    closeBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L["FOCUS_RESTORE_TIP"], 1, 1, 1)
        GameTooltip:Show()
    end)
    closeBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Restore button
    local restoreBtn = CreateFrame("Button", nil, titleBar, "UIPanelButtonTemplate")
    restoreBtn:SetSize(64, 22)
    restoreBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
    restoreBtn:SetText(L["FOCUS_RESTORE_BTN"])
    restoreBtn:SetScript("OnClick", function() BNB.CloseFocusMode() end)
    restoreBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L["FOCUS_RESTORE_TIP"], 1, 1, 1)
        GameTooltip:Show()
    end)
    restoreBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Spin (orbit) toggle button — left of Restore
    do
        local BTNS  = "Interface\\AddOns\\BigNoteBox\\Assets\\Buttons\\"
        local db    = BigNoteBoxDB
        local isOn  = db and db.focusOrbitEnabled ~= false
        local spinBase = isOn and "bt-spinon" or "bt-spinoff"
        local sb = CreateFrame("Button", nil, titleBar)
        sb:SetSize(18, 18)
        sb:SetPoint("RIGHT", restoreBtn, "LEFT", -4, 0)
        sb:SetHighlightTexture(""); sb:SetPushedTexture("")
        local sn = sb:CreateTexture(nil, "ARTWORK"); sn:SetAllPoints()
        sn:SetTexture(BTNS .. spinBase .. "-normal")
        local sh = sb:CreateTexture(nil, "ARTWORK"); sh:SetAllPoints()
        sh:SetTexture(BTNS .. spinBase .. "-hover"); sh:Hide()
        local sp = sb:CreateTexture(nil, "ARTWORK"); sp:SetAllPoints()
        sp:SetTexture(BTNS .. spinBase .. "-press"); sp:Hide()
        sb:SetScript("OnMouseDown", function(self) if self:IsEnabled() then sp:Show(); sn:Hide(); sh:Hide() end end)
        sb:SetScript("OnMouseUp",   function(self) sp:Hide(); sn:Show(); sh:Hide() end)
        sb:SetScript("OnEnter", function(self)
            sn:Hide(); sh:Show()
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            local db = BigNoteBoxDB
            local tip = (db and db.focusOrbitEnabled ~= false)
                and L["CFG_FOCUS_ORBIT_TIP_OFF"] or L["CFG_FOCUS_ORBIT_TIP_ON"]
            GameTooltip:AddLine(tip, 1, 1, 1)
            GameTooltip:Show()
        end)
        sb:SetScript("OnLeave", function() sp:Hide(); sh:Hide(); sn:Show(); GameTooltip:Hide() end)
        sb:SetScript("OnClick", function()
            if BNB.FocusOrbit then BNB.FocusOrbit.Toggle() end
        end)
        sb._n, sb._h, sb._p = sn, sh, sp
        focusSpinBtn = sb
    end

    -- ── Content area ──────────────────────────────────────────────────────────
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT",     f, "TOPLEFT",     SK_FOCUS_PAD, -SK_FOCUS_TITLE_H)
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -SK_FOCUS_PAD, TOOLBAR_H)

    -- Title background (same as normal version)
    local titleBg = BNB.CreateBackdropFrame("Frame", nil, content)
    titleBg:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, 0)
    titleBg:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
    titleBg:SetHeight(36)
    BNB.SetBackdrop(titleBg, 0.06, 0.06, 0.09, 0, 0.30, 0.30, 0.32, 0)
    focusTitleBg = titleBg

    local titleEb = CreateFrame("EditBox", nil, titleBg)
    titleEb:SetPoint("TOPLEFT",     titleBg, "TOPLEFT",     6, 0)
    titleEb:SetPoint("BOTTOMRIGHT", titleBg, "BOTTOMRIGHT", -6, 0)
    local boldPath = BNB.GetBoldFont and BNB.GetBoldFont()
    if boldPath then
        pcall(function() titleEb:SetFont(boldPath, 20, "") end)
    else
        local font, _, flags = GameFontNormalHuge:GetFont()
        if font then titleEb:SetFont(font, 20, flags or "")
        else titleEb:SetFontObject("GameFontNormalLarge") end
    end
    titleEb:SetAutoFocus(false)
    titleEb:SetMaxLetters(200)
    titleEb:SetTextInsets(2, 2, 2, 2)
    titleEb:SetScript("OnEditFocusGained", function()
        if titleBg.SetBackdropColor then
            titleBg:SetBackdropColor(0.06, 0.06, 0.09, 0.85)
            titleBg:SetBackdropBorderColor(0.35, 0.35, 0.38, 1)
        end
    end)
    titleEb:SetScript("OnEditFocusLost", function()
        if titleBg.SetBackdropColor then
            titleBg:SetBackdropColor(0.06, 0.06, 0.09, 0)
            titleBg:SetBackdropBorderColor(0.30, 0.30, 0.32, 0)
        end
    end)
    BNB.AddPlaceholder(titleEb, L["NOTE_TITLE_HINT"], 0.35, 0.35, 0.35)
    titleEb:SetScript("OnEscapePressed", function(self)
        self:ClearFocus(); BNB.CloseFocusMode()
    end)
    titleEb:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if focusBodyEb then focusBodyEb:SetFocus() end
    end)
    titleEb:SetScript("OnTextChanged", function(self, userInput)
        if userInput and not self._showingPlaceholder then
            focusDirty = true; BNB._dirty = true; UpdateFocusSaveBtn()
        end
    end)
    focusTitleEb = titleEb

    local underline = content:CreateTexture(nil, "ARTWORK")
    underline:SetHeight(1)
    underline:SetPoint("TOPLEFT",  titleBg, "BOTTOMLEFT",  0, -1)
    underline:SetPoint("TOPRIGHT", titleBg, "BOTTOMRIGHT", 0, -1)
    underline:SetColorTexture(0.28, 0.28, 0.30, 1)
    focusTitleUl = underline

    local tsStrip = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tsStrip:SetPoint("TOPLEFT",  underline, "BOTTOMLEFT",  2, -2)
    tsStrip:SetPoint("TOPRIGHT", underline, "BOTTOMRIGHT", -2, -2)
    tsStrip:SetHeight(TSTAMP_H)
    tsStrip:SetJustifyH("LEFT")
    tsStrip:SetTextColor(0.38, 0.38, 0.38)
    tsStrip:SetText("")
    focusTsStrip = tsStrip

    local statsStrip2 = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statsStrip2:SetPoint("TOPLEFT",  underline, "BOTTOMLEFT",  2, -2)
    statsStrip2:SetPoint("TOPRIGHT", underline, "BOTTOMRIGHT", -2, -2)
    statsStrip2:SetHeight(TSTAMP_H)
    statsStrip2:SetJustifyH("RIGHT")
    statsStrip2:SetTextColor(0.38, 0.38, 0.38)
    statsStrip2:SetText("")
    focusStatsStrip = statsStrip2

    -- Markup bar for rich notes (anchored below timestamp strip)
    BuildFocusMarkupBar(content, tsStrip)

    -- Body scroll (identical to normal version)
    local bodyPath, bodySize
    if BNB.GetBodyFont then bodyPath, bodySize = BNB.GetBodyFont() end
    bodySize = bodySize or (BigNoteBoxDB and BigNoteBoxDB.fontSize) or 13

    local sf, eb = BNB.CreateScrolledEditBox("BigNoteBoxFocusBodyScroll", content, bodySize)
    if bodyPath then pcall(function() eb:SetFont(bodyPath, bodySize, "") end) end

    sf:SetPoint("TOPLEFT",     content, "TOPLEFT",     0, BODY_TOP_OFFSET)
    sf:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -20, 0)

    BNB.AddPlaceholder(eb, L["NOTE_BODY_HINT"], 0.35, 0.35, 0.35)
    eb:SetScript("OnEscapePressed", function(self)
        self:ClearFocus(); BNB.CloseFocusMode()
    end)
    eb:SetScript("OnTextChanged", function(self, userInput)
        if userInput and not self._showingPlaceholder then
            focusDirty = true; BNB._dirty = true; UpdateFocusSaveBtn()
            if sf.UpdateScrollbar then sf:UpdateScrollbar() end
            UpdateFocusStats(self:GetText())
            -- Notify focus live preview
            if BNB.RichPreviewFocus and BNB.RichPreviewFocus.ScheduleRefresh then
                BNB.RichPreviewFocus.ScheduleRefresh()
            end
            local id = BNB._currentNoteID
            if id and not BNB._undoActive then
                local idleDelay = (BigNoteBoxDB and BigNoteBoxDB.undoIdleDelay)     or 0.8
                local forcedInt = (BigNoteBoxDB and BigNoteBoxDB.undoForcedInterval) or 3.0
                if not BNB._focusUndoTimers then BNB._focusUndoTimers = {} end
                if not BNB._focusUndoForced then BNB._focusUndoForced = {} end
                local ft = BNB._focusUndoTimers
                local ff = BNB._focusUndoForced
                if not BNB._undoSnap[id] or BNB._undoStack[id] == nil then
                    BNB.UndoPush(id, self:GetText() or "", self:GetCursorPosition() or 0)
                else
                    if ft[id] then ft[id]:Cancel(); ft[id] = nil end
                    ft[id] = C_Timer.NewTimer(idleDelay, function()
                        ft[id] = nil
                        if ff[id] then ff[id]:Cancel(); ff[id] = nil end
                        if not BNB._undoActive then
                            BNB.UndoPush(id, self:GetText() or "", self:GetCursorPosition() or 0)
                        end
                    end)
                    if not ff[id] then
                        ff[id] = C_Timer.NewTimer(forcedInt, function()
                            ff[id] = nil
                            if ft[id] then ft[id]:Cancel(); ft[id] = nil end
                            if not BNB._undoActive then
                                BNB.UndoPush(id, self:GetText() or "", self:GetCursorPosition() or 0)
                            end
                        end)
                    end
                end
            end
        end
    end)

    eb:SetScript("OnKeyDown", function(self, key)
        local ctrl  = IsControlKeyDown()
        local shift = IsShiftKeyDown()
        if ctrl and key == "Z" and not shift then
            self:SetPropagateKeyboardInput(false)
            local id = BNB._currentNoteID
            if id and BNB.UndoCanUndo(id) then
                local ft = BNB._focusUndoTimers
                local ff = BNB._focusUndoForced
                if ft and ft[id] then ft[id]:Cancel(); ft[id] = nil end
                if ff and ff[id] then ff[id]:Cancel(); ff[id] = nil end
                BNB._undoActive = true
                local text, cursor = BNB.UndoStep(id)
                if text then
                    self:SetText(text)
                    C_Timer.After(0, function() self:SetCursorPosition(cursor or 0) end)
                    focusDirty = true; BNB._dirty = true; UpdateFocusSaveBtn()
                end
                BNB._undoActive = false
            end
        elseif ctrl and ((key == "Z" and shift) or key == "Y") then
            self:SetPropagateKeyboardInput(false)
            local id = BNB._currentNoteID
            if id and BNB.UndoCanRedo(id) then
                local ft = BNB._focusUndoTimers
                local ff = BNB._focusUndoForced
                if ft and ft[id] then ft[id]:Cancel(); ft[id] = nil end
                if ff and ff[id] then ff[id]:Cancel(); ff[id] = nil end
                BNB._undoActive = true
                local text, cursor = BNB.RedoStep(id)
                if text then
                    self:SetText(text)
                    C_Timer.After(0, function() self:SetCursorPosition(cursor or 0) end)
                    focusDirty = true; BNB._dirty = true; UpdateFocusSaveBtn()
                end
                BNB._undoActive = false
            end
        end
    end)

    focusBodyScroll = sf
    focusBodyEb     = eb
    BNB._focusEditorBody = eb

    if BNB.WireDropTarget      then BNB.WireDropTarget(eb)      end
    if BNB.WireInsertInfoTarget then BNB.WireInsertInfoTarget(eb) end

    local hintLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hintLbl:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  SK_FOCUS_PAD, TOOLBAR_H + 4)
    hintLbl:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -SK_FOCUS_PAD, TOOLBAR_H + 4)
    hintLbl:SetJustifyH("CENTER")
    hintLbl:SetTextColor(0.30, 0.30, 0.30, 1)
    hintLbl:SetText("Ctrl+Z = Undo  --  Ctrl+Y = Redo")

    -- ── Bottom toolbar strip ──────────────────────────────────────────────────
    local toolbar = BNB.CreateSkinStrip(f, false, false)
    toolbar:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  0, 0)
    toolbar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    toolbar:SetHeight(TOOLBAR_H)

    -- Separator (host frame avoids backdrop overdraw)
    local toolSepHost = CreateFrame("Frame", nil, f)
    toolSepHost:SetHeight(1)
    toolSepHost:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  SK_FOCUS_PAD, TOOLBAR_H)
    toolSepHost:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -SK_FOCUS_PAD, TOOLBAR_H)
    local toolSep = BNB.CreateDivider(toolSepHost, "HORIZONTAL", 0.28, 0.28, 0.30, 1)
    toolSep:SetPoint("TOPLEFT",  toolSepHost, "TOPLEFT",  0, 0)
    toolSep:SetPoint("TOPRIGHT", toolSepHost, "TOPRIGHT", 0, 0)

    local ASSETS = "Interface\\AddOns\\BigNoteBox\\Assets\\"
    local sBtn = CreateFrame("Button", nil, toolbar)
    sBtn:SetSize(26, 26)
    sBtn:SetPoint("LEFT", toolbar, "LEFT", SK_FOCUS_PAD + 6, 0)
    local sTx = sBtn:CreateTexture(nil, "ARTWORK"); sTx:SetAllPoints()
    sTx:SetTexture(ASSETS .. "Actionbar\\ab-save")
    local sHi = sBtn:CreateTexture(nil, "HIGHLIGHT"); sHi:SetAllPoints()
    sHi:SetColorTexture(1, 1, 1, 0.25)
    sBtn:SetEnabled(false); sBtn:SetAlpha(0.4)
    sBtn:SetScript("OnClick", function() SaveFocusNote() end)
    sBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["BTN_SAVE_NOTE"], 1, 1, 1)
        GameTooltip:Show()
    end)
    sBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    focusSaveBtn = sBtn

    f:SetPropagateKeyboardInput(false)
    f:EnableKeyboard(true)
    f:SetScript("OnKeyDown", function(self, key)
        if key ~= "ESCAPE" then self:SetPropagateKeyboardInput(true); return end
        self:SetPropagateKeyboardInput(false)
        -- If AFK overlay is up, ESC only dismisses it — focus mode stays open
        if _afkOverlay and _afkOverlay:IsShown() then
            HideAfkOverlay()
            return
        end
        BNB.CloseFocusMode()
    end)

    focusFrame = f
    f:Hide()
end

--------------------------------------------------------------------------------
-- PUBLIC: OPEN FOCUS MODE
--------------------------------------------------------------------------------
function BNB.OpenFocusMode()
    if InCombatLockdown() then BNB:Print(L["COMBAT_BLOCKED"]); return end
    if BNB._dirty then BNB.SaveCurrentNote() end

    if not focusFrame then
        if BigNoteBoxDB and BigNoteBoxDB.skinMode then
            BuildFocusFrameSkin()
        else
            BuildFocusFrame()
        end
    end

    -- Snapshot which companion windows are open, then close them all.
    -- CloseFocusMode will reopen exactly what was open.
    local noteID = BNB._currentNoteID
    local snap = {}
    local function shown(name) local f = _G[name]; return f and f:IsShown() end
    snap.noteConfig   = shown("BigNoteBoxNoteConfigFrame")
    snap.config       = shown("BigNoteBoxConfigFrame")
    snap.trash        = shown("BigNoteBoxTrashFrame")
    snap.tagManager   = shown("BigNoteBoxTagManagerFrame")
    snap.historyWin   = shown("BigNoteBoxHistoryFrame")
    snap.historyPanel = shown("BigNoteBoxNoteHistoryFrame")
    snap.refBox       = shown("BigNoteBoxReferenceBoxFrame")
    snap.sendToChat   = shown("BigNoteBoxSendDialog")
    snap.noteID       = noteID  -- needed to reopen note-specific windows
    -- Snapshot rich preview state before companion windows are closed
    snap.richPreview  = BNB.RichPreview and BNB.RichPreview.IsOpen()

    -- Close everything (HistoryCompare just closes, never restores)
    BNB.CloseCompanionWindows()
    if BNB.CloseReferenceBox then BNB.CloseReferenceBox() end

    -- Hide all open sticky notes
    local SN = BNB.Sticky
    if SN and SN.HideAll then
        snap.hadVisibleStickies = true
        SN.HideAll()
    end
    BNB._focusHiddenWindows = snap

    -- Centre focus frame over the main window (focus is fixed size)
    if BNB.mainFrame then
        CopyFrameCenter(BNB.mainFrame, focusFrame)
    end

    focusFrame:SetAlpha(0)
    focusFrame:Show()
    focusFrame:Raise()
    -- Suppress Narcissus AFK screensaver while focus mode is active
    if Narci then Narci.isActive = true end

    -- Open focus preview: always if setting is on; otherwise only if main preview was open
    local db2 = BigNoteBoxDB
    local alwaysShowPreview = db2 == nil or db2.focusPreviewAlwaysShow ~= false
    if (alwaysShowPreview or snap.richPreview) and BNB.RichPreviewFocus then
        BNB.RichPreviewFocus.Open(focusFrame, true)
    end

    LoadNoteInFocus(BNB._currentNoteID)

    -- Cross-fade: main out, focus in
    if BNB.mainFrame and BNB.mainFrame:IsShown() then
        local prevAlpha = BNB.mainFrame:GetAlpha()
        FadeTo(BNB.mainFrame, prevAlpha, 0, FADE_TIME, function()
            if BNB.mainFrame then
                BNB.mainFrame._focusHide = true
                BNB.mainFrame:Hide()
                BNB.mainFrame._focusHide = false
                BNB.mainFrame:SetAlpha(0.95)
            end
        end)
    end
    FadeTo(focusFrame, 0, 0.95, FADE_TIME)

    ShowFocusOverlay()

    -- If already AFK when focus mode opens, show the AFK overlay immediately
    if UnitIsAFK("player") then ShowAfkOverlay() end

    -- Hide entire WoW UI if setting is enabled
    if BigNoteBoxDB and BigNoteBoxDB.focusHideUI then
        C_Timer.After(FADE_TIME, function()
            if focusFrame and focusFrame:IsShown() then
                UIParent:Hide()
            end
        end)
    end

    C_Timer.After(FADE_TIME + 0.05, function()
        if focusBodyEb and BNB._currentNoteID
           and focusFrame and focusFrame:IsShown() then
            focusBodyEb:SetFocus()
        end
        if BNB.FocusOrbit then BNB.FocusOrbit.Start() end
    end)
end

--------------------------------------------------------------------------------
-- PUBLIC: CLOSE FOCUS MODE
--------------------------------------------------------------------------------
function BNB.CloseFocusMode()
    if not focusFrame or not focusFrame:IsShown() then return end
    if focusDirty then SaveFocusNote() end

    if BNB.FocusOrbit then BNB.FocusOrbit.Stop() end
    HideAfkOverlay()
    BNB.FadeOutFocusOverlay(0.5)
    -- Close focus preview window
    if BNB.RichPreviewFocus then BNB.RichPreviewFocus.Close() end
    -- Restore Narcissus guard flag (only if Narcissus isn't actually open)
    if Narci and not Narci.isAFK then Narci.isActive = false end

    -- Centre main window where focus frame currently is, then show it.
    -- _fromFocusMode suppresses RestoreWindowPos in OnShow so the position
    -- we just set isn't immediately overwritten from DB.
    if BNB.mainFrame then
        CopyFrameCenter(focusFrame, BNB.mainFrame)
        BNB.mainFrame:SetAlpha(0)
        BNB.mainFrame._focusHide = true
        BNB.mainFrame._fromFocusMode = true
        BNB.mainFrame:Show()
        BNB.mainFrame._focusHide = false
        if BNB._currentNoteID and BNB.LoadNoteInEditor then
            BNB.LoadNoteInEditor(BNB._currentNoteID)
        end
    end

    -- Always restore UIParent in case full-UI-hide was active
    UIParent:Show()

    -- Cross-fade: focus out, main in
    local fa = focusFrame:GetAlpha()
    FadeTo(focusFrame, fa, 0, FADE_TIME, function()
        if focusFrame then focusFrame:Hide() end
    end)
    if BNB.mainFrame then
        FadeTo(BNB.mainFrame, 0, 0.95, FADE_TIME)
    end

    -- Restore companion windows and stickies that were open when focus mode was entered.
    local snap = BNB._focusHiddenWindows
    BNB._focusHiddenWindows = nil
    if snap then
        local id = snap.noteID
        -- Restore sticky notes
        if snap.hadVisibleStickies and BNB.Sticky and BNB.Sticky.ShowAll then
            BNB.Sticky.ShowAll()
        end
        C_Timer.After(FADE_TIME + 0.05, function()
            if snap.noteConfig  and BNB.OpenNoteConfig       then BNB.OpenNoteConfig(id)       end
            if snap.config      then
                local cf = _G["BigNoteBoxConfigFrame"]
                if cf then cf:Show() end
            end
            if snap.trash       then
                local tw = _G["BigNoteBoxTrashFrame"]
                if tw then tw:Show() end
            end
            if snap.tagManager  and BNB.ToggleTagManager     then BNB.ToggleTagManager()       end
            if snap.historyWin  and BNB.OpenHistoryWindow    then BNB.OpenHistoryWindow()      end
            if snap.historyPanel and BNB.OpenNoteHistoryPanel then BNB.OpenNoteHistoryPanel(id) end
            if snap.refBox      and BNB.OpenReferenceBox     then BNB.OpenReferenceBox(id)     end
            if snap.sendToChat  and BNB.OpenSendToChat       then BNB.OpenSendToChat(id)       end
            if snap.richPreview and BNB.RichPreview          then BNB.RichPreview.Open()       end
        end)
    end
end

--------------------------------------------------------------------------------
-- PUBLIC: CLOSE FOCUS MODE AND BNB  (X button path)
-- Same as CloseFocusMode but also hides the main BNB window afterwards.
--------------------------------------------------------------------------------
function BNB.CloseFocusModeAndBNB()
    BNB.CloseFocusMode()
    -- Hide main window after the fade completes so it doesn't flash
    C_Timer.After(FADE_TIME + 0.1, function()
        if BNB.mainFrame and BNB.mainFrame:IsShown() then
            BNB.mainFrame._skipConfirm = true
            BNB.mainFrame:Hide()
            BNB.mainFrame._skipConfirm = false
        end
    end)
end

--------------------------------------------------------------------------------
-- PUBLIC: IS FOCUS MODE OPEN?
--------------------------------------------------------------------------------
function BNB.IsFocusModeOpen()
    return focusFrame and focusFrame:IsShown()
end

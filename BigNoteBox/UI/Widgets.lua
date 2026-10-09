-- BigNoteBox UI/Widgets.lua — Shared widget construction helpers
-- Visual style matches BCB: dark metal backdrop, SharedButtonTemplate buttons,
-- ScrollFrameTemplate scrollbars with smart hide/show.

local BNB = BigNoteBox
local L   = BNB.L

-- Width of the list windows beside the main window: Note History, Trash,
-- Alarms, Tag Manager (ALL-269; placement helpers in UI/ToolWindow.lua).
-- Here because those files read it at load time.
BNB.SIDE_WINDOW_W = 400

--------------------------------------------------------------------------------
-- BACKDROP DEFINITIONS
-- White8x8 bg + Tooltip border — present on all WoW versions.
-- Mirrors the BCB / ButtonFrameTemplate dark look.
--------------------------------------------------------------------------------
local BACKDROP_FRAME = {
    bgFile   = "Interface\\Buttons\\White8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile     = false, tileSize = 0, edgeSize = 14,
    insets   = { left = 3, right = 3, top = 3, bottom = 3 },
}
local BACKDROP_INSET = {
    bgFile   = "Interface\\Buttons\\White8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile     = false, tileSize = 0, edgeSize = 10,
    insets   = { left = 2, right = 2, top = 2, bottom = 2 },
}

function BNB.SetBackdrop(frame, r, g, b, a, bR, bG, bB, bA)
    if frame.SetBackdrop then
        frame:SetBackdrop(BACKDROP_FRAME)
        frame:SetBackdropColor(r or 0.06, g or 0.06, b or 0.06, a or 0.97)
        frame:SetBackdropBorderColor(bR or 0.40, bG or 0.40, bB or 0.40, bA or 1)
    end
end

function BNB.SetBackdropDark(frame)
    if frame.SetBackdrop then
        frame:SetBackdrop(BACKDROP_INSET)
        frame:SetBackdropColor(0.03, 0.03, 0.04, 0.98)
        frame:SetBackdropBorderColor(0.30, 0.30, 0.30, 1)
    end
end

-- BNB.CreateBarTextButton(parent, text, w, h) — small 10pt text button for the
-- markup bars (main and focus editor). Skin mode: a skin button (ALL-79);
-- normal mode: the panel button template with WoW's locale font.
function BNB.CreateBarTextButton(parent, text, w, h)
    if BigNoteBoxDB and BigNoteBoxDB.skinMode then
        return BNB.CreateSkinButton(nil, parent, text, w, h, 10)
    end
    local btn = CreateFrame("Button", nil, parent, BNB.PanelButtonTemplate())
    btn:SetSize(w, h)
    btn:SetText(text)
    local fs = btn:GetFontString()
    if fs then pcall(function() fs:SetFont(BNB.GetLocaleFont(), 10, "") end) end
    return btn
end

-- BNB.MakeToolbarFactory(bar, startX) — shared MkBtn/Divider pair for an
-- editor toolbar strip. Returns MkBtn(label, tip, onClick) and Divider(),
-- both advancing a shared x-offset starting at startX.
function BNB.MakeToolbarFactory(bar, startX)
    local btnX = startX or 0
    local function MkBtn(label, tip, onClick)
        local btn = BNB.CreateBarTextButton(bar, label, 28, 18)
        btn:SetPoint("LEFT", bar, "LEFT", btnX, 0)
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
        if BigNoteBoxDB and BigNoteBoxDB.skinMode then BNB.RegisterSkinRule(d, 0.40) end
        btnX = btnX + 6
    end
    return MkBtn, Divider
end

-- BNB.MakeLangLabel(entry) — language picker row label, prefixed with the
-- hardcoded English name for the "client" entry when the active language
-- isn't English (Dukul, 2026-09-23), plus the flag icon markup if present.
local LANG_CLIENT_LABEL_EN = "Client Language"
function BNB.MakeLangLabel(entry)
    local label = entry.label
    if entry.code == "client" and BNB.GetActiveLanguage and BNB.GetActiveLanguage() ~= "enUS" then
        label = LANG_CLIENT_LABEL_EN .. " - " .. label
    end
    if entry.flag then
        return "|T" .. entry.flag .. ":14:20:0:0:32:32|t " .. label
    end
    return label
end

--------------------------------------------------------------------------------
-- KEYBOARD WINDOWS AND COMBAT (BUG-05, ALL-136.4)
-- SetPropagateKeyboardInput is protected in combat: a call raises
-- ADDON_ACTION_BLOCKED and the value stays as it was (confirmed by Dukul,
-- 2026-10-01). EnableKeyboard is kept out of combat as well. So:
--  * every propagation change goes through BNB.SetPropagate (skipped in combat);
--  * a window that closes on ESC uses BNB.AttachEscClose. In combat it does
--    nothing, so every key, ESC included, goes to the game, which closes the
--    windows in UISpecialFrames, clears the target or opens the game menu;
--  * every registered frame is set to propagate when combat starts
--    (PLAYER_REGEN_DISABLED fires before the lockdown), and AttachEscClose
--    sets it back to propagate one frame after taking an ESC, so a window is
--    never left swallowing keys.
--------------------------------------------------------------------------------
function BNB.SetPropagate(f, on)
    if not InCombatLockdown() then f:SetPropagateKeyboardInput(on) end
end

local _kbFrames      = {}   -- [frame] = onCombat function or true
local _kbEnableLater = {}   -- frames built in combat, keyboard on when it ends

-- onCombat(f), optional: runs when combat starts, before the reset to
-- propagate (the keybind capture ends a running capture there).
function BNB.RegisterKeyboardFrame(f, onCombat)
    _kbFrames[f] = onCombat or true
end

local function EnableKeyboardSafe(f)
    if InCombatLockdown() then _kbEnableLater[f] = true; return end
    f:EnableKeyboard(true)
    f:SetPropagateKeyboardInput(true)
end

-- stepAside for windows that leave ESC to the main window's cascade while it is up
function BNB.MainWindowShown()
    return BNB.mainFrame and BNB.mainFrame:IsShown() or false
end

-- closeFn(self): what ESC does (may close a child window first).
-- stepAside(self), optional: true = leave this ESC to the game or to the main
-- window's cascade (callers pass "main window is shown" or "game menu is up").
function BNB.AttachEscClose(f, closeFn, stepAside)
    BNB.RegisterKeyboardFrame(f)
    f:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end
        if key ~= "ESCAPE" or (stepAside and stepAside(self)) then
            self:SetPropagateKeyboardInput(true); return
        end
        self:SetPropagateKeyboardInput(false)
        C_Timer.After(0, function() BNB.SetPropagate(self, true) end)
        closeFn(self)
    end)
    EnableKeyboardSafe(f)
end

BNB.RegisterEvent("PLAYER_REGEN_DISABLED", function()
    if InCombatLockdown() then return end
    for f, onCombat in pairs(_kbFrames) do
        if onCombat ~= true then pcall(onCombat, f) end
        f:SetPropagateKeyboardInput(true)
    end
end)

BNB.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    for f in pairs(_kbEnableLater) do
        _kbEnableLater[f] = nil
        EnableKeyboardSafe(f)
    end
end)

-- BNB.WireKeybindCapture(kbBtn, action, UpdateText, pressText)
-- Shared keybind-row click handling: right-click clears the binding,
-- left-click enters capture mode and applies the next non-modifier key
-- (with a conflict prompt via the shared BNB_KEYBIND_CONFLICT StaticPopup).
-- Registers the StaticPopup once, guarded, and calls SetPropagateKeyboardInput
-- for keys it does not handle (keyboard-routing rule, CLAUDE.md).
local _KB_MODIFIER_KEYS = {
    LSHIFT=true, RSHIFT=true, LCTRL=true, RCTRL=true, LALT=true, RALT=true,
}
if not StaticPopupDialogs["BNB_KEYBIND_CONFLICT"] then
    StaticPopupDialogs["BNB_KEYBIND_CONFLICT"] = {
        text = "%s", button1 = YES, button2 = NO,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        OnAccept = function(_, data)
            if data and data.applyFn then data.applyFn(data.fullKey) end
        end,
    }
end

function BNB.WireKeybindCapture(kbBtn, action, UpdateText, pressText)
    local function StopCapture(btn)
        btn._capturing = false
        btn:EnableKeyboard(false)
        btn:SetScript("OnKeyDown", nil)
        BNB.SetPropagate(btn, true)
        UpdateText()
    end
    -- A capture still running when combat starts ends there, while
    -- EnableKeyboard and SetBinding are still allowed
    BNB.RegisterKeyboardFrame(kbBtn, function(btn)
        if btn._capturing then StopCapture(btn) end
    end)

    local function ApplyBind(fullKey)
        local k1, k2 = GetBindingKey(action)
        if k1 then SetBinding(k1, nil) end
        if k2 then SetBinding(k2, nil) end
        SetBinding(fullKey, action)
        SaveBindings(GetCurrentBindingSet())
        UpdateText()
    end

    local function OnKeyCaptured(btn, key)
        if _KB_MODIFIER_KEYS[key] then return end
        if InCombatLockdown() then return end
        btn:SetPropagateKeyboardInput(false)
        if key == "ESCAPE" then StopCapture(btn); return end
        local mods = {}
        if IsAltKeyDown()     then mods[#mods+1] = "ALT"   end
        if IsControlKeyDown() then mods[#mods+1] = "CTRL"  end
        if IsShiftKeyDown()   then mods[#mods+1] = "SHIFT" end
        mods[#mods+1] = key
        local fullKey = table.concat(mods, "-")
        StopCapture(btn)
        local existing = GetBindingAction(fullKey)
        if existing and existing ~= "" and existing ~= action then
            local msg = string.format(L["KEYBIND_CONFLICT"],
                GetBindingText(fullKey), GetBindingName(existing))
            StaticPopup_Show("BNB_KEYBIND_CONFLICT", msg, nil,
                { fullKey = fullKey, applyFn = ApplyBind })
            return
        end
        ApplyBind(fullKey)
    end

    kbBtn:SetScript("OnClick", function(btn, button)
        -- SetBinding and EnableKeyboard are blocked in combat
        if InCombatLockdown() then BNB:Print(L["COMBAT_BLOCKED"]); return end
        if button == "RightButton" then
            local k1, k2 = GetBindingKey(action)
            if k1 then SetBinding(k1, nil) end
            if k2 then SetBinding(k2, nil) end
            if k1 or k2 then SaveBindings(GetCurrentBindingSet()) end
            UpdateText(); GameTooltip:Hide()
        else
            btn:SetText(pressText)
            btn._capturing = true
            btn:EnableKeyboard(true)
            btn:SetPropagateKeyboardInput(false)
            btn:SetScript("OnKeyDown", OnKeyCaptured)
        end
    end)
end

function BNB.GetDeflate()
    return LibStub and LibStub("LibDeflate", true)
end

--------------------------------------------------------------------------------
-- ENSURE BACKDROP MIXIN
--------------------------------------------------------------------------------
function BNB.EnsureBackdrop(frame)
    if not frame.SetBackdrop then
        pcall(function() Mixin(frame, BackdropTemplateMixin) end)
    end
end

function BNB.CreateBackdropFrame(frameType, name, parent, extraTemplate)
    local tpl = "BackdropTemplate" .. (extraTemplate and ("," .. extraTemplate) or "")
    local f = CreateFrame(frameType or "Frame", name, parent, tpl)
    BNB.EnsureBackdrop(f)
    return f
end

--------------------------------------------------------------------------------
-- PANEL BUTTON TEMPLATE  (ALL-43)
-- SharedButtonTemplate is the current Blizzard button: red with bronze edges
-- on Forever, grey edges on Retail, and sharp at any size. UIPanelButtonTemplate
-- is the old low-res one, kept only as the fallback for a client without it.
-- Normal-mode buttons that bypass BNB.CreateButton (to stay un-skinned in skin
-- mode) take their template from here, so every button matches.
--------------------------------------------------------------------------------
local _panelBtnTpl
function BNB.PanelButtonTemplate()
    if not _panelBtnTpl then
        _panelBtnTpl = (C_XMLUtil and C_XMLUtil.GetTemplateInfo
            and C_XMLUtil.GetTemplateInfo("SharedButtonTemplate"))
            and "SharedButtonTemplate" or "UIPanelButtonTemplate"
    end
    return _panelBtnTpl
end

--------------------------------------------------------------------------------
-- UI PANEL BUTTON  (the standard WoW button, see BNB.PanelButtonTemplate)
-- Returns: button
--------------------------------------------------------------------------------
function BNB.CreateButton(name, parent, text, w, h)
    if BigNoteBoxDB and BigNoteBoxDB.skinMode then
        return BNB.CreateSkinButton(name, parent, text, w, h)
    end
    local btn = CreateFrame("Button", name, parent, BNB.PanelButtonTemplate())
    btn:SetSize(w or 80, h or 22)
    btn:SetText(text or "")
    return btn
end

-- State buttons in a 2-column grid at (0, y) of parent, `width` wide (ALL-256,
-- Note Settings; Sticky settings ALL-257). defs = { { text = fn -> label,
-- tip = fn -> title, body, onClick = fn, enabled = fn or nil }, ... }: the
-- label says what a click does and follows the state through Refresh, as does
-- the enabled state when `enabled` is given. Returns the y under the grid and
-- the Refresh function.
function BNB.CreateStateButtonGrid(parent, y, width, defs, h)
    h = h or 24
    local GAP = 6
    local bw  = math.floor((width - GAP) / 2)
    local btns = {}
    local function Refresh()
        for _, b in ipairs(btns) do
            b:SetText(b._def.text() or "")
            if b._def.enabled then
                local on = b._def.enabled() and true or false
                b:SetEnabled(on)   -- a skin button greys its own label (ALL-392)
            end
        end
    end
    for i, def in ipairs(defs) do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        local b = BNB.CreateButton(nil, parent, "", bw, h)
        b:SetPoint("TOPLEFT", parent, "TOPLEFT", col * (bw + GAP), y - row * (h + 4))
        b._def = def
        b:SetScript("OnClick", function() def.onClick(); Refresh() end)
        if def.tip then
            b:SetScript("OnEnter", function(s)
                local title, body = def.tip()
                GameTooltip:SetOwner(s, "ANCHOR_TOP")
                if title then GameTooltip:AddLine(title, 1, 0.82, 0) end
                if body then GameTooltip:AddLine(body, 0.85, 0.85, 0.85, true) end
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        BNB.TruncateButtonText(b)
        btns[#btns + 1] = b
    end
    Refresh()
    local rows = math.ceil(#defs / 2)
    return y - rows * (h + 4) + 4, Refresh
end

-- Keeps a BNB.CreateButton label inside the button: fixed width, one line,
-- ends in "..." when too long (an icon name overflowed the Note Settings
-- Icon button, Dukul 2026-10-04). pad = room on each side, default 8.
function BNB.TruncateButtonText(btn, pad)
    local fs = btn._lbl or (btn.GetFontString and btn:GetFontString())
    if not fs then return end
    pad = pad or 8
    fs:ClearAllPoints()
    fs:SetPoint("LEFT",  btn, "LEFT",   pad, 0)
    fs:SetPoint("RIGHT", btn, "RIGHT", -pad, 0)
    fs:SetWordWrap(false)
end

--------------------------------------------------------------------------------
-- TINT BUTTON  (skin mode only)
-- Recolours all texture regions of a UIPanelButtonTemplate-based button to
-- match the current skin preset's border colour, and sets the label white.
-- Call after button creation, and again on OnShow if preset may change.
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- SKIN BUTTON  (skin mode only)
-- A backdrop-based Button that matches the current preset and never uses
-- UIPanelButtonTemplate — avoiding NineSlice vertex-colour issues entirely.
-- w, h, fontSize default to 80, 22, 13.
-- Registered with ApplyMainWindowSkin so it updates on preset change.
--------------------------------------------------------------------------------
local _skinLabelFonts = setmetatable({}, { __mode = "k" })   -- button -> its ApplyLabelFont
if BNB.RegisterMessage then
    BNB.RegisterMessage("Widgets.SkinLabelFont", "UIFontChanged", function()
        for _, apply in pairs(_skinLabelFonts) do apply() end
    end)
end

function BNB.CreateSkinButton(name, parent, text, w, h, fontSize)
    w = w or 80; h = h or 22; fontSize = fontSize or 13

    local btn = CreateFrame("Button", name, parent, "BackdropTemplate")
    btn:SetSize(w, h)

    local function ApplyPreset()
        local p = BNB.GetSkinPreset and BNB.GetSkinPreset()
        if not p then return end
        local r, g, b = BNB.SkinButtonOf(p)
        local br, bg_, bb = BNB.SkinBorderOf(p)
        BNB.SetBackdrop(btn, r, g, b, 0.92, br, bg_, bb, 1)
        btn._br, btn._bg_, btn._bb = r, g, b
    end
    ApplyPreset()

    -- Highlight overlay on mouse over — inset 2px to stay inside the border
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
    hl:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
    hl:SetColorTexture(1, 1, 1, 0.10)

    -- Darken on mouse down, restore on mouse up. A disabled button still gets
    -- the mouse events: no press look then (ALL-392). The label moves 1 px
    -- down-right while held, as a skin icon button's symbol does (ALL-420).
    -- Its own anchors are kept and put back: some callers re-anchor the label
    -- (BNB.TruncateButtonText pads it)
    local function PressLabel(on)
        local l = btn._lbl
        if not l then return end
        if on then
            if btn._lblPts then return end
            local pts = {}
            for i = 1, l:GetNumPoints() do pts[i] = { l:GetPoint(i) } end
            btn._lblPts = pts
            l:ClearAllPoints()
            for _, pt in ipairs(pts) do l:SetPoint(pt[1], pt[2], pt[3], (pt[4] or 0) + 1, (pt[5] or 0) - 1) end
        elseif btn._lblPts then
            local pts = btn._lblPts
            btn._lblPts = nil
            l:ClearAllPoints()
            for _, pt in ipairs(pts) do l:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5]) end
        end
    end
    btn:SetScript("OnMouseDown", function(self)
        if not self:IsEnabled() then return end
        PressLabel(true)
        if self.SetBackdropColor then
            self:SetBackdropColor(
                (self._br or 0.10) * 0.70,
                (self._bg_ or 0.10) * 0.70,
                (self._bb or 0.12) * 0.70, 0.95)
        end
    end)
    btn:SetScript("OnMouseUp", function(self)
        PressLabel(false)
        if self.SetBackdropColor then
            self:SetBackdropColor(self._br or 0.10, self._bg_ or 0.10, self._bb or 0.12, 0.92)
        end
    end)

    -- Label in OVERLAY — above backdrop, unaffected by highlight.
    -- Starts with GameFontNormal (always safe) and upgrades to the TTF body font
    -- once BNB.InitFonts has run. On first login, CreateSkinButton can run before
    -- PLAYER_LOGIN / InitFonts — if we SetFont to a TTF path before the renderer
    -- has cached the file, the label renders blank. This defers the swap so the
    -- button always shows text, even on the very first session open.
    local lbl = btn:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    lbl:SetAllPoints()
    lbl:SetJustifyH("CENTER")
    lbl:SetJustifyV("MIDDLE")
    BNB.SetTextWhite(lbl)
    lbl:SetText(text or "")
    btn._lbl = lbl

    local function ApplyLabelFont()
        if not BNB._fontsInitialised then return false end
        local ok = pcall(function()
            local path = BNB.GetUIFont and BNB.GetUIFont()
            if path then lbl:SetFont(path, fontSize, "") end
        end)
        return ok
    end

    -- A font change re-applies it live (ALL-25; weak table, one handler)
    _skinLabelFonts[btn] = ApplyLabelFont

    -- Try once now (works on every session after the first, once InitFonts has run).
    if not ApplyLabelFont() then
        -- Not ready yet — retry when the button is first shown, and again shortly
        -- after in case InitFonts is still pending on that exact frame.
        local tried = false
        btn:HookScript("OnShow", function()
            if tried then return end
            if ApplyLabelFont() then tried = true; return end
            C_Timer.After(0.1, function()
                if ApplyLabelFont() then tried = true end
            end)
        end)
    end

    -- Disabled = dimmed label (ALL-392), as the template buttons do. The colour
    -- a caller set (state grids colour their labels) comes back on enable.
    btn:HookScript("OnHide", function() PressLabel(false) end)
    btn:HookScript("OnDisable", function()
        PressLabel(false)
        if not btn._lblCol then btn._lblCol = { lbl:GetTextColor() } end
        lbl:SetTextColor(0.5, 0.5, 0.5)
    end)
    btn:HookScript("OnEnable", function()
        local c = btn._lblCol
        btn._lblCol = nil
        if c then lbl:SetTextColor(c[1], c[2], c[3]) end
    end)

    -- Mimic standard Button API
    function btn:SetText(t) lbl:SetText(t or "") end
    function btn:GetText() return lbl:GetText() end
    function btn:GetFontString() return lbl end

    -- Re-skin when preset changes (triggered by ApplyMainWindowSkin), and on
    -- every show, which is why the registry may skip it while hidden.
    btn:HookScript("OnShow", ApplyPreset)
    BNB.RegisterSkinButton(ApplyPreset, btn)

    return btn
end

--------------------------------------------------------------------------------
-- SCROLL FRAME  (ALL-171 / ALL-172)
-- Every ScrollFrameTemplate frame is made here. Retail and Forever get the
-- template's MinimalScrollBar. Classic's template builds the wide
-- WoWClassicScrollBar (SCROLL_FRAME_SCROLL_BAR_TEMPLATE in the client's
-- ScrollDefine.lua), which stuck out of our windows; the Classic clients ship
-- MinimalScrollBar too, so it is swapped in with Retail's offsets and bound the
-- way the template's ScrollFrame_OnLoad binds its own bar. Done before the caller
-- sets any script: the bind SetScripts OnVerticalScroll, OnScrollRangeChanged and
-- OnMouseWheel.
--------------------------------------------------------------------------------
function BNB.CreateScrollFrame(name, parent)
    local sf = CreateFrame("ScrollFrame", name, parent, "ScrollFrameTemplate")
    local old = sf.ScrollBar
    if BNB.IsClassic and old and ScrollUtil and ScrollUtil.InitScrollFrameWithScrollBar then
        local ok, bar = pcall(CreateFrame, "EventFrame", nil, sf, "MinimalScrollBar")
        if ok and bar then
            old:Hide()
            old:ClearAllPoints()
            bar:SetPoint("TOPLEFT", sf, "TOPRIGHT", 6, 2)
            bar:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 6, 5)
            if bar.SetHideIfUnscrollable then bar:SetHideIfUnscrollable(sf.scrollBarHideIfUnscrollable) end
            sf.ScrollBar = bar
            bar:Show()
            ScrollUtil.InitScrollFrameWithScrollBar(sf, bar)
            if bar.Update then bar:Update() end
        end
    end
    BNB.SkinScrollBar(sf.ScrollBar)
    return sf
end

--------------------------------------------------------------------------------
-- SKIN-MODE SCROLLBARS  (ALL-393)
-- In skin mode the scrollbar keeps the game's own art, desaturated and tinted to
-- the preset's border colour (Dukul 2026-10-08, from the /bnbskinw test:
-- "Tinted game art with tint at 1.00"): track darker, arrows and thumb lighter.
-- Skin mode is set at build time (switching it reloads); a preset change
-- re-tints every bar through SkinChanged. The thumb and arrows swap atlases on
-- hover / press and the arrows re-desaturate on enable, so those re-tint.
-- Normal mode: untouched.
--------------------------------------------------------------------------------
local SB_TINT = { track = 0.7, thumb = 1.4, arrow = 1.2, sliderTrackAlpha = 0.7 }
local _skinBars = setmetatable({}, { __mode = "k" })   -- frame -> its tint function

local function TintRegions(frame, m, deep, r, g, b, alpha)
    if not frame then return end
    for _, t in ipairs({ frame:GetRegions() }) do
        if t.IsObjectType and t:IsObjectType("Texture") then
            t:SetDesaturated(true)
            t:SetVertexColor(math.min(1, r * m), math.min(1, g * m), math.min(1, b * m))
            if alpha then t:SetAlpha(alpha) end
        end
    end
    if deep then
        for _, c in ipairs({ frame:GetChildren() }) do TintRegions(c, m, true, r, g, b, alpha) end
    end
end

local function TintScrollBar(bar)
    local p = BNB.GetSkinPreset and BNB.GetSkinPreset()
    if not p then return end
    local r, g, b = BNB.SkinBorderOf(p)
    local track = bar.Track
    TintRegions(track, SB_TINT.track, false, r, g, b)
    TintRegions(track and track.Thumb, SB_TINT.thumb, false, r, g, b)
    TintRegions(bar.Back, SB_TINT.arrow, true, r, g, b)
    TintRegions(bar.Forward, SB_TINT.arrow, true, r, g, b)
end

-- Registers a tinted widget: tint now, again after its parts change state
-- (hover / press / enable swap atlases or reset desaturation), and on SkinChanged
local _sbMsg = false
local function KeepTinted(key, tint, parts)
    _skinBars[key] = tint
    tint()
    local function Again() C_Timer.After(0, tint) end
    for _, f in ipairs(parts) do
        if f and f.HookScript then
            for _, script in ipairs({ "OnEnter", "OnLeave", "OnMouseUp", "OnEnable", "OnDisable" }) do
                pcall(f.HookScript, f, script, Again)
            end
        end
    end
    if not _sbMsg and BNB.RegisterMessage then
        _sbMsg = true
        BNB.RegisterMessage("SkinScrollBars", "SkinChanged", function()
            for _, fn in pairs(_skinBars) do pcall(fn) end
        end)
    end
end

function BNB.SkinScrollBar(bar)
    if not bar or _skinBars[bar] or not (BigNoteBoxDB and BigNoteBoxDB.skinMode) then return end
    local track = bar.Track
    KeepTinted(bar, function() TintScrollBar(bar) end, { track and track.Thumb, bar.Back, bar.Forward })
end

-- Skin-mode sliders (ALL-393, Dukul 2026-10-08: "skin the value sliders"):
-- MinimalSliderWithSteppersTemplate tinted like the scrollbars, track darker,
-- thumb and stepper arrows lighter, half as bright while disabled. Called by
-- BNB.CreateStackedSlider, the one slider builder.
function BNB.SkinSlider(sl)
    if not sl or _skinBars[sl] or not (BigNoteBoxDB and BigNoteBoxDB.skinMode) then return end
    local inner = sl.Slider
    local function Tint()
        local p = BNB.GetSkinPreset and BNB.GetSkinPreset()
        if not p then return end
        local r, g, b = BNB.SkinBorderOf(p)
        local dim = (inner and inner.IsEnabled and not inner:IsEnabled()) and 0.5 or 1
        -- The track at 0.7 opacity, not solid black (ALL-413, Dukul 2026-10-09)
        TintRegions(inner, SB_TINT.track * dim, false, r, g, b, SB_TINT.sliderTrackAlpha)
        local thumb = inner and inner.GetThumbTexture and inner:GetThumbTexture()
        if thumb then
            local m = SB_TINT.thumb * dim
            thumb:SetAlpha(1)   -- the thumb is one of the slider's regions too
            thumb:SetDesaturated(true)
            thumb:SetVertexColor(math.min(1, r * m), math.min(1, g * m), math.min(1, b * m))
        end
        TintRegions(sl.Back, SB_TINT.arrow * dim, true, r, g, b)
        TintRegions(sl.Forward, SB_TINT.arrow * dim, true, r, g, b)
    end
    KeepTinted(sl, Tint, { inner, sl.Back, sl.Forward })
end

--------------------------------------------------------------------------------
-- SKIN-MODE DROPDOWNS  (ALL-393, the closed box half of ALL-80)
-- In skin mode a dropdown is drawn with our own skin pieces (Dukul 2026-10-08,
-- from the /bnbskinw test: "Flat drawn dropdown"): the skin text button
-- (CreateSkinButton) as the box and a square skin icon button with the "down"
-- symbol at its right end. Both sit under the real WowStyle1 dropdown as a
-- sibling with the mouse off; the dropdown's art is hidden (alpha 0, the
-- template keeps swapping atlases), its text kept, its hover / press / enabled
-- state and its alpha / visibility passed on. The open menu is still the
-- game's (ALL-80's menu hook). Usage: wrap the CreateFrame call,
--   local dd = BNB.SkinDropdown(CreateFrame("DropdownButton", nil, p, "WowStyle1DropdownTemplate"))
-- Normal mode: returns dd untouched.
--
-- The open list (Dukul 2026-10-08: the Flat column's list in /bnbskinw): while
-- one of our dropdowns has the game's menu open, the menu's own background is
-- hidden and our skin box lent to it (fill = preset colour, border = preset
-- border), and the game's atlas chrome on the rows (radio / check marks,
-- highlight, arrows, its scrollbar) is desaturated and tinted to the border.
-- Plain textures (icons in entries) are left alone. Menu frames are pooled and
-- shared with every addon, so every touched texture is put back as it was on
-- close. A ticker re-tints rows a scrolling menu acquires while open.
-- Submenus keep the game's look.
--------------------------------------------------------------------------------
local _menuSkin              -- our one skin box, lent to the open menu
local _touched = {}          -- texture -> { desaturated, r, g, b, a, alpha }
local _menuTicker, _openMenu
local MENU_TINT = 1.4

local function Touch(t)
    if _touched[t] then return end
    local r, g, b, a = t:GetVertexColor()
    _touched[t] = { t:IsDesaturated(), r, g, b, a, t:GetAlpha() }
end

local function RestoreMenu()
    if _menuTicker then _menuTicker:Cancel(); _menuTicker = nil end
    for t, s in pairs(_touched) do
        t:SetDesaturated(s[1]); t:SetVertexColor(s[2], s[3], s[4], s[5]); t:SetAlpha(s[6])
    end
    wipe(_touched)
    if _menuSkin then _menuSkin:Hide(); _menuSkin:SetParent(UIParent) end
    _openMenu = nil
end

local function TintMenu(menu)
    if not (menu and menu:IsShown()) or _openMenu ~= menu then RestoreMenu(); return end
    local p = BNB.GetSkinPreset and BNB.GetSkinPreset()
    if not p then return end
    local br, bg, bb = BNB.SkinBorderOf(p)
    local tr, tg, tb = math.min(1, br * MENU_TINT), math.min(1, bg * MENU_TINT), math.min(1, bb * MENU_TINT)
    for _, t in ipairs({ menu:GetRegions() }) do   -- the menu's own background
        if t.IsObjectType and t:IsObjectType("Texture") then Touch(t); t:SetAlpha(0) end
    end
    local function Walk(f)
        for _, c in ipairs({ f:GetChildren() }) do
            if c ~= _menuSkin then
                for _, t in ipairs({ c:GetRegions() }) do
                    local atlas = t.IsObjectType and t:IsObjectType("Texture") and t.GetAtlas and t:GetAtlas()
                    if atlas and atlas:find("dropdown%-bg") then
                        Touch(t); t:SetAlpha(0)   -- the background on a style child
                    elseif atlas then
                        Touch(t); t:SetDesaturated(true); t:SetVertexColor(tr, tg, tb)
                    end
                end
                Walk(c)
            end
        end
    end
    Walk(menu)
end

local function SkinOpenMenu(menu)
    if not menu and Menu and Menu.GetManager then
        local mgr = Menu.GetManager()
        menu = mgr and mgr.GetOpenMenu and mgr:GetOpenMenu()
    end
    if not menu then return end
    RestoreMenu()
    _openMenu = menu
    if not _menuSkin then _menuSkin = BNB.CreateBackdropFrame("Frame", nil, UIParent) end
    local p = BNB.GetSkinPreset and BNB.GetSkinPreset()
    if p then
        local br, bg, bb = BNB.SkinBorderOf(p)
        BNB.SetBackdrop(_menuSkin, p.r, p.g, p.b, 0.96, br, bg, bb, 1)
    end
    _menuSkin:SetParent(menu)
    _menuSkin:ClearAllPoints()
    _menuSkin:SetAllPoints(menu)
    _menuSkin:SetFrameLevel(menu:GetFrameLevel())   -- under the rows
    _menuSkin:Show()
    TintMenu(menu)
    _menuTicker = C_Timer.NewTicker(0.15, function() TintMenu(menu) end)
end

function BNB.SkinDropdown(dd)
    if not dd or dd._skinDD or not (BigNoteBoxDB and BigNoteBoxDB.skinMode) then return dd end
    dd._skinDD = true
    local vis, arrow

    local function HideArt()
        for _, t in ipairs({ dd:GetRegions() }) do
            if t.IsObjectType and t:IsObjectType("Texture") then t:SetAlpha(0) end
        end
        for _, c in ipairs({ dd:GetChildren() }) do
            for _, t in ipairs({ c:GetRegions() }) do
                if t.IsObjectType and t:IsObjectType("Texture") then t:SetAlpha(0) end
            end
        end
        local on = dd:IsEnabled()
        if dd.Text then
            if on then dd.Text:SetTextColor(BNB.TextWhite()) else dd.Text:SetTextColor(0.5, 0.5, 0.5) end
        end
        if vis then vis:SetEnabled(on) end
        if arrow then arrow:SetEnabled(on) end
    end
    local function Pass(f, script)
        local fn = f and f:GetScript(script)
        if fn then pcall(fn, f) end
    end

    -- Built once the dropdown has its size (sites set width / height after
    -- CreateFrame); the arrow button's box is chosen by its size
    local function Build()
        if vis then return end
        local h = math.floor(dd:GetHeight() + 0.5)
        if h < 10 then h = 26 end
        vis = BNB.CreateSkinButton(nil, dd:GetParent(), "", math.max(1, dd:GetWidth()), h)
        vis:SetAllPoints(dd)
        vis:SetFrameLevel(math.max(0, dd:GetFrameLevel() - 1))
        vis:EnableMouse(false)
        vis:SetAlpha(dd:GetAlpha())
        vis:SetShown(dd:IsShown())
        arrow = BNB.CreateIconButton(vis, h, "down", { skin = true })
        arrow:SetPoint("RIGHT", vis, "RIGHT", 0, 0)
        arrow:EnableMouse(false)
        HideArt()
    end
    if dd:IsVisible() then C_Timer.After(0, Build) end

    local function Later() C_Timer.After(0, HideArt) end
    dd:HookScript("OnShow", function() Build(); if vis then vis:Show() end; Later() end)
    dd:HookScript("OnHide", function() if vis then vis:Hide() end end)
    dd:HookScript("OnSizeChanged", function()
        if arrow then
            local h = math.floor(dd:GetHeight() + 0.5)
            if h >= 10 then arrow:SetSize(h, h) end
        end
    end)
    dd:HookScript("OnEnter", function()
        if vis and dd:IsEnabled() then vis:LockHighlight(); Pass(arrow, "OnEnter") end
        Later()
    end)
    dd:HookScript("OnLeave", function()
        if vis then vis:UnlockHighlight(); Pass(vis, "OnMouseUp"); Pass(arrow, "OnLeave") end
        Later()
    end)
    dd:HookScript("OnMouseDown", function()
        if vis and dd:IsEnabled() then Pass(vis, "OnMouseDown"); Pass(arrow, "OnMouseDown") end
    end)
    dd:HookScript("OnMouseUp", function()
        if vis then Pass(vis, "OnMouseUp"); Pass(arrow, "OnMouseUp") end
        Later()
    end)
    dd:HookScript("OnEnable", Later)
    dd:HookScript("OnDisable", Later)
    -- Greying by alpha (some pages fade a dropdown instead of disabling it)
    hooksecurefunc(dd, "SetAlpha", function(_, a) if vis then vis:SetAlpha(a) end end)
    BNB.SkinDropdownMenu(dd)
    return dd
end

-- The open list only (see above), for an invisible menu anchor whose visible
-- box is drawn some other way (the formatting toolbar's font / size pickers).
-- DropdownButtonMixin calls these with the menu. Normal mode: no-op.
function BNB.SkinDropdownMenu(dd)
    if not dd or dd._skinMenu or not (BigNoteBoxDB and BigNoteBoxDB.skinMode) then return dd end
    dd._skinMenu = true
    if dd.OnMenuOpened then
        hooksecurefunc(dd, "OnMenuOpened", function(_, menu) pcall(SkinOpenMenu, menu) end)
    end
    if dd.OnMenuClosed then
        hooksecurefunc(dd, "OnMenuClosed", function(_, menu)
            if menu == nil or menu == _openMenu then RestoreMenu() end
        end)
    end
    return dd
end

--------------------------------------------------------------------------------
-- SMART SCROLL FRAME  (mirrors BCB's CreateSmartScrollFrame)
-- "ScrollFrameTemplate" — modern scrollbar inside frame bounds.
-- Scrollbar auto-hides when content fits.
-- Caller anchors the scroll frame; this function only sets up the child and bar.
--
-- Returns: scrollFrame, scrollChild
--------------------------------------------------------------------------------
function BNB.CreateSmartScrollFrame(name, parent)
    local sf = BNB.CreateScrollFrame(name, parent)

    local scrollBar = sf.ScrollBar   -- exists on ScrollFrameTemplate

    local child = CreateFrame("Frame", name and (name .. "Child") or nil, sf)
    child:SetWidth(sf:GetWidth())
    child:SetHeight(1)
    sf:SetScrollChild(child)

    -- Hide scrollbar when content fits; restore when scrollable.
    -- Alpha-only — never Show/Hide, which fights ScrollFrameTemplate.
    if scrollBar then
        scrollBar:SetAlpha(0)
        sf:HookScript("OnScrollRangeChanged", function(_, _, yRange)
            scrollBar:SetAlpha((yRange or 0) > 1 and 1.0 or 0)
        end)
    end

    function sf:UpdateScrollbar()
        C_Timer.After(0.05, function()
            if not sf:IsVisible() then return end
            local contentH = child:GetHeight()
            local visibleH = sf:GetHeight()
            if scrollBar then
                scrollBar:SetAlpha(contentH > visibleH + 2 and 1.0 or 0)
            end
        end)
    end

    sf:SetScript("OnSizeChanged", function(self)
        child:SetWidth(self:GetWidth())
    end)

    return sf, child
end

--------------------------------------------------------------------------------
-- SCROLLED EDIT BOX  (multi-line body editor)
-- Uses ScrollFrameTemplate.  Returns: scrollFrame, editBox
--------------------------------------------------------------------------------
function BNB.CreateScrolledEditBox(name, parent, fontSize)
    local sf = BNB.CreateScrollFrame(name, parent)

    local eb = CreateFrame("EditBox", name and (name .. "EditBox") or nil, sf)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject("BNBFontNormal")
    if fontSize then
        local fontPath = eb:GetFont()
        if fontPath then pcall(function() eb:SetFont(fontPath, fontSize, "") end) end
    end
    eb:SetTextInsets(6, 6, 4, 4)
    eb:SetMaxLetters(0)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    sf:SetScrollChild(eb)

    local scrollBar = sf.ScrollBar

    -- Hide scrollbar when content fits; restore when scrollable.
    -- Alpha-only — never Show/Hide, which fights ScrollFrameTemplate.
    if scrollBar then
        scrollBar:SetAlpha(0)
        sf:HookScript("OnScrollRangeChanged", function(_, _, yRange)
            scrollBar:SetAlpha((yRange or 0) > 1 and 1.0 or 0)
        end)
    end

    ---------------------------------------------------------------------------
    -- Width sync — sf has no anchors at creation time.
    -- When the scrollbar is visible, subtract its width so the editbox
    -- matches the actual visible text area.
    ---------------------------------------------------------------------------
    local function SyncWidth()
        local w = sf:GetWidth()
        if not w or w <= 0 then return end
        if scrollBar and scrollBar:IsShown() then
            local sbW = scrollBar:GetWidth()
            if sbW and sbW > 0 then w = w - sbW end
        end
        eb:SetWidth(w)
    end

    sf:SetScript("OnSizeChanged", function(self) SyncWidth() end)
    sf:HookScript("OnShow", function()
        C_Timer.After(0, function() SyncWidth() end)
    end)

    function sf:UpdateScrollbar()
        -- ScrollFrameTemplate manages scrollbar natively.
        -- Re-sync width in case scrollbar appeared/disappeared.
        C_Timer.After(0.05, function()
            if sf:IsVisible() then SyncWidth() end
        end)
    end

    sf:SetScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" then eb:SetFocus() end
    end)

    -- Scroll to top on SetText (note load).
    local _isSetTextCall = false
    hooksecurefunc(eb, "SetText", function()
        _isSetTextCall = true
        C_Timer.After(0, function()
            if _isSetTextCall then
                SyncWidth()
                sf:SetVerticalScroll(0)
                _isSetTextCall = false
            end
        end)
    end)

    -- Re-sync width on text change (scrollbar may appear/disappear).
    eb:SetScript("OnTextChanged", function(self)
        C_Timer.After(0.05, function()
            if sf:IsVisible() then SyncWidth() end
        end)
    end)

    -- Cursor follow — scroll the parent to keep the caret visible as the user types.
    eb:SetScript("OnCursorChanged", function(self, _, y, _, h)
        y = -y
        local offset = sf:GetVerticalScroll()
        if y < offset then
            sf:SetVerticalScroll(y)
        else
            local bottom = y + (h or 16) - sf:GetHeight()
            if bottom > offset then
                sf:SetVerticalScroll(bottom)
            end
        end
    end)

    return sf, eb
end

--------------------------------------------------------------------------------
-- PLACEHOLDER EDITBOX
-- pcall(SetTextColor) throughout — safe on all clients, no GetFontString().
--------------------------------------------------------------------------------
function BNB.AddPlaceholder(eb, text, r, g, b)
    r, g, b = r or 0.45, g or 0.45, b or 0.45

    local function setColor(self, cr, cg, cb)
        pcall(function() self:SetTextColor(cr, cg, cb) end)
    end

    local function showPlaceholder()
        if eb:GetText() == "" and not eb:HasFocus() then
            eb:SetText(text)
            setColor(eb, r, g, b)
            eb._showingPlaceholder = true
        end
    end

    -- The typed text's colour: white unless set with eb:SetRealColor
    -- (the editor title takes the note's title colour, ALL-260)
    local function realColor(self)
        local c = self._realColor
        if c then setColor(self, c.r, c.g, c.b) else setColor(self, BNB.TextWhite()) end   -- ALL-402 S2
    end

    local function hidePlaceholder()
        if eb._showingPlaceholder then
            eb:SetText("")
            realColor(eb)
            eb._showingPlaceholder = false
        end
    end

    eb:SetScript("OnEditFocusGained", function() hidePlaceholder() end)
    eb:SetScript("OnEditFocusLost",   function() showPlaceholder() end)

    if eb:GetText() == "" then showPlaceholder() end

    eb.GetRealText = function(self)
        if self._showingPlaceholder then return "" end
        return self:GetText()
    end
    eb.SetRealText = function(self, t)
        hidePlaceholder()
        self:SetText(t or "")
        realColor(self)
        if not t or t == "" then showPlaceholder() end
    end
    -- c = { r, g, b } or nil (white); the placeholder keeps its own grey
    eb.SetRealColor = function(self, c)
        self._realColor = c
        if not self._showingPlaceholder then realColor(self) end
    end
end

--------------------------------------------------------------------------------
-- DIVIDER LINE
-- In skin mode: ignores caller r/g/b and uses the preset border colour instead,
-- then registers the texture for live recolouring on preset/brightness change.
-- The caller's alpha value is preserved as the registration alpha.
--------------------------------------------------------------------------------
function BNB.CreateDivider(parent, orientation, r, g, b, a)
    local t = parent:CreateTexture(nil, "ARTWORK")
    local alpha = a or 1
    if BigNoteBoxDB and BigNoteBoxDB.skinMode
       and BNB.GetSkinPreset and BNB.SkinRuleOf and BNB.RegisterSkinRule then
        local p = BNB.GetSkinPreset()
        local br, bg_, bb = BNB.SkinRuleOf(p)
        t:SetColorTexture(br, bg_, bb, alpha)
        BNB.RegisterSkinRule(t, alpha)
    else
        t:SetColorTexture(r or 0.25, g or 0.25, b or 0.25, alpha)
    end
    if orientation == "VERTICAL" then t:SetWidth(1)
    else t:SetHeight(1) end
    return t
end

-- The one horizontal rule of the note list and the note editor (Dukul,
-- 2026-10-04: the editor's lines were four colours and sizes): the grey of the
-- pinned / regular divider, in both looks, one screen pixel tall at any UI
-- scale (a 1-unit line drew 1 or 2 px depending on where it landed). Pixel
-- snapping is off: snapped, a 1px line half a pixel off the grid had both edges
-- rounded onto the same row and vanished (the pinned divider in the scrolled
-- note list, 2026-10-04); unsnapped, it always fills exactly one row. The
-- caller anchors it. Skin mode: the preset's border tint at the same alpha,
-- following preset changes (ALL-262, Dukul 2026-10-05: "The dividers in skin
-- mode should all be tinted, not grey."). Focus mode uses it too.
BNB.NOTE_RULE_RGBA = { 0.35, 0.35, 0.38, 0.7 }

--------------------------------------------------------------------------------
-- WHITE UI ICONS  (Dukul, 2026-10-08: all new icon art is white)
-- A bare icon with no button border: gold in normal mode (the formatting
-- toolbar's gold), the skin preset's accent in skin mode (follows preset
-- changes through RegisterSkinAccentTex). One hover glow for every place,
-- Assets/UI/ui-hover-64 (top bar, formatting toolbar, note list), tinted the
-- same as the icon.
--------------------------------------------------------------------------------
BNB.ICON_GOLD    = { 1, 0.86, 0.2 }
BNB.UI_HOVER_TEX = "Interface\\AddOns\\BigNoteBox\\Assets\\UI\\ui-hover-64"

function BNB.TintUIIcon(tx, shade)
    local k = shade or 1
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.RegisterSkinAccentTex then
        BNB.RegisterSkinAccentTex(tx, k)
    else
        local g = BNB.ICON_GOLD
        tx:SetVertexColor(g[1] * k, g[2] * k, g[3] * k)
    end
end

-- The hover glow over `tx` (default: the whole button), shown by the client
-- while the pointer is over `btn` (HIGHLIGHT layer).
function BNB.AddUIIconHover(btn, tx)
    local hi = btn:CreateTexture(nil, "HIGHLIGHT")
    hi:SetAllPoints(tx or btn)
    hi:SetTexture(BNB.UI_HOVER_TEX)
    BNB.TintUIIcon(hi)
    return hi
end
--------------------------------------------------------------------------------
-- CHECKBOX LABEL HIT  (Dukul, 2026-10-07: the tooltip shows over the text too,
-- everywhere)
-- Stretches a checkbox's hit area over its label, so hovering the text shows
-- the checkbox's tooltip and clicking it ticks the box. lbl nil = found on
-- show: the template's own text, else a FontString in the parent anchored to
-- the checkbox. Re-measured on every show (text can change), only over the
-- visible text, never past the label's own width.
--------------------------------------------------------------------------------
local function HasText(fs)
    return fs and fs.GetText and (fs:GetText() or "") ~= ""
end
local function FindCheckLabel(cb)
    for _, fs in ipairs({ cb.text, cb.Text }) do
        if HasText(fs) then return fs end
    end
    -- An empty FontString is never the label: the template's own Text is
    -- anchored to the checkbox too, and taking it (no width) left the hit
    -- area on the box alone (Settings > Modules > Toasts, 2026-10-08)
    local parent = cb:GetParent()
    for _, holder in ipairs({ cb, parent }) do
        for _, r in ipairs({ holder:GetRegions() }) do
            if r:GetObjectType() == "FontString" and HasText(r) then
                for i = 1, r:GetNumPoints() do
                    local _, rel = r:GetPoint(i)
                    if rel == cb then return r end
                end
            end
        end
    end
end

local function FitCheckHit(cb)
    local lbl = cb._hitLbl
    if not HasText(lbl) then lbl = FindCheckLabel(cb) end
    cb._hitLbl = lbl
    if lbl and BNB.UseLabelFont then BNB.UseLabelFont(lbl) end
    if not (lbl and lbl:IsShown()) then cb:SetHitRectInsets(0, 0, 0, 0); return end
    local w = lbl:GetStringWidth() or 0
    local lw = lbl:GetWidth() or 0
    if lw > 0 and lw < w then w = lw end
    local gap = (lbl:GetLeft() and cb:GetRight()) and (lbl:GetLeft() - cb:GetRight()) or 4
    if w <= 0 then return end
    local scale = cb:GetEffectiveScale() / lbl:GetEffectiveScale()
    cb:SetHitRectInsets(0, -math.floor((gap + w) / scale + 0.5), 0, 0)
end

--------------------------------------------------------------------------------
-- SKIN CHECKBOXES  (ALL-405, Dukul's art 2026-10-08; skin mode only, normal
-- mode keeps the game's checkbox; the ui-cb-box / -mark / -mark-hover normal
-- set is shipped but unused for now). Every checkbox that goes through
-- BNB.LabelHit is drawn with Assets/UI/ui-cb-skin-* (64x64 canvases):
-- ui-cb-skin-bg in the skin button colour (only while ticked, faint), ui-cb-skin-box in the preset border
-- colour (capped, never white), ui-cb-skin-check and -check-hover in the accent. Everything rides on
-- the button's native textures (Normal / Pushed / Disabled = box, Checked /
-- DisabledChecked = tick, Highlight = hover tick), so a SetScript after this
-- (CheckTip sets OnEnter) cannot break it and the hover covers the label too
-- (LabelHit's hit rect). A preset change repaints (RegisterSkinButton).
--------------------------------------------------------------------------------
local CB_DIR   = "Interface\\AddOns\\BigNoteBox\\Assets\\UI\\ui-cb-"
local CB_SCALE = 0.75   -- canvas size / checkbox size: the box comes out about
                        -- as big as the game's box art was

local function PaintCheck(cb)
    if not cb._cbSkin then return end
    local p = BNB.GetSkinPreset and BNB.GetSkinPreset()
    if not p then return end
    local on = cb:IsEnabled()
    local dim = on and 1 or 0.5
    local r, g, b = BNB.SkinButtonOf(p)
    -- The background only behind a tick, and faint, so the tick stands out
    -- against it (Dukul, 2026-10-08)
    -- Darkened rather than faded: a dark fill behind the tick (Dukul, 2026-10-08)
    local d = 0.4
    cb._cbBg:SetVertexColor(r * d, g * d, b * d, on and 0.6 or 0.3)
    cb._cbBg:SetShown(cb:GetChecked() and true or false)
    local br, bg_, bb = BNB.SkinBorderOf(p)
    local k = math.min(1, 1 / math.max(br, bg_, bb, 0.001)) * dim
    for _, t in ipairs({ cb:GetNormalTexture(), cb:GetPushedTexture(), cb:GetDisabledTexture() }) do
        if t then t:SetVertexColor(br * k, bg_ * k, bb * k) end
    end
    local ar, ag, ab = BNB.SkinAccentOf(p)
    local ct, hl = cb:GetCheckedTexture(), cb:GetHighlightTexture()
    if ct then ct:SetVertexColor(ar, ag, ab) end
    if hl then hl:SetVertexColor(ar, ag, ab) end
end

-- artSize = the drawn size in the checkbox's own units (nil = CB_SCALE x its
-- width); the sticky task boxes pass it to match the Reference Box tasks
function BNB.SkinCheckbox(cb, artSize)
    if not cb or cb._cbStyled then return end
    if not (BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset) then return end
    if not (cb.IsObjectType and cb:IsObjectType("CheckButton")) then return end
    cb._cbStyled = true
    cb._cbSkin = true
    local w = cb:GetWidth()
    if not w or w < 8 then w = 24 end
    local sz = artSize or math.floor(w * CB_SCALE + 0.5)
    local function Place(t, layer, sub)
        if not t then return end
        t:ClearAllPoints()
        t:SetPoint("CENTER", cb, "CENTER", 0, 0)
        t:SetSize(sz, sz)
        t:SetTexCoord(0, 1, 0, 1)
        t:SetDrawLayer(layer, sub)
        t:SetAlpha(1)
    end
    local box, mark, hover = CB_DIR .. "skin-box", CB_DIR .. "skin-check", CB_DIR .. "skin-check-hover"
    local bg = cb:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(CB_DIR .. "skin-bg")
    Place(bg, "BACKGROUND", 0)
    cb._cbBg = bg
    cb:SetNormalTexture(box)
    cb:SetPushedTexture(box)
    cb:SetDisabledTexture(box)
    cb:SetCheckedTexture(mark)
    cb:SetDisabledCheckedTexture(mark)
    cb:SetHighlightTexture(hover, "BLEND")
    Place(cb:GetNormalTexture(),   "BORDER", 0)
    Place(cb:GetPushedTexture(),   "BORDER", 0)
    Place(cb:GetDisabledTexture(), "BORDER", 0)
    Place(cb:GetCheckedTexture(),  "ARTWORK", 1)
    Place(cb:GetDisabledCheckedTexture(), "ARTWORK", 1)
    Place(cb:GetHighlightTexture(), "HIGHLIGHT", 0)
    -- Disabled tick: grey (the box dims in PaintCheck)
    local dct = cb:GetDisabledCheckedTexture()
    if dct then dct:SetDesaturated(true); dct:SetVertexColor(0.5, 0.5, 0.5) end
    local function Paint() PaintCheck(cb) end
    Paint()
    -- Method hooks survive a later SetScript; OnShow catches a preset change
    -- made while it was hidden (RegisterSkinButton skips hidden owners)
    hooksecurefunc(cb, "SetEnabled", Paint)
    hooksecurefunc(cb, "Enable", Paint)
    hooksecurefunc(cb, "Disable", Paint)
    cb:HookScript("OnShow", Paint)
    -- The checked state: SetChecked from code, PostClick for a click (sites
    -- SetScript their OnClick after LabelHit, which would drop an OnClick hook)
    hooksecurefunc(cb, "SetChecked", Paint)
    cb:HookScript("PostClick", Paint)
    if BNB.RegisterSkinButton then BNB.RegisterSkinButton(Paint, cb) end
end

-- A checkbox's tooltip (ALL-373): one wrapped grey line, as Settings' AddCheck
-- draws it. text may be a function (read on every hover). Call LabelHit too, so
-- the tooltip shows over the label.
function BNB.CheckTip(cb, text)
    cb:SetScript("OnEnter", function(self)
        local t = type(text) == "function" and text() or text
        if not t or t == "" then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(t, 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function BNB.LabelHit(cb, lbl)
    if not cb then return end
    if cb._labelHit then   -- a pooled row with new text: measure again
        if lbl then cb._hitLbl = lbl; BNB.UseLabelFont(lbl) end
        C_Timer.After(0, function() if cb:IsShown() then FitCheckHit(cb) end end)
        return
    end
    cb._labelHit = true
    cb._hitLbl = lbl
    BNB.SkinCheckbox(cb)
    -- Checkbox labels are white in both modes, only headings take the accent
    -- (ALL-402 S2); a label coloured by hand keeps its colour
    BNB.UseLabelFont(cb.Text)
    BNB.UseLabelFont(lbl)
    cb:HookScript("OnShow", function(self)
        FitCheckHit(self)
        -- Anchored labels have no size until the next frame
        C_Timer.After(0, function() if self:IsShown() then FitCheckHit(self) end end)
    end)
    if cb:IsVisible() then C_Timer.After(0, function() FitCheckHit(cb) end) end
end

--------------------------------------------------------------------------------
-- ICON MARKERS  (Dukul, 2026-10-08)
-- The small markers on a note icon (alarm, favourite, situation). Normal mode,
-- every client: three layers on one 64x64 canvas, as the icon buttons are:
-- Overlay/Layers/ov-bottom, Overlay/Symbols/ov-<symbol>, Overlay/Layers/ov-top.
-- Skin mode keeps the single Overlay/ov-<symbol> picture, drawn white and tinted
-- to the preset border x 2.2 as the skin icon buttons' symbols are (Dukul,
-- 2026-10-08); a preset change re-tints through SkinChanged. Returns something
-- that takes SetSize / SetPoint / ClearAllPoints / Show / Hide / SetShown, plus
-- SetMuted(on) = greyed (a fired alarm). Decided once, when built (skin mode
-- changes reload).
--------------------------------------------------------------------------------
local OVERLAY_DIR = "Interface\\AddOns\\BigNoteBox\\Assets\\Overlay\\"
local MARKER_TINT = 2.2
local _skinMarkers = setmetatable({}, { __mode = "k" })

local function TintMarker(t)
    local br, bg_, bb = 1, 1, 1
    if BNB.GetSkinPreset and BNB.SkinBorderOf then br, bg_, bb = BNB.SkinBorderOf(BNB.GetSkinPreset()) end
    -- One factor for all three channels, capped where the brightest one hits
    -- 1: clamping each channel on its own turned a bright preset white
    -- (skin brightness 3.00, Dukul 2026-10-08)
    local hi = math.max(br, bg_, bb, 0.001)
    local m = math.min(MARKER_TINT, 1 / hi) * (t._muted and 0.5 or 1)
    t:SetVertexColor(br * m, bg_ * m, bb * m)
end

function BNB.CreateIconMarker(host, symbol)
    if BigNoteBoxDB and BigNoteBoxDB.skinMode then
        local t = host:CreateTexture(nil, "OVERLAY", nil, 1)
        t:SetTexture(OVERLAY_DIR .. "ov-" .. symbol)
        function t:SetMuted(on) self._muted = on or nil; TintMarker(self) end
        _skinMarkers[t] = true
        TintMarker(t)
        t:Hide()
        if not _skinMarkers._msg and BNB.RegisterMessage then
            _skinMarkers._msg = true
            BNB.RegisterMessage("Widgets.IconMarkers", "SkinChanged", function()
                for k in pairs(_skinMarkers) do if type(k) == "table" then TintMarker(k) end end
            end)
        end
        return t
    end
    local m = CreateFrame("Frame", nil, host)
    m:SetFrameLevel(host:GetFrameLevel() + 1)
    m:EnableMouse(false)
    local parts = {}
    for i, path in ipairs({ OVERLAY_DIR .. "Layers\\ov-bottom",
                            OVERLAY_DIR .. "Symbols\\ov-" .. symbol,
                            OVERLAY_DIR .. "Layers\\ov-top" }) do
        local t = m:CreateTexture(nil, "OVERLAY", nil, i)
        t:SetAllPoints()
        t:SetTexture(path)
        parts[i] = t
    end
    function m:SetMuted(on)
        local c = on and 0.5 or 1
        for _, t in ipairs(parts) do t:SetDesaturated(on and true or false); t:SetVertexColor(c, c, c) end
    end
    m:Hide()
    return m
end

-- The owning character's class icon (bottom-left): normal mode draws it round
-- in ov-top's hole, under the ring, so it matches the other markers; skin mode
-- keeps the plain square texture. Its picture is set with SetTexture as before.
-- The hole is x 12-51, y 9-48 of the 64 px canvas (measured, 2026-10-08).
local HOLE_L, HOLE_T, HOLE_W = 12 / 64, 9 / 64, 40 / 64
function BNB.CreateClassMarker(host)
    if BigNoteBoxDB and BigNoteBoxDB.skinMode then
        local t = host:CreateTexture(nil, "OVERLAY", nil, 1)
        t:SetTexCoord(0, 1, 0, 1)
        t:Hide()
        return t
    end
    local m = CreateFrame("Frame", nil, host)
    m:SetFrameLevel(host:GetFrameLevel() + 1)
    m:EnableMouse(false)
    local icon = m:CreateTexture(nil, "OVERLAY", nil, 1)
    local mask = m:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask",
        "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(icon)
    icon:AddMaskTexture(mask)
    local top = m:CreateTexture(nil, "OVERLAY", nil, 3)
    top:SetAllPoints()
    top:SetTexture(OVERLAY_DIR .. "Layers\\ov-top")
    local function Place(self, w)
        w = w or self:GetWidth()
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", self, "TOPLEFT", w * HOLE_L, -w * HOLE_T)
        icon:SetSize(w * HOLE_W, w * HOLE_W)
    end
    m:SetScript("OnSizeChanged", Place)
    m:SetScript("OnShow", function(self) Place(self) end)   -- sized while hidden
    function m:SetTexture(path) icon:SetTexture(path) end
    function m:SetTexCoord(...) icon:SetTexCoord(...) end
    function m:SetVertexColor(r, g, b, a) icon:SetVertexColor(r, g, b, a) end
    m:Hide()
    return m
end

function BNB.CreateNoteRule(parent)
    local t = parent:CreateTexture(nil, "ARTWORK")
    local c = BNB.NOTE_RULE_RGBA
    if BigNoteBoxDB and BigNoteBoxDB.skinMode
       and BNB.GetSkinPreset and BNB.SkinRuleOf and BNB.RegisterSkinRule then
        local br, bg_, bb = BNB.SkinRuleOf(BNB.GetSkinPreset())
        t:SetColorTexture(br, bg_, bb, c[4])
        BNB.RegisterSkinRule(t, c[4])
    else
        t:SetColorTexture(c[1], c[2], c[3], c[4])
    end
    if t.SetSnapToPixelGrid then
        t:SetSnapToPixelGrid(false)
        t:SetTexelSnappingBias(0)
    end
    if PixelUtil and PixelUtil.SetHeight then
        PixelUtil.SetHeight(t, 1, 1)
    else
        t:SetHeight(1)
    end
    return t
end

-- Selection cards (ALL-404): the bundled-font cards in Settings > Appearance,
-- the New note dialog and the setup wizard, and the wizard's other picks
-- (usage, picture choices, list mode), one look for all. state = "sel"
-- | "hover" | nil. Normal mode keeps the green selection; skin mode takes the
-- preset: body fill + rule border, lifted fill + accent border when selected,
-- a dimmer accent border on hover. nameLbl (optional) = accent when selected,
-- white otherwise; hover leaves it alone. Callers re-paint on SkinChanged.
function BNB.PaintSelectCard(btn, state, nameLbl)
    if not (btn and btn.SetBackdropColor) then return end
    if BigNoteBoxDB and BigNoteBoxDB.skinMode then
        local p = BNB.GetSkinPreset()
        local fr, fg, fb = BNB.SkinColourOf(p, state == "sel")
        btn:SetBackdropColor(fr, fg, fb, 0.95)
        if state == "sel" then
            btn:SetBackdropBorderColor(BNB.SkinAccentOf(p))
        elseif state == "hover" then
            btn:SetBackdropBorderColor(BNB.SkinAccentOf(p, 1.3))
        else
            local r, g, b = BNB.SkinRuleOf(p)
            btn:SetBackdropBorderColor(r, g, b, 1)
        end
    elseif state == "sel" then
        btn:SetBackdropColor(0.12, 0.18, 0.12, 0.95)
        btn:SetBackdropBorderColor(0.4, 0.8, 0.4, 1)
    elseif state == "hover" then
        btn:SetBackdropColor(0.10, 0.12, 0.10, 0.95)
        btn:SetBackdropBorderColor(0.35, 0.55, 0.35, 1)
    else
        btn:SetBackdropColor(0.06, 0.06, 0.08, 0.95)
        btn:SetBackdropBorderColor(0.28, 0.28, 0.30, 1)
    end
    if nameLbl and state ~= "hover" then
        if state == "sel" then BNB.SetHeaderColor(nameLbl) else BNB.SetTextWhite(nameLbl, 0.85) end
    end
end

-- List window rows (Trash, Note History, Alarms): hover, selection and Select
-- mode backgrounds. Normal mode = Dukul's greyscale ui-window-* art stretched
-- over the whole row and tinted the BNB green, as the note list's row art
-- (2026-10-07); skin mode = the flat `fill` colour. kind = "hover" |
-- "selection" | "multi-selection"; drawn on BACKGROUND (sublevel 1 / 2 / 3),
-- under the icon and text. Built hidden. Skin mode is read at build time: a
-- switch reloads the UI.
local ROW_ART_PATH = "Interface\\AddOns\\BigNoteBox\\Assets\\UI\\ui-window-"
local ROW_ART_SUB  = { selection = 1, ["multi-selection"] = 2, hover = 3 }
function BNB.CreateListRowArt(row, kind, fill)
    local tex = row:CreateTexture(nil, "BACKGROUND", nil, ROW_ART_SUB[kind] or 1)
    tex:SetAllPoints()
    if BigNoteBoxDB and BigNoteBoxDB.skinMode then
        tex:SetColorTexture(fill[1], fill[2], fill[3], fill[4])
    else
        tex:SetTexture(ROW_ART_PATH .. kind)
        tex:SetVertexColor(0.40, 0.85, 0.40)   -- NoteList COL_SEL_BG
    end
    tex:Hide()
    return tex
end

--------------------------------------------------------------------------------
-- TOP TAB ROW FIT  (ALL-229, ALL-170)
-- Normal-mode PanelTopTabButtonTemplate tabs, kept inside the host: the row
-- starts `side` in from the left edge and ends `side` in from the right. Too
-- wide: take the side padding off every tab a pixel at a time, then share the
-- width equally (long labels truncate). Classic's tab font is wider, and its
-- template sizes the tabs again when they show, so the fit is re-applied on the
-- host's show and after every tab click (one frame later, after the template).
--------------------------------------------------------------------------------
function BNB.FitTabRow(host, tabs, side, gap)
    if not (host and tabs and tabs[1]) then return end
    local function Fit()
        local w = host:GetWidth()
        if not w or w <= 0 then return end
        local free = w - 2 * side - (#tabs - 1) * gap
        local function RowW()
            local t = 0
            for _, b in ipairs(tabs) do t = t + b:GetWidth() end
            return t
        end
        for _, b in ipairs(tabs) do PanelTemplates_TabResize(b, 15, nil, 70) end
        if RowW() <= free then return end
        for pad = 14, 0, -1 do
            for _, b in ipairs(tabs) do PanelTemplates_TabResize(b, pad) end
            if RowW() <= free then return end
        end
        local share = math.floor(free / #tabs)
        for _, b in ipairs(tabs) do PanelTemplates_TabResize(b, 0, share) end
    end
    local function SafeFit() pcall(Fit) end
    local function Later() C_Timer.After(0, SafeFit) end
    SafeFit()
    host:HookScript("OnShow", function() SafeFit(); Later() end)
    for _, b in ipairs(tabs) do b:HookScript("OnClick", Later) end
end

--------------------------------------------------------------------------------
-- SETTINGS-PANEL PIECES  (ALL-65.8)
-- Shared by AlarmWindow, TaskEditWindow, NoteConfig, StickyNote and
-- ConfigWindow, which each had their own copy.
--------------------------------------------------------------------------------

-- Section rule: 1px line y pixels below the top of parent, width wide, or
-- spanning the parent when width is nil. Skin mode: preset border at 0.9 alpha.
function BNB.CreateRule(parent, y, width)
    local t
    if BigNoteBoxDB and BigNoteBoxDB.skinMode then
        t = BNB.CreateDivider(parent, "HORIZONTAL", nil, nil, nil, 0.9)
    else
        t = BNB.CreateDivider(parent, "HORIZONTAL", 0.25, 0.25, 0.28, 1)
    end
    t:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    if width then t:SetWidth(width)
    else t:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y) end
    return t
end

-- Yellow section header
function BNB.CreateSectionHeader(parent, text, y, width)
    local l = parent:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    l:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    l:SetWidth(width); l:SetJustifyH("LEFT")
    l:SetText(text)
    BNB.SetHeaderColor(l)
    return l
end

-- Small grey label
function BNB.CreateSmallLabel(parent, text, y, width)
    local l = parent:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    l:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    l:SetWidth(width); l:SetJustifyH("LEFT")
    l:SetText(text); l:SetTextColor(0.68, 0.68, 0.68, 1)
    return l
end

-- Compact value dropdown on WowStyle1DropdownTemplate (every client has it, so
-- there is no cycle-button fallback any more, DEP-05).
-- entries = { { label = "...", value = v }, ... }
-- onDirty() fires on every user pick, before onChange(value).
-- Returns a container with :SetSelected(v) / :GetSelected(); ._dd is the
-- DropdownButton.
function BNB.CreateValueDropdown(parent, entries, initial, onChange, width, height, onDirty)
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(width, height)

    local dd = BNB.SkinDropdown(CreateFrame("DropdownButton", nil, c, "WowStyle1DropdownTemplate"))
    dd:SetToplevel(true); dd:SetWidth(width); dd:SetHeight(height)
    dd:SetPoint("TOPLEFT")
    dd._selected = initial
    dd:SetupMenu(function(_, root)
        for _, e in ipairs(entries) do
            local ev = e.value
            root:CreateRadio(e.label,
                function() return dd._selected == ev end,
                function()
                    dd._selected = ev; dd:SetText(e.label)
                    if onDirty then onDirty() end
                    if onChange then onChange(ev) end
                end)
        end
        -- Long lists (LibSharedMedia media, ALL-69.5) scroll.
        if #entries > 20 then root:SetScrollMode(20 * 20) end
    end)
    for _, e in ipairs(entries) do
        if e.value == initial then dd:SetText(e.label); break end
    end
    function c:SetSelected(v)
        dd._selected = v
        for _, e in ipairs(entries) do
            if e.value == v then dd:SetText(e.label); return end
        end
        dd:SetText("")
    end
    function c:GetSelected() return dd._selected end
    c._dd = dd
    return c
end

-- Number field with a value list: a value dropdown whose text part is a
-- typeable box (alarm hour/minute, ALL-136.3). Type a number, pick it from the
-- arrow's list (every value from lo to hi), or turn the mouse wheel while the
-- box has focus (wraps). Leaving the box clamps and pads the value to two
-- digits; GetValue() reads the box as typed, so nothing needs confirming.
-- opts: { onDirty, onTab(shift), onEnter } -- onTab moves focus, ":" counts as Tab;
-- Enter always just leaves the box, onEnter runs after that.
-- Sizes (ALL-261): opts.values = the list's entries instead of lo..hi (any
-- value in range can still be typed), opts.fmt = how a value shows (default
-- "%02d"), opts.digits = how many digits can be typed (default 2).
-- Returns a container with :GetValue() / :SetValue(n) / :SetRange(lo, hi) /
-- :SetFieldWidth(w) / :SetEnabled(on) and .eb (the EditBox).
function BNB.CreateNumberCombo(parent, lo, hi, initial, width, height, opts)
    opts = opts or {}
    local FMT    = opts.fmt or "%02d"
    local DIGITS = opts.digits or 2
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(width, height)

    local dd = BNB.SkinDropdown(CreateFrame("DropdownButton", nil, c, "WowStyle1DropdownTemplate"))
    dd:SetToplevel(true); dd:SetSize(width, height); dd:SetPoint("TOPLEFT")
    -- The box shows the value; the template's own label stays empty
    if dd.Text then dd.Text:SetAlpha(0) end
    local eb = CreateFrame("EditBox", nil, dd)
    eb:SetPoint("TOPLEFT", dd, "TOPLEFT", 4, 0)
    eb:SetPoint("BOTTOMRIGHT", dd, "BOTTOMRIGHT", -22, 0)  -- leave the arrow clickable
    eb:SetFrameLevel(dd:GetFrameLevel() + 2)
    eb:SetAutoFocus(false); eb:SetMaxLetters(DIGITS + 1)
    eb:SetFontObject("BNBFontHighlightSmall"); eb:SetJustifyH("CENTER")
    eb:SetTextInsets(6, 6, 0, 0)

    local function Clamp(n)
        n = math.floor(tonumber(n) or lo)
        if n < lo then n = lo elseif n > hi then n = hi end
        return n
    end
    function c:SetValue(n)
        n = Clamp(n)
        eb:SetText(string.format(FMT, n))
        dd._selected = n
    end
    function c:GetValue()
        local t = eb:GetText():gsub("%D", "")
        if t == "" then return dd._selected or lo end
        return Clamp(t)
    end
    c.eb = eb
    -- Range and width can change after creation (12/24-hour clock)
    function c:SetRange(a, b) lo, hi = a, b; c:SetValue(c:GetValue()) end
    function c:SetFieldWidth(w)
        c:SetWidth(w)
        dd:SetWidth(w)
    end
    -- Greyed and untouchable while off (Insert image height under Keep ratio)
    function c:SetEnabled(on)
        on = on and true or false
        if not on then eb:ClearFocus() end
        eb:EnableMouse(on)
        dd:SetEnabled(on)
        c:SetAlpha(on and 1 or 0.45)
    end

    -- Digits only, DIGITS at most; ":" or "." jumps to the next field like Tab
    local function DigitsOnly(self)
        local t = self:GetText()
        local digits = t:gsub("%D", ""):sub(1, DIGITS)
        if digits ~= t then self:SetText(digits) end
    end
    eb:SetScript("OnChar", function(self, ch)
        if ch == ":" or ch == "." then
            DigitsOnly(self)
            if opts.onTab then opts.onTab(false) end
        end
    end)
    eb:SetScript("OnTextChanged", function(self, user)
        if not user then return end
        DigitsOnly(self)
        if opts.onDirty then opts.onDirty() end
    end)
    eb:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
        self:EnableMouseWheel(true)
    end)
    eb:SetScript("OnEditFocusLost", function(self)
        self:HighlightText(0, 0)
        -- The wheel only steps while typing; otherwise it scrolls the page
        self:EnableMouseWheel(false)
        c:SetValue(c:GetValue())
    end)
    eb:SetScript("OnTabPressed", function()
        if opts.onTab then opts.onTab(IsShiftKeyDown()) end
    end)
    eb:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if opts.onEnter then opts.onEnter() end
    end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnMouseWheel", function(_, delta)
        local n = c:GetValue() + (delta > 0 and 1 or -1)
        if n > hi then n = lo elseif n < lo then n = hi end
        c:SetValue(n)
        if opts.onDirty then opts.onDirty() end
    end)
    eb:EnableMouseWheel(false)

    dd:SetupMenu(function(_, root)
        local cur = c:GetValue()
        local list = opts.values
        if not list then
            list = {}
            for n = lo, hi do list[#list + 1] = n end
        end
        for _, n in ipairs(list) do
            root:CreateRadio(string.format(FMT, n),
                function() return cur == n end,
                function()
                    c:SetValue(n)
                    if opts.onDirty then opts.onDirty() end
                end)
        end
        if #list > 20 then root:SetScrollMode(20 * 20) end
    end)

    c:SetValue(initial or lo)
    return c
end

-- Tab / Shift+Tab steps through the edit boxes in list order, wrapping at both
-- ends, and selects the text it lands in (dialog fields, ALL-255).
function BNB.TabChain(boxes)
    for i, eb in ipairs(boxes) do
        eb:SetScript("OnTabPressed", function()
            local n = #boxes
            local nxt = boxes[IsShiftKeyDown() and ((i - 2) % n + 1) or (i % n + 1)]
            nxt:SetFocus()
            nxt:HighlightText()
        end)
    end
end

-- The highlighted text in an edit box, or nil, leaving the box as it was. The
-- game has no getter: Insert("") deletes the selection, so the text is put
-- back and highlighted again. Programmatic Insert is not user input, so the
-- note is not marked edited. Used by the link dialog (ALL-253). singleLine: a
-- selection over more than one line is not returned and its highlight is
-- collapsed (cursor after it), so a following Insert does not replace it.
function BNB.PeekSelection(eb, singleLine)
    if not eb then return nil end
    eb:SetFocus()
    local before = eb:GetText() or ""
    eb:Insert("")
    local after = eb:GetText() or ""
    if #after >= #before then return nil end
    local start = eb:GetCursorPosition() or 0
    local sel = before:sub(start + 1, start + (#before - #after))
    eb:Insert(sel)
    if singleLine and sel:find("\n", 1, true) then
        eb:SetCursorPosition(start + #sel)
        return nil
    end
    eb:HighlightText(start, start + #sel)
    return sel
end

-- Scroll panel whose bar stays invisible (alpha, never Hide) until the
-- content outgrows it. While it fits, the content frame widens to cwNoBar
-- and takes the bar's space. The caller anchors sf (leave 24px on the right
-- for the bar) and reports the content height with sf:FinaliseHeight(h), or
-- by setting ct._contentH before the panel is shown.
-- Returns: scrollFrame, contentFrame
function BNB.CreateAutoScrollPanel(parent, cw, cwNoBar)
    local sf  = BNB.CreateScrollFrame(nil, parent)
    local bar = sf.ScrollBar
    if bar then bar:SetAlpha(0) end

    local ct = CreateFrame("Frame", nil, sf)
    ct:SetWidth(cw); ct:SetHeight(1)
    sf:SetScrollChild(ct)

    local function ApplyScrollbar()
        local sfH = sf:GetHeight()
        -- GetHeight() returns 0 before the frame is laid out; skip until ready
        if sfH < 4 then return end
        local ctH = ct._contentH or 1
        ct:SetHeight(math.max(ctH, sfH))
        if ctH <= sfH + 2 then
            if bar then bar:SetAlpha(0) end
            ct:SetWidth(cwNoBar)
        else
            if bar then bar:SetAlpha(1) end
            ct:SetWidth(cw)
        end
    end
    -- Re-evaluate on resize, and when shown (first open, tab switch)
    sf:SetScript("OnSizeChanged", function() ApplyScrollbar() end)
    sf:HookScript("OnShow", function() C_Timer.After(0.05, ApplyScrollbar) end)
    sf._applyScrollbar = ApplyScrollbar

    function sf:FinaliseHeight(contentH)
        ct._contentH = contentH
        -- Defer one frame so the scroll frame has been laid out and GetHeight() is valid
        C_Timer.After(0.05, ApplyScrollbar)
    end

    return sf, ct
end

-- Blizzard colour picker. onDone(r, g, b) fires on every change (swatchFunc
-- runs while dragging, not just on OK); onCancel is optional.
-- a: optional opacity (0-1); given, the picker shows its opacity slider and
-- onDone gets (r, g, b, a).
function BNB.OpenColorPicker(r, g, b, onDone, onCancel, a)
    local withAlpha = a ~= nil
    local function Swatch()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        if withAlpha then onDone(nr, ng, nb, ColorPickerFrame:GetColorAlpha())
        else onDone(nr, ng, nb) end
    end
    local function Cancel() if onCancel then onCancel() end end
    ColorPickerFrame:SetupColorPickerAndShow({
        swatchFunc = Swatch, cancelFunc = Cancel,
        opacityFunc = withAlpha and Swatch or nil,
        hasOpacity = withAlpha, opacity = withAlpha and a or nil,
        r = r, g = g, b = b,
    })
end

--------------------------------------------------------------------------------
-- SLIDERS: every slider is BNB.CreateStackedSlider (below), on
-- MinimalSliderWithSteppersTemplate. Its no-template fallbacks CreateSlider /
-- CreateFloatSlider went with DEP-05 (every client has the template).
--------------------------------------------------------------------------------
-- No mouse wheel on a slider: the wheel scrolls the page (Dukul 2026-09-28).
-- MinimalSliderWithSteppersTemplate takes the wheel itself (inner Slider and
-- the stepper arrows), so leaving out our own OnMouseWheel is not enough.
-- With the wheel off, the event falls through to the scroll frame below.
local function NoSliderWheel(frame)
    pcall(frame.EnableMouseWheel, frame, false)
    if frame.HasScript and frame:HasScript("OnMouseWheel") then
        pcall(frame.SetScript, frame, "OnMouseWheel", nil)
    end
    for _, child in ipairs({ frame:GetChildren() }) do NoSliderWheel(child) end
end

--------------------------------------------------------------------------------
-- STACKED SLIDER  (sticky settings' layout, with Reset; Dukul 2026-09-28)
--
--   Label (Default: 100%)                      80%
--   <-----------------|----------------->  [ Reset ]
--
-- o = { label, min, max, value, default, fmt = fn(v) -> text, onChange(v),
--       step, tip, tipTitle, onReset }
-- step: nil/1 = whole numbers; a fraction (0.05) snaps to it (ALL-121).
-- Reset puts the default back (through onChange) and is greyed while the
-- value is already the default. onReset: Reset moves the slider silently and
-- calls it instead, for a setting whose default is "no saved value" (a note's
-- font size). tip: a string or a list of grey lines, tipTitle a white first
-- line, shown over the label row. Returns the container, BNB.STACKED_SLIDER_H
-- tall: :SetValue(v, silent) (fires onChange unless silent), :GetValue(),
-- :SetEnabled(on). The inner slider is ._slider, not .Slider, so greying
-- code that looks for .Slider calls the container's SetEnabled instead.
-- Every slider in the addon is one of these (ALL-121).
--------------------------------------------------------------------------------
BNB.STACKED_SLIDER_H = 40
function BNB.CreateStackedSlider(parent, width, o)
    local step = o.step or 1
    local fmt = o.fmt or (step < 1
        and function(v) return string.format(step < 0.01 and "%.3f" or "%.2f", v) end
        or  function(v) return tostring(v) end)
    local function Snap(v)
        v = math.max(o.min, math.min(o.max, v or o.min))
        if step == 1 then return math.floor(v + 0.5) end
        return o.min + math.floor((v - o.min) / step + 0.5) * step
    end
    local function Same(a, b) return a ~= nil and b ~= nil and math.abs(a - b) < step / 2 end

    local RESET_W, GAP = 52, 6
    local h = CreateFrame("Frame", nil, parent)
    h:SetSize(width, BNB.STACKED_SLIDER_H)

    local val = h:CreateFontString(nil, "OVERLAY", "BNBFontHighlightSmall")
    val:SetPoint("TOPRIGHT", h, "TOPRIGHT", 0, 0)
    val:SetJustifyH("RIGHT")

    local lbl = h:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    lbl:SetPoint("TOPLEFT", h, "TOPLEFT", 0, 0)
    lbl:SetPoint("RIGHT", val, "LEFT", -8, 0)
    lbl:SetJustifyH("LEFT")
    lbl:SetWordWrap(false)
    lbl:SetTextColor(0.78, 0.78, 0.78)
    local text = o.label or ""
    if o.default ~= nil then
        text = (text ~= "" and text .. "  " or "")
            .. "|cff888888" .. string.format(L["SLIDER_DEFAULT_FMT"], fmt(o.default)) .. "|r"
    end
    lbl:SetText(text)

    local reset = BNB.CreateButton(nil, h, L["RESET"], RESET_W, 20)
    reset:SetPoint("TOPRIGHT", h, "TOPRIGHT", 0, -16)

    local sl = CreateFrame("Slider", nil, h, "MinimalSliderWithSteppersTemplate")
    sl:SetPoint("TOPLEFT", h, "TOPLEFT", 0, -16)
    sl:SetPoint("RIGHT", reset, "LEFT", -GAP, 0)
    sl:SetHeight(20)
    local cur = Snap(o.value)
    sl:Init(cur, o.min, o.max, math.floor((o.max - o.min) / step + 0.5))
    NoSliderWheel(sl)
    BNB.SkinSlider(sl)   -- skin mode: tinted to the preset (ALL-393)

    local enabled, muted = true, false
    local function Sync()
        val:SetText(fmt(cur))
        local atDef = o.default == nil or Same(cur, o.default)
        reset:SetEnabled(enabled and not atDef)
        reset:SetAlpha((enabled and not atDef) and 1 or 0.4)
    end
    sl:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, v)
        local n = Snap(v)
        if Same(n, cur) then return end
        cur = n
        Sync()
        if o.onChange and not muted then o.onChange(n) end
    end)

    local function SetValue(v, silent)
        muted = silent and true or false
        sl:SetValue(Snap(v))
        muted = false
    end
    reset:SetScript("OnClick", function()
        if o.default == nil then return end
        if o.onReset then SetValue(o.default, true); o.onReset()
        else SetValue(o.default) end
    end)

    if o.tip or o.tipTitle then
        -- A strip over the label row only, so the slider keeps its own mouse
        local hot = CreateFrame("Frame", nil, h)
        hot:SetPoint("TOPLEFT", h, "TOPLEFT", 0, 0)
        hot:SetPoint("BOTTOMRIGHT", h, "TOPRIGHT", 0, -14)
        hot:EnableMouse(true)
        hot:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if o.tipTitle then GameTooltip:AddLine(o.tipTitle, 1, 1, 1) end
            local lines = type(o.tip) == "table" and o.tip or { o.tip }
            for _, line in ipairs(lines) do GameTooltip:AddLine(line, 0.8, 0.8, 0.8, true) end
            GameTooltip:Show()
        end)
        hot:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    h._slider = sl
    function h:SetValue(v, silent) SetValue(v, silent) end
    function h:GetValue() return cur end
    function h:SetEnabled(on)
        enabled = on and true or false
        pcall(sl.SetEnabled, sl, enabled)
        Sync()
        if _skinBars[sl] then C_Timer.After(0, _skinBars[sl]) end   -- dim / undim the tint
    end
    Sync()
    return h
end

--------------------------------------------------------------------------------
-- 24-color grid: 8 columns × 3 rows, Dukul's named palette (ALL-259,
-- 2026-10-05; it replaced class colours, several of which looked alike).
-- Saved colours are RGB values, never an index here, so notes keep theirs.
-- label: the colour's name, used in tooltips.
-- Tooltip format: "Description (R:255 G:255 B:255)"
--------------------------------------------------------------------------------
BNB.COLOR_PALETTE = {
    -- Row 1
    { r=1.000, g=1.000, b=1.000, label=L["COLOR_WHITE"] },  -- #ffffff
    { r=0.000, g=0.000, b=0.000, label=L["COLOR_BLACK"] },  -- #000000
    { r=0.769, g=0.118, b=0.227, label=L["COLOR_CARDINAL"] },  -- #c41e3a
    { r=0.533, g=0.000, b=0.082, label=L["COLOR_MAROON"] },  -- #880015
    { r=0.725, g=0.478, b=0.341, label=L["COLOR_PHEASANT"] },  -- #b97a57
    { r=1.000, g=0.682, b=0.788, label=L["COLOR_BABY_PINK"] },  -- #ffaec9
    { r=1.000, g=0.788, b=0.055, label=L["COLOR_MIKADO_YELLOW"] },  -- #ffc90e
    { r=1.000, g=0.949, b=0.000, label=L["COLOR_DORN_YELLOW"] },  -- #fff200
    -- Row 2
    { r=0.937, g=0.894, b=0.690, label=L["COLOR_BONE_WHITE"] },  -- #efe4b0
    { r=0.133, g=0.694, b=0.298, label=L["COLOR_BABYLON_GREEN"] },  -- #22b14c
    { r=0.710, g=0.902, b=0.114, label=L["COLOR_LURID_LETTUCE"] },  -- #b5e61d
    { r=0.000, g=0.635, b=0.910, label=L["COLOR_BEL_AIR_BLUE"] },  -- #00a2e8
    { r=0.600, g=0.851, b=0.918, label=L["COLOR_OVER_THE_SKY"] },  -- #99d9ea
    { r=0.247, g=0.282, b=0.800, label=L["COLOR_WARM_BLUE"] },  -- #3f48cc
    { r=0.439, g=0.573, b=0.745, label=L["COLOR_KING_NEPTUNE"] },  -- #7092be
    -- (Fuchsia Pheromone #a349a4 removed, too close to Epic; its last slot in
    -- the grid is the colour picker tile, Dukul 2026-10-06)
    -- Row 3: light purple, then the item quality colours (names from the game)
    { r=0.784, g=0.749, b=0.906, label=L["COLOR_LIGHT_PURPLE"] },  -- #c8bfe7
    { r=0.616, g=0.616, b=0.616, label=_G["ITEM_QUALITY0_DESC"] or "Poor" },  -- #9d9d9d
    { r=0.118, g=1.000, b=0.000, label=_G["ITEM_QUALITY2_DESC"] or "Uncommon" },  -- #1eff00
    { r=0.000, g=0.439, b=0.867, label=_G["ITEM_QUALITY3_DESC"] or "Rare" },  -- #0070dd
    { r=0.639, g=0.208, b=0.933, label=_G["ITEM_QUALITY4_DESC"] or "Epic" },  -- #a335ee
    { r=1.000, g=0.502, b=0.000, label=_G["ITEM_QUALITY5_DESC"] or "Legendary" },  -- #ff8000
    { r=0.902, g=0.800, b=0.502, label=_G["ITEM_QUALITY6_DESC"] or "Artifact" },  -- #e6cc80
    { r=0.000, g=0.800, b=1.000, label=_G["ITEM_QUALITY7_DESC"] or "Heirloom" },  -- #00ccff
}

--------------------------------------------------------------------------------
-- Colour picker tile: the square after the palette (Assets\UI\ui-color-picker)
-- that opens the colour picker. getColor() -> r, g, b to start from (nil =
-- white); onPick(r, g, b) on every change, and onPick(r, g, b, true) with the
-- start colour again on Cancel. Every colour grid ends with one (Dukul 2026-10-06), which replaced
-- the "Click to pick color" swatches and the Custom color button.
--------------------------------------------------------------------------------
function BNB.CreateColorPickerTile(parent, size, getColor, onPick)
    local sw = CreateFrame("Button", nil, parent)
    sw:SetSize(size, size)
    local tx = sw:CreateTexture(nil, "ARTWORK")
    tx:SetAllPoints()
    tx:SetTexture("Interface\\AddOns\\BigNoteBox\\Assets\\UI\\ui-color-picker")
    local hi = sw:CreateTexture(nil, "HIGHLIGHT")
    hi:SetAllPoints()
    hi:SetColorTexture(1, 1, 1, 0.25)
    local bdr = BNB.CreateBackdropFrame("Frame", nil, sw)
    bdr:SetAllPoints()
    bdr:SetFrameLevel(sw:GetFrameLevel() - 1)
    BNB.SetBackdrop(bdr, 0, 0, 0, 0, 0.30, 0.30, 0.32, 0.9)
    bdr:EnableMouse(false)
    sw:SetScript("OnClick", function()
        local r, g, b
        if getColor then r, g, b = getColor() end
        r, g, b = r or 1, g or 1, b or 1
        BNB.OpenColorPicker(r, g, b, onPick, function() onPick(r, g, b, true) end)
    end)
    sw:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["STICKY_CLICK_PICK_COLOR"], 1, 1, 1)
        GameTooltip:Show()
    end)
    sw:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return sw
end

--------------------------------------------------------------------------------
-- BuildColorGrid
-- Renders BNB.COLOR_PALETTE as an 8×3 swatch grid on `ct` starting at y, the
-- colour picker tile in the last slot (BNB.CreateColorPickerTile).
-- contentW: available pixel width — swatch size is computed from it.
-- onPick(r, g, b): called when a swatch is clicked or the picker changes.
-- getColor() -> r, g, b: where the picker starts (the current colour).
-- getCurrent() -> r, g, b or nil: the colour the ring marks (nil = no ring,
-- e.g. a default nobody picked); nil = getColor. It is polled, so it must not
-- change anything (the sticky background's getColor does).
-- The current colour's swatch gets the selected mark; a colour that is not in
-- the palette marks the picker tile (ALL-330, Dukul 2026-10-06). The grid follows
-- getColor by itself (after a click, on show and by a light poll while shown),
-- so a note switch or a Cancel needs no call from the window.
-- Returns the new y below the grid.
--------------------------------------------------------------------------------
-- The selected-colour mark (Assets\UI\ui-color-picker-selected, Dukul
-- 2026-10-06): a green diamond drawn over the whole swatch, its centre open
-- so the colour shows; btn._selRing. The New note dialog's grid uses it too
function BNB.AddColorSelRing(btn)
    local t = btn:CreateTexture(nil, "OVERLAY")
    t:SetAllPoints()
    t:SetTexture("Interface\\AddOns\\BigNoteBox\\Assets\\UI\\ui-color-picker-selected")
    t:Hide()
    btn._selRing = t
end

local function SameColor(a, b) return a and b and math.abs(a - b) < 0.003 end

local AddSelRing = BNB.AddColorSelRing

function BNB.BuildColorGrid(ct, y, contentW, onPick, getColor, getCurrent)
    local COLS = 8
    local ROWS = 3
    local GAP  = 3
    local SZ   = math.floor((contentW - (COLS - 1) * GAP) / COLS)
    local swatches, tile = {}, nil

    -- Ring the current colour's swatch, or the tile for any other colour
    local function MarkCurrent()
        local r, g, b
        local cur = getCurrent or getColor
        if cur then r, g, b = cur() end
        local hit = false
        for _, sw in ipairs(swatches) do
            local on = r ~= nil and not hit
                and SameColor(r, sw._r) and SameColor(g, sw._g) and SameColor(b, sw._b)
            if on then hit = true end
            sw._selRing:SetShown(on and true or false)
        end
        if tile then tile._selRing:SetShown(r ~= nil and not hit) end
    end
    local function Pick(r, g, b, cancel)
        onPick(r, g, b, cancel)
        MarkCurrent()
    end

    for i, c in ipairs(BNB.COLOR_PALETTE) do
        local col = (i - 1) % COLS
        local row = math.floor((i - 1) / COLS)
        local sw  = CreateFrame("Button", nil, ct)
        sw:SetSize(SZ, SZ)
        sw:SetPoint("TOPLEFT", ct, "TOPLEFT",
            col * (SZ + GAP),
            y - row * (SZ + GAP))

        local tx = sw:CreateTexture(nil, "ARTWORK")
        tx:SetAllPoints()
        tx:SetColorTexture(c.r, c.g, c.b)

        local hi = sw:CreateTexture(nil, "HIGHLIGHT")
        hi:SetAllPoints()
        hi:SetColorTexture(1, 1, 1, 0.35)

        -- Thin border frame so swatches have a subtle outline
        local bdr = BNB.CreateBackdropFrame("Frame", nil, sw)
        bdr:SetAllPoints()
        bdr:SetFrameLevel(sw:GetFrameLevel() - 1)
        BNB.SetBackdrop(bdr, 0, 0, 0, 0, 0.30, 0.30, 0.32, 0.9)
        bdr:EnableMouse(false)

        local cr, cg, cb, lbl = c.r, c.g, c.b, c.label
        sw._r, sw._g, sw._b = cr, cg, cb
        AddSelRing(sw)
        swatches[#swatches + 1] = sw
        sw:SetScript("OnClick", function() Pick(cr, cg, cb) end)
        sw:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(string.format("%s (R:%d G:%d B:%d)",
                lbl,
                math.floor(cr * 255 + 0.5),
                math.floor(cg * 255 + 0.5),
                math.floor(cb * 255 + 0.5)), cr, cg, cb)
            GameTooltip:Show()
        end)
        sw:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    local n = #BNB.COLOR_PALETTE   -- the tile takes the next slot (the last one)
    tile = BNB.CreateColorPickerTile(ct, SZ, getColor, Pick)
    tile:SetPoint("TOPLEFT", ct, "TOPLEFT",
        (n % COLS) * (SZ + GAP), y - math.floor(n / COLS) * (SZ + GAP))
    AddSelRing(tile)

    -- Follow the colour while shown: a light poll (every 0.25 s, 24 compares)
    -- catches note switches and changes made elsewhere without a hook per window
    local watch = CreateFrame("Frame", nil, tile)
    local acc = 0
    watch:SetScript("OnShow", function() acc = 0; MarkCurrent() end)
    watch:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.25 then return end
        acc = 0
        MarkCurrent()
    end)
    MarkCurrent()

    return y - (ROWS * (SZ + GAP)) - 4
end

--------------------------------------------------------------------------------
-- TAG AUTOCOMPLETE
-- Shared dropdown for tag input fields (NoteEditor + NoteConfig).
-- Modelled on BCB's autocomplete: backdrop frame, row buttons, highlight tex.
-- Usage:
--   BNB.AttachTagAutocomplete(editbox)
-- The dropdown opens above the editbox (tags sit at panel bottom).
-- Selecting a row or pressing Tab fills the field and fires OnEnterPressed.
-- The dropdown is a single shared instance, repositioned on each open.
--------------------------------------------------------------------------------
local _tagAC = nil   -- shared autocomplete frame (built once)
local MAX_AC_ROWS = 8
local AC_ROW_H    = 22

local function BuildTagAutocomplete()
    if _tagAC then return _tagAC end

    local popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    popup:SetBackdrop({
        bgFile   = "Interface\\Buttons\\White8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    popup:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
    popup:SetBackdropBorderColor(0.4, 0.4, 0.5, 1)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetFrameLevel(200)
    popup:SetClampedToScreen(true)
    popup:Hide()
    popup:EnableMouse(true)
    popup.rows    = {}
    popup.matches = {}
    popup.selIdx  = 0
    popup._eb     = nil   -- currently attached editbox

    for i = 1, MAX_AC_ROWS do
        local row = CreateFrame("Button", nil, popup)
        row:SetHeight(AC_ROW_H)
        row:SetPoint("TOPLEFT",  popup, "TOPLEFT",  4, -4 - (i-1)*AC_ROW_H)
        row:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -4, -4 - (i-1)*AC_ROW_H)

        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(0.3, 0.5, 0.8, 0.3)

        local sel = row:CreateTexture(nil, "BACKGROUND")
        sel:SetAllPoints()
        sel:SetColorTexture(0.2, 0.4, 0.7, 0.5)
        sel:Hide()
        row.selTex = sel

        -- Tag name (left)
        local nameLbl = row:CreateFontString(nil, "ARTWORK", "BNBFontHighlightSmall")
        nameLbl:SetPoint("LEFT", 8, 0)
        nameLbl:SetJustifyH("LEFT")
        row.nameLbl = nameLbl

        -- Count (right, dimmed)
        local countLbl = row:CreateFontString(nil, "ARTWORK", "BNBFontHighlightSmall")
        countLbl:SetPoint("RIGHT", -8, 0)
        countLbl:SetJustifyH("RIGHT")
        countLbl:SetTextColor(0.5, 0.5, 0.5)
        row.countLbl = countLbl

        local idx = i
        row:SetScript("OnClick", function()
            popup:Select(idx)
        end)
        row:SetScript("OnEnter", function()
            popup.selIdx = idx
            popup:UpdateSel()
        end)
        popup.rows[i] = row
    end

    function popup:UpdateSel()
        for i, r in ipairs(self.rows) do
            r.selTex[i == self.selIdx and "Show" or "Hide"](r.selTex)
        end
    end

    function popup:Select(idx)
        local m = self.matches[idx]
        if not m or not self._eb then return end
        local eb = self._eb
        self._selecting = true   -- prevent OnEditFocusLost from hiding while we commit
        if eb.SetRealText then
            eb:SetRealText(m.tag)
        else
            eb:SetText(m.tag)
        end
        self:Hide()
        -- Fire OnEnterPressed so the tag gets committed immediately
        local fn = eb:GetScript("OnEnterPressed")
        if fn then fn(eb) end
        self._selecting = false
    end

    function popup:ShowFor(eb, partial)
        self._eb = eb
        -- Gather matches: tagIndex keys that start with partial (case-insensitive)
        local idx = BNB.TagIndex()
        if not idx then self:Hide(); return end
        local lpartial = partial:lower()
        -- Build set of tags already on the current note so we can exclude them
        local noteTags = {}
        local noteID = BNB._currentNoteID
        local note   = noteID and BNB.GetNote and BNB.GetNote(noteID)
        if note and note.tags then
            for _, t in ipairs(note.tags) do
                noteTags[t:lower()] = true
            end
        end
        local found = {}
        for tag, ids in pairs(idx) do
            -- Skip tags already on this note
            if not noteTags[tag:lower()] then
                if #partial == 0 or tag:lower():sub(1, #lpartial) == lpartial then
                    if tag:lower() ~= lpartial then   -- don't suggest exact match
                        local count = 0
                        for _ in pairs(ids) do count = count + 1 end
                        found[#found + 1] = { tag = tag, count = count }
                    end
                end
            end
        end
        if #found == 0 then self:Hide(); return end
        -- Sort: least-used first so most-used appears at the bottom
        -- (dropdown opens upward, so most-used is closest to the input field)
        table.sort(found, function(a, b)
            if a.count ~= b.count then return a.count < b.count end
            return a.tag:lower() > b.tag:lower()
        end)
        self.matches = found
        local visible = math.min(#found, MAX_AC_ROWS)
        self.selIdx  = visible   -- start selection at bottom (most-used)
        for i = 1, MAX_AC_ROWS do
            if i <= visible then
                self.rows[i].nameLbl:SetText(found[i].tag)
                self.rows[i].countLbl:SetText("(" .. found[i].count .. ")")
                self.rows[i]:Show()
            else
                self.rows[i]:Hide()
            end
        end
        self:SetHeight(visible * AC_ROW_H + 8)
        self:SetWidth(math.max(eb:GetWidth(), 160))
        self:ClearAllPoints()
        -- Open upward (tag fields sit at the bottom of panels)
        self:SetPoint("BOTTOMLEFT", eb, "TOPLEFT", 0, 2)
        self:Show()
        self:UpdateSel()
    end

    function popup:MoveSelection(delta)
        local n = math.min(#self.matches, MAX_AC_ROWS)
        if n == 0 then return end
        self.selIdx = ((self.selIdx - 1 + delta) % n) + 1
        self:UpdateSel()
    end

    _tagAC = popup
    BNB._tagAC = popup   -- exposed for OnEnterPressed handlers in tag inputs
    return popup
end

-- Attach tag autocomplete behaviour to a tag-input EditBox.
-- The editbox must already have AddPlaceholder applied.
function BNB.AttachTagAutocomplete(eb)
    local ac = BuildTagAutocomplete()

    -- Show full tag list (most-used first) as soon as the field is clicked
    eb:HookScript("OnEditFocusGained", function(self)
        ac:ShowFor(self, "")
    end)

    eb:HookScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local text = self._showingPlaceholder and "" or (self:GetText() or "")
        text = text:match("^%s*(.-)%s*$") or ""
        if text == "" then
            ac:Hide()
        else
            ac:ShowFor(self, text)
        end
    end)

    -- Tab key: cycle through suggestions or confirm top match
    eb:HookScript("OnTabPressed", function(self)
        if ac:IsShown() and ac._eb == self then
            if #ac.matches > 0 then
                ac:Select(ac.selIdx)
            end
        end
    end)

    -- Arrow keys navigate; Enter commits selection; Escape dismisses
    -- Block Backspace/Delete when the placeholder text is showing — otherwise
    -- the placeholder itself becomes editable and deletable.
    -- Also block ALL key propagation while focused so game bindings (WASD, C, etc.)
    -- don't fire while the player is typing a tag.
    local PASSTHROUGH = { ESCAPE = true, TAB = true }
    eb:HookScript("OnKeyDown", function(self, key)
        if self._showingPlaceholder and (key == "BACKSPACE" or key == "DELETE") then
            BNB.SetPropagate(self, false)
            return
        end
        -- Pass Escape/Tab through so WoW handles focus/close; eat everything else
        BNB.SetPropagate(self, PASSTHROUGH[key] == true)
    end)

    eb:HookScript("OnKeyDown", function(self, key)
        if not ac:IsShown() or ac._eb ~= self then return end
        if key == "UP" then
            ac:MoveSelection(-1)
            BNB.SetPropagate(self, false)
        elseif key == "DOWN" then
            ac:MoveSelection(1)
            BNB.SetPropagate(self, false)
        elseif key == "ESCAPE" then
            ac:Hide()
            BNB.SetPropagate(self, false)
        elseif key == "ENTER" or key == "NUMPADENTER" then
            -- Fill the field with the highlighted suggestion so OnEnterPressed
            -- receives the completed tag text rather than the partial typed text.
            if #ac.matches > 0 then
                local m = ac.matches[ac.selIdx]
                if m then
                    if self.SetRealText then self:SetRealText(m.tag)
                    else self:SetText(m.tag) end
                    ac:Hide()
                    -- Let the real OnEnterPressed fire with the filled text
                end
            end
            -- Don't block propagation — OnEnterPressed needs to run
        end
    end)

    -- Hide dropdown when focus leaves
    eb:HookScript("OnEditFocusLost", function()
        -- Tiny delay so a row click registers before hide.
        -- Don't hide if Select() is mid-commit (row click).
        C_Timer.After(0.15, function()
            if ac._selecting then return end
            if ac._eb == eb then ac:Hide(); ac._eb = nil end
        end)
    end)
end

--------------------------------------------------------------------------------
-- CLIPBOARD HINT  —  floating "Press Ctrl+C to copy" prompt shown whenever
-- the addon pre-selects text in the hidden clipboard helper editbox.
--
-- Usage:  BNB.ShowClipboardHint(content [, anchorFrame [, deferFocus [, preview]]])
--   Selects `content` in the hidden helper editbox, positions a small hint
--   frame near the cursor (or below anchorFrame if supplied), and waits for
--   Ctrl+C (copies + dismisses) or ESC (dismisses without copying).
--   The frame is named BNBClipboardHintFrame so the MainWindow ESC chain can
--   find and close it at the highest priority.
--
--   `deferFocus` (optional, default false): pass true when the calling button's
--   OnClick path makes synchronous focus unreliable. Defers SetFocus() by one
--   tick so it lands after any same-tick focus contention.
--
--   `preview` (optional): true adds a third, small line with the start of
--   `content`, so a link button shows what it copies (ALL-222). Only for
--   short text the player cannot see elsewhere: export windows leave it off.
--
-- IMPORTANT: The hint frame is at TOOLTIP strata. It MUST NOT have
-- EnableKeyboard(true), because TOOLTIP strata beats editbox focus in WoW's
-- keyboard routing priority — and Ctrl+C would be routed to the hint frame
-- (a plain Frame, which cannot perform the engine-level copy) instead of the
-- focused helper editbox. ESC dismissal is handled by the helper's OnKeyDown.
--------------------------------------------------------------------------------
function BNB.ShowClipboardHint(content, anchorFrame, deferFocus, preview)
    -- ── 1. Ensure the invisible text-selection editbox exists ─────────────────
    if not BNB._clipboardHelper then
        local helper = CreateFrame("EditBox", nil, UIParent)
        helper:SetSize(1, 1)
        helper:SetAlpha(0)
        helper:SetPoint("CENTER")
        helper:SetAutoFocus(false)
        helper:SetMultiLine(true)
        helper:SetMaxLetters(0)
        helper:Hide()
        BNB._clipboardHelper = helper
    end

    -- ── 2. Ensure the hint frame exists (built once, reused) ─────────────────
    if not BNB._clipboardHint then
        local f = BNB.CreateBackdropFrame("Frame", "BNBClipboardHintFrame", UIParent)
        f:SetFrameStrata("TOOLTIP")
        f:SetFrameLevel(200)
        f:SetSize(220, 48)
        f:Hide()
        BNB.SetBackdrop(f, 0.06, 0.06, 0.08, 0.97, 0.45, 0.45, 0.45, 1)

        -- ── AutoCast glow (LibCustomGlow) in BNB green — started on show ──────
        -- LCG is loaded by the time ShowClipboardHint is first called (post-login).

        -- ── Keyboard icon ──────────────────────────────────────────────────────
        local icon = f:CreateTexture(nil, "ARTWORK")
        icon:SetSize(24, 24)
        icon:SetPoint("LEFT", f, "LEFT", 10, 0)
        f._icon = icon
        pcall(function()
            icon:SetAtlas("groupfinder-icon-keyboard", true)
        end)

        -- ── Main label ─────────────────────────────────────────────────────────
        local lbl = f:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
        lbl:SetPoint("LEFT",  icon, "RIGHT", 8, 4)
        lbl:SetPoint("RIGHT", f,    "RIGHT", -8, 4)
        lbl:SetJustifyH("LEFT")
        lbl:SetText(L["WIDGET_CLIPBOARD_HINT"])
        lbl:SetTextColor(0.400, 0.733, 0.416, 1)

        -- ── Sub-label ──────────────────────────────────────────────────────────
        local sub = f:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
        sub:SetPoint("LEFT",  icon, "RIGHT", 8, -10)
        sub:SetPoint("RIGHT", f,    "RIGHT", -8, -10)
        sub:SetJustifyH("LEFT")
        sub:SetTextColor(0.55, 0.55, 0.55)
        sub:SetText(L["WIDGET_CLIPBOARD_HINT_SUB"])

        -- ── Preview line (opt-in, ALL-222): clipped by the client's own "..." ──
        local prev = f:CreateFontString(nil, "OVERLAY", "BNBFontHighlightSmall")
        prev:SetPoint("LEFT",  icon, "RIGHT", 8, -24)
        prev:SetPoint("RIGHT", f,    "RIGHT", -8, -24)
        prev:SetJustifyH("LEFT"); prev:SetWordWrap(false)
        prev:SetTextColor(0.75, 0.75, 0.75)
        prev:SetTextScale(0.9)
        prev:Hide()
        f._preview = prev

        -- ── Main frame pulse animation ─────────────────────────────────────────
        -- Breathes the whole frame between 0.80 and 1.0 alpha.
        local pulseAG = f:CreateAnimationGroup()
        pulseAG:SetLooping("REPEAT")
        local p1 = pulseAG:CreateAnimation("Alpha")
        p1:SetFromAlpha(1.0)
        p1:SetToAlpha(0.80)
        p1:SetDuration(0.7)
        p1:SetSmoothing("IN_OUT")
        p1:SetOrder(1)
        local p2 = pulseAG:CreateAnimation("Alpha")
        p2:SetFromAlpha(0.80)
        p2:SetToAlpha(1.0)
        p2:SetDuration(0.7)
        p2:SetSmoothing("IN_OUT")
        p2:SetOrder(2)
        f._pulseAG = pulseAG

        -- ── Dismiss ────────────────────────────────────────────────────────────
        local function Dismiss()
            f._pulseAG:Stop()
            -- Stop LCG AutoCast glow. LCG uses dot syntax: first arg is the frame, NOT self.
            local LCG2 = LibStub and LibStub("LibCustomGlow-1.0", true)
            if LCG2 then pcall(LCG2.AutoCastGlow_Stop, f, "bnb_clip") end
            f:Hide()
            BNB._clipboardHelper:ClearFocus()
            BNB._clipboardHelper:Hide()
        end

        f._dismiss = Dismiss

        -- Close with the frame it is anchored to. Without this, closing the
        -- window behind the copy box stranded it on screen: the helper had lost
        -- focus, so ESC never reached it (ALL-21)
        f:SetScript("OnUpdate", function(self)
            if self._anchor and not self._anchor:IsVisible() then Dismiss() end
        end)

        -- Click the box to close it: a fallback for any other path that
        -- leaves it up without keyboard focus. Mouse only, so Ctrl+C routing
        -- to the helper editbox is unaffected
        f:EnableMouse(true)
        f:SetScript("OnMouseDown", function() Dismiss() end)

        BNB._clipboardHint = f
    end

    -- ── 3. Load content into helper and focus it ──────────────────────────────
    local helper = BNB._clipboardHelper
    local hint   = BNB._clipboardHint

    helper:Show()
    helper:SetText(content)
    if deferFocus then
        -- Defer focus by one tick for callers whose OnClick path makes
        -- synchronous focus unreliable (e.g. Share Note's copy button).
        C_Timer.After(0, function()
            if helper:IsShown() then
                helper:SetFocus()
                helper:HighlightText()
            end
        end)
    else
        helper:SetFocus()
        helper:HighlightText()
    end

    -- Intercept keys on the focused editbox.
    --
    -- Ctrl+C fix: do NOT propagate the key. The OS copy is performed by the
    -- WoW engine at the editbox level (highlighted text → clipboard) before
    -- key propagation happens, so swallowing the key here still copies the
    -- text but prevents WoW from also firing the "C" keybind (Character window).
    --
    -- ESC: swallow and dismiss without copying.
    helper:SetScript("OnKeyDown", function(self, key)
        if key == "C" and IsControlKeyDown() then
            BNB.SetPropagate(self, false)         -- copy happens; swallow to block keybinds
            hint._dismiss()
        elseif key == "ESCAPE" then
            BNB.SetPropagate(self, false)
            hint._dismiss()
        else
            BNB.SetPropagate(self, true)
        end
    end)

    -- ── 4. Size for the preview line, then position below anchorFrame if
    -- given, otherwise near the cursor ────────────────────────────────────────
    local hw, hh = 220, 48
    if preview and content and content ~= "" then
        hw, hh = 260, 64
        hint._preview:SetText((content:gsub("[\r\n]+", " "):sub(1, 120)))
        hint._preview:Show()
        hint._icon:SetPoint("LEFT", hint, "LEFT", 10, 8)
    else
        hint._preview:Hide()
        hint._icon:SetPoint("LEFT", hint, "LEFT", 10, 0)
    end
    hint:SetSize(hw, hh)
    hint:ClearAllPoints()
    hint._anchor = anchorFrame
    if anchorFrame then
        -- Anchor centred below the button that triggered the hint
        hint:SetPoint("TOP", anchorFrame, "BOTTOM", 0, -6)
    else
        local scale  = UIParent:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        cx = cx / scale
        cy = cy / scale
        local ox = cx + 16
        local oy = cy + 16
        if ox + hw > GetScreenWidth()  then ox = cx - hw - 4 end
        if oy + hh > GetScreenHeight() then oy = cy - hh - 4 end
        hint:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", ox, oy)
    end
    hint:Show()
    hint:Raise()
    hint._pulseAG:Play()
    -- Start AutoCast glow (BNB green) on the hint frame.
    -- Signature: AutoCastGlow_Start(frame, color, N, frequency, scale, xOffset, yOffset, key, frameLevel)
    -- LCG uses dot syntax: first arg is the frame, NOT self.
    local LCG2 = LibStub and LibStub("LibCustomGlow-1.0", true)
    if LCG2 then
        pcall(LCG2.AutoCastGlow_Start, hint,
            { 0.400, 0.733, 0.416, 1.0 }, nil, nil, nil, nil, nil, "bnb_clip")
    end
end

--------------------------------------------------------------------------------
-- BOTTOM-RIGHT GRIP RESIZE (ALL-97)
-- Replaces f:StartSizing("BOTTOMRIGHT"), which snapped the window's corner to
-- the pointer (every click on the grip grew or shrank the window a little) and,
-- with resize bounds larger than the screen and SetClampedToScreen, could throw
-- the window to the top and blow it up to the whole screen (Dukul, 2026-09-28).
-- Here the top-left is pinned, the size follows the pointer's movement from
-- the press (not its position), within the frame's resize bounds and never past
-- the screen's right or bottom edge. Call Start from the grip's OnMouseDown and
-- Stop from its OnMouseUp; SetSize fires OnSizeChanged as StartSizing did.
--------------------------------------------------------------------------------
function BNB.StartGripSizing(f)
    local left, top = f:GetLeft(), f:GetTop()
    if not (left and top) then return end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)

    local s        = f:GetEffectiveScale()
    local cx, cy   = GetCursorPosition()
    local w0, h0   = f:GetSize()
    local minW, minH, maxW, maxH = f:GetResizeBounds()
    -- Room to the screen's bottom-right, in the frame's own units
    local screenW  = UIParent:GetWidth() * UIParent:GetEffectiveScale() / s
    local roomW, roomH = screenW - left, top
    maxW = (maxW and maxW > 0) and math.min(maxW, roomW) or roomW
    maxH = (maxH and maxH > 0) and math.min(maxH, roomH) or roomH
    -- No bounds set (Rich Preview): a floor so the window cannot vanish
    if not minW or minW <= 0 then minW = 150 end
    if not minH or minH <= 0 then minH = 100 end

    local drv = f._gripDriver or CreateFrame("Frame")
    f._gripDriver = drv
    drv:SetScript("OnUpdate", function()
        local x, y = GetCursorPosition()
        local w = math.max(minW, math.min(maxW, w0 + (x - cx) / s))
        local h = math.max(minH, math.min(maxH, h0 + (cy - y) / s))
        f:SetSize(w, h)
    end)
end

function BNB.StopGripSizing(f)
    if f._gripDriver then f._gripDriver:SetScript("OnUpdate", nil) end
end

-- The resize grip every resizable window uses (ALL-263): the damage meter's
-- scale handle with its own hover and pressed atlases (Dukul, 2026-10-04: art
-- 32, click area 24), the chat grabber where the atlas is missing. Drives
-- BNB.StartGripSizing / StopGripSizing. opts: { x, y = BOTTOMRIGHT offset,
-- canSize = fn -> false to refuse a press (a locked sticky), onStart, onStop,
-- onLeave }. grip._sizing is true while sizing. The grip owns OnMouseDown /
-- OnMouseUp / OnEnter / OnLeave: add behaviour through opts or HookScript.
local GRIP_ATLAS, GRIP_ART, GRIP_HIT = "damagemeters-scalehandle", 32, 24
local GRIP_HOVER_R, GRIP_HOVER_G, GRIP_HOVER_B = 0.40, 0.85, 0.40   -- BNB green (NoteList COL_SEL_BG)
local GRABBER = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-"
function BNB.CreateResizeGrip(f, opts)
    opts = opts or {}
    local grip = CreateFrame("Button", nil, f)
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", opts.x or 0, opts.y or 0)
    grip:SetFrameLevel(f:GetFrameLevel() + 10)
    local hasAtlas = C_Texture and C_Texture.GetAtlasInfo
        and C_Texture.GetAtlasInfo(GRIP_ATLAS) ~= nil
    local tex
    if hasAtlas then
        grip:SetSize(GRIP_HIT, GRIP_HIT)
        tex = grip:CreateTexture(nil, "OVERLAY")
        tex:SetSize(GRIP_ART, GRIP_ART)
        tex:SetPoint("BOTTOMRIGHT", grip, "BOTTOMRIGHT", 0, 0)
        tex:SetAtlas(GRIP_ATLAS)
    else
        grip:SetSize(16, 16)
        grip:SetNormalTexture(GRABBER .. "Up")
        grip:SetHighlightTexture(GRABBER .. "Highlight")
        grip:GetHighlightTexture():SetVertexColor(GRIP_HOVER_R, GRIP_HOVER_G, GRIP_HOVER_B)
        grip:SetPushedTexture(GRABBER .. "Down")
    end

    -- Pressed while sizing, hover while the pointer is over it, else normal.
    -- The hover art is tinted BNB green (ALL-278, Dukul), the rest untinted.
    local function SetState()
        if not tex then return end
        local hover = not grip._sizing and grip:IsMouseOver()
        tex:SetAtlas(GRIP_ATLAS .. (grip._sizing and "-pressed"
            or (hover and "-hover" or "")))
        if hover then tex:SetVertexColor(GRIP_HOVER_R, GRIP_HOVER_G, GRIP_HOVER_B)
        else tex:SetVertexColor(1, 1, 1) end
    end
    grip:SetScript("OnMouseDown", function(_, btn)
        if btn ~= "LeftButton" then return end
        if opts.canSize and not opts.canSize() then return end
        grip._sizing = true
        SetState()
        if opts.onStart then opts.onStart() end
        BNB.StartGripSizing(f)
    end)
    grip:SetScript("OnMouseUp", function()
        if not grip._sizing then return end
        grip._sizing = false
        BNB.StopGripSizing(f)
        SetState()
        if opts.onStop then opts.onStop() end
    end)
    grip:SetScript("OnEnter", SetState)
    grip:SetScript("OnLeave", function()
        SetState()
        if opts.onLeave then opts.onLeave() end
    end)
    grip:HookScript("OnHide", function()
        -- Hidden mid-drag (window closed): stop following the pointer
        if grip._sizing then
            grip._sizing = false
            BNB.StopGripSizing(f)
            if opts.onStop then opts.onStop() end
        end
        SetState()
    end)
    BNB.SetHoverCursor(grip, "resize")   -- ALL-95
    return grip
end

-- Window drag without StartMoving (ALL-97, drag half). On Retail with a UI
-- scale of 0.8 the client's StartMoving threw the main window 100-190 px up on
-- every drag (probed 2026-10-03: one CENTER anchor on UIParent, height well
-- inside the screen, and the jump stayed with the screen clamp off and with
-- IsUserPlaced cleared). Same idea as StartGripSizing: pin TOPLEFT, follow the
-- pointer's movement, keep the window on screen when it is clamped. The clamp
-- honours SetClampRectInsets (the top sidebar tabs add theirs, ALL-248).
-- Call StartDragMoving from OnDragStart and StopDragMoving from OnDragStop.
function BNB.StartDragMoving(f)
    local left, top = f:GetLeft(), f:GetTop()
    if not (left and top) then return end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)

    local s       = f:GetEffectiveScale()
    local cx, cy  = GetCursorPosition()
    local w, h    = f:GetSize()
    -- The screen in the frame's own units
    local us      = UIParent:GetEffectiveScale()
    local screenW = UIParent:GetWidth()  * us / s
    local screenH = UIParent:GetHeight() * us / s
    local clamp   = f:IsClampedToScreen()
    -- Positive top / right and negative left / bottom insets reach outside the frame
    local il, ir, it, ib = f:GetClampRectInsets()
    il, ir, it, ib = il or 0, ir or 0, it or 0, ib or 0

    local drv = f._dragDriver or CreateFrame("Frame")
    f._dragDriver = drv
    drv:SetScript("OnUpdate", function(self)
        if not f:IsShown() then self:SetScript("OnUpdate", nil); return end
        local x, y = GetCursorPosition()
        local l = left + (x - cx) / s
        local t = top  + (y - cy) / s
        if clamp then
            l = math.min(math.max(l, -il), math.max(-il, screenW - w - ir))
            t = math.max(math.min(t, screenH - it), math.min(h - ib, screenH - it))
        end
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
    end)
end

function BNB.StopDragMoving(f)
    if f._dragDriver then f._dragDriver:SetScript("OnUpdate", nil) end
end

--------------------------------------------------------------------------------
-- RIGHT-CLICK MENUS: every one goes through BNB.ContextMenu.Open(owner, build)
-- (UI/ContextMenu.lua, ALL-148). It opens at the pointer and closes when
-- `owner` (the row or box right-clicked) hides. PlaceContextMenu, the old
-- helper for Blizzard's hidden-DropdownButton menus (ALL-81), is gone.
--------------------------------------------------------------------------------

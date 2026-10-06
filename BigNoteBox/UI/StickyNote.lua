-- BigNoteBox UI/StickyNote.lua — Floating Sticky Notes
--
-- Layout: header + body scroll. No footer.
-- Header buttons (right→left): x close | _ minimize | = settings | e edit
--
-- MINIMIZE: collapses to a MINI_SIZE×MINI_SIZE icon tile anchored at the
-- top-right corner of the note's current position (where the minimize button
-- is). The tile is draggable; a click-without-move restores the note.
-- The resize handle is hidden when minimized so it can't be accidentally used.
--
-- SETTINGS: pressing "=" hides the front face via alpha crossfade (simulated
-- flip) and shows a settings face at the same size. The settings face uses the
-- same visual style as the main window (ButtonFrameTemplate colors, matching
-- header). "< Back" reverses the crossfade. Uses BNB.CreateStackedSlider
-- and WowStyle1DropdownTemplate for border.
--
-- HOVER: every child frame forwards OnEnter/OnLeave to the root so the full
-- note surface responds to hover alpha.

local BNB = BigNoteBox
local L   = BNB.L

BNB.Sticky = BNB.Sticky or {}
local SN = BNB.Sticky

-- ── Constants ─────────────────────────────────────────────────────────────────
local DEF_W      = 260
local DEF_H      = 220
local MIN_W      = 160
local MIN_H      = 140
-- Small padding so the header sits just inside the top border edge.
local HEADER_BORDER_PAD = 6
local HEADER_H   = 28
local MINI_SIZE  = 40
local PAD        = 10
local FOCUS_PAD  = 4    -- reduced padding in focus mode
local TASK_FOOTER_H = 20   -- height of the sticky note task footer strip
local FLIP_TIME  = 0.18   -- seconds for settings fade-in/out

local COL_HEADER = { 0.10, 0.10, 0.13 }
local COL_BG     = { 0.07, 0.07, 0.09 }
local COL_BORDER = { 0.35, 0.35, 0.38 }
local COL_GOLD   = { 1, 0.82, 0, 1 }

-- The default sticky colours (Dukul 2026-10-06): in skin mode the skin preset's
-- own colour and border at brightness 1.00, so a sticky stays fairly dark
-- whatever the Skin brightness slider says; in normal mode the old dark grey.
-- A sticky uses them while cfg.bgFollow is set (no colour ever picked).
local function SkinFollowPreset(cfg)
    local db = BigNoteBoxDB
    if cfg and cfg.bgFollow and db and db.skinMode and BNB.GetSkinPreset then
        return BNB.GetSkinPreset()
    end
end
local function DefaultBg(cfg)
    local p = SkinFollowPreset(cfg)
    if p then return p.r, p.g, p.b end
    return COL_BG[1], COL_BG[2], COL_BG[3]
end
-- The header bar: the preset's lifted colour (as skin title strips), else COL_HEADER
local function HeaderRGB(cfg)
    local p = SkinFollowPreset(cfg)
    if p then
        local lift = p.lift or 0
        return math.min(1, p.r + lift), math.min(1, p.g + lift), math.min(1, p.b + lift)
    end
    return COL_HEADER[1], COL_HEADER[2], COL_HEADER[3]
end

-- The border's own colour: the skin preset's border while the sticky follows
-- it, else COL_BORDER.
local function BorderBase(cfg)
    local p = SkinFollowPreset(cfg)
    if p then return p.br, p.bg_, p.bb end
    return COL_BORDER[1], COL_BORDER[2], COL_BORDER[3]
end

-- Border RGB at cfg.borderBrightness without the part above 100 % (for a
-- backdrop drawn at alpha 0). A visible border goes through SetStickyBorder.
local function BorderRGB(cfg)
    local m = BNB.BorderBright.Split(cfg and cfg.borderBrightness)
    local r, g, b = BorderBase(cfg)
    return r * m, g * m, b * m
end

-- A backdrop's border at the sticky's brightness, 0..200 %: above 100 % by
-- ADD copies, since the client clamps vertex colours at 1 (ALL-142)
local function SetStickyBorder(target, cfg, a)
    local r, g, b = BorderBase(cfg)
    BNB.BorderBright.SetBackdropBorder(target, cfg and cfg.borderBrightness, r, g, b, a)
end

-- bgR/G/B are not in here: GetCfg fills them from DefaultBg while bgFollow is
-- set, so a default sticky follows the skin preset live
local DEFAULT_CFG = {
    alpha      = 0.90,   -- was 0.96 (Dukul 2026-10-06)
    fontSize   = nil,
    fontID     = nil,
    textR = 0.88, textG = 0.88, textB = 0.88,
    textAlpha  = 1.0,
    textAlign  = "LEFT",
    fontOutline = "None",
    borderName       = "Default",
    borderScale      = 100,
    borderOffset     = 2,
    borderBrightness = 100,
    bgTexture      = "none", -- key into BNB.StickyBG (UI/StickyBackgrounds.lua); "none" = plain colour
    bgColorOpacity = 1.0,    -- 0.0 = raw paper colour (white tint), 1.0 = full chosen colour
}

-- ── State ──────────────────────────────────────────────────────────────────────
local openFrames = {}
-- A closed sticky's frame, kept per note and reused on its next open (PERF-03):
-- WoW never frees a frame, so every close and reopen (situations, alarms, ESC
-- stickies) used to leak a whole sticky tree. Only the same note reuses its
-- frame, because the frame's scripts are bound to the note id it was built for.
local closedFrames = {}

-- Settings > Modules > Sticky notes "Keep sticky notes above BigNoteBox
-- windows" (nil = off, Dukul 2026-10-02: off by default now that Ctrl+J
-- brings them forward). On: HIGH, over the main window (MEDIUM). Off: MEDIUM
-- as well, where SetToplevel brings whichever window was clicked last to the
-- front. ESC-screen stickies keep FULLSCREEN_DIALOG.
function SN.Strata()
    return (BigNoteBoxDB and BigNoteBoxDB.stickiesOnTop == true) and "HIGH" or "MEDIUM"
end

-- Re-strata every open sticky and mini tile after the setting changes
function SN.ApplyStrata()
    local s = SN.Strata()
    for _, f in pairs(openFrames) do
        if not f._escOnly then f:SetFrameStrata(s) end
        if f._miniTile then f._miniTile:SetFrameStrata(s) end
    end
end
BNB._stickyFrames = openFrames

-- Open stickies on the default colour follow a skin preset change (SkinChanged,
-- sent by ApplyMainWindowSkin). ApplyConfig re-reads GetCfg, which fills the
-- colour from the preset while cfg.bgFollow is set
local ApplyConfig   -- below
function SN.ApplySkinColours()
    for noteID, f in pairs(openFrames) do
        pcall(ApplyConfig, f, noteID)
        if f._miniTile and f._miniTile._applyColours then pcall(f._miniTile._applyColours) end
    end
end
if BNB.RegisterMessage then
    BNB.RegisterMessage("StickyNote.Skin", "SkinChanged", function() SN.ApplySkinColours() end)
end

-- Per-note collapse state for sticky task rows: _stickyCollapsed[noteID][taskID] = true
-- Persists across re-renders; cleared when the sticky is closed.
local _stickyCollapsed = {}

-- Guard so TasksChanged callback is registered only once.
local _stickyTaskCallbackRegistered = false

-- ── ESC menu (GameMenuFrame) integration ──────────────────────────────────────
-- Stickies with cfg.escOnly=true are hidden in the game world and shown only
-- when the ESC menu is open.  We hook OnShow/OnHide on GameMenuFrame (safe,
-- no taint) and iterate openFrames each time the menu appears or disappears.
-- _escHookDone ensures the hook is registered exactly once across reloads.
local _escHookDone = false

-- ── ESC dim overlay ───────────────────────────────────────────────────────────
-- A full-screen dark overlay shown behind ESC-pinned stickies (and GameMenuFrame)
-- to help them stand out.  Mirrors the FocusEditor overlay pattern exactly.
-- Created once and reused; color refreshes live when the skin preset changes.
local _escOverlay = nil

local function _escOverlayColor()
    local db = BigNoteBoxDB
    if db and db.skinMode and BNB.GetSkinPreset and BNB.SkinColourOf then
        local preset = BNB.GetSkinPreset()
        local r, g, b = BNB.SkinColourOf(preset, false)
        -- Darken the skin color so it reads as a dim, not a tint.
        -- Factor 0.4 gives roughly 40% of the already-dark base color.
        return r * 0.4, g * 0.4, b * 0.4
    end
    return 0, 0, 0  -- plain black in normal mode
end

local function GetESCOverlay()
    if _escOverlay then return _escOverlay end
    local ov = CreateFrame("Frame", nil, UIParent)
    ov:SetAllPoints(UIParent)
    ov:SetFrameStrata("DIALOG")
    ov:SetFrameLevel(1)   -- just above OneWoW's dim (level 0) if present
    ov:EnableMouse(false)  -- click-through
    local tex = ov:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints()
    tex:SetColorTexture(0, 0, 0, 1)
    ov._tex = tex
    ov:Hide()
    -- Refresh color live when the skin preset or brightness changes.
    if BNB.RegisterSkinBackdrop then
        BNB.RegisterSkinBackdrop(function()
            if ov:IsShown() then
                local r, g, b = _escOverlayColor()
                ov._tex:SetColorTexture(r, g, b, 0.6)
            end
        end)
    end
    _escOverlay = ov
    return ov
end

local function ShowESCOverlay()
    local db = BigNoteBoxDB
    -- Overlay disabled in config.
    if db and db.stickyEscOverlay == false then return end
    -- OneWoW detection: if their dim overlay exists and is visible, skip ours
    -- to avoid double-darkening the screen.
    if _G["OneWoWEscDimOverlay"] and _G["OneWoWEscDimOverlay"]:IsShown() then return end
    local ov = GetESCOverlay()
    local r, g, b = _escOverlayColor()
    ov._tex:SetColorTexture(r, g, b, 0.6)
    ov:Show()
end

local function HideESCOverlay()
    if _escOverlay and _escOverlay:IsShown() then
        _escOverlay:Hide()
    end
end

local function EnsureESCHook()
    if _escHookDone then return end
    _escHookDone = true
    -- GameMenuFrame is always available on retail Midnight; guard anyway.
    if not GameMenuFrame then return end
    GameMenuFrame:HookScript("OnShow", function()
        local hasESCSticky = false
        for _, f in pairs(openFrames) do
            local cfg = f._cfg
            if cfg and cfg.escOnly then
                if not f._minimized then f:Show() end
                f:Raise()
                hasESCSticky = true
            end
        end
        -- Only show the dim overlay when at least one ESC-pinned sticky is open.
        if hasESCSticky then ShowESCOverlay() end
    end)
    GameMenuFrame:HookScript("OnHide", function()
        for _, f in pairs(openFrames) do
            local cfg = f._cfg
            if cfg and cfg.escOnly then
                f:Hide()
                if f._miniTile then f._miniTile:Hide() end
            end
        end
        HideESCOverlay()
        -- Settings panel close is handled by SN._OnESCHide(), registered after
        -- all locals are in scope (CloseStickySettings is in UI/StickySettings.lua).
        if SN._OnESCHide then SN._OnESCHide() end
    end)
end

-- Close the ESC menu (if open) then call fn().  Used for header button clicks
-- that open other BNB windows so the game menu doesn't stay open behind them.
local function CloseESCAndDo(fn)
    if GameMenuFrame and GameMenuFrame:IsShown() then
        HideUIPanel(GameMenuFrame)
    end
    fn()
end

-- ── DB helpers ────────────────────────────────────────────────────────────────
local function DB()       return BigNoteBoxDB end
local function StickyDB() return BigNoteBoxDB and BigNoteBoxDB.postits or {} end
local function CountOpen()
    local n = 0; for _ in pairs(openFrames) do n = n + 1 end; return n
end

-- Close enough to a saved literal (SavedVariables round-trip)
local function Near(a, b) return a ~= nil and math.abs(a - b) < 0.001 end

local function GetCfg(noteID)
    local rec = noteID and StickyDB()[noteID]
    local cfg = (rec and rec.cfg) and rec.cfg or {}
    -- Once per sticky (cfgV 2, Dukul 2026-10-06): the old defaults were saved
    -- in full, so a colour that is still exactly the old default counts as
    -- never picked and follows the new default (skin colour), and an opacity
    -- still at the old 96% moves to the new 90%
    if (cfg.cfgV or 1) < 2 then
        if cfg.bgFollow == nil and (cfg.bgR == nil
           or (Near(cfg.bgR, COL_BG[1]) and Near(cfg.bgG, COL_BG[2]) and Near(cfg.bgB, COL_BG[3]))) then
            cfg.bgFollow = true
        end
        if Near(cfg.alpha, 0.96) then cfg.alpha = nil end
        cfg.cfgV = 2
    end
    for k, v in pairs(DEFAULT_CFG) do
        if cfg[k] == nil then cfg[k] = v end
    end
    if cfg.bgFollow then cfg.bgR, cfg.bgG, cfg.bgB = DefaultBg(cfg) end
    if cfg.bgR == nil then cfg.bgR, cfg.bgG, cfg.bgB = COL_BG[1], COL_BG[2], COL_BG[3] end
    return cfg
end

local function SaveCfg(noteID, cfg)
    local db = DB(); if not db then return end
    db.postits = db.postits or {}
    db.postits[noteID] = db.postits[noteID] or {}
    db.postits[noteID].cfg = cfg
end

-- Lock sticky (ALL-257): position and size stay where they are, everything
-- else still works. Every drag start and the resize grip ask this.
local function StickyLocked(noteID)
    local rec = noteID and StickyDB()[noteID]
    return (rec and rec.cfg and rec.cfg.locked == true) or false
end
SN.IsLocked = StickyLocked

-- Lock or unlock a sticky (Sticky settings button and the right-click menu)
-- A rich note's sticky shown as plain text, or back to rich (ALL-357):
-- the header's view button and the settings' Plain text state button
function SN.SetPlainView(noteID, on)
    local cfg = (SN._SettingsCfg and SN._SettingsCfg(noteID)) or GetCfg(noteID)
    cfg.richPlainText = on and true or nil
    SaveCfg(noteID, cfg)
    if SN._RefreshSettingsStates then SN._RefreshSettingsStates(noteID) end
    if SN.RefreshNote then SN.RefreshNote(noteID) end
    local f = openFrames[noteID]
    if f and f._syncViewBtn then f._syncViewBtn() end
end

function SN.SetLocked(noteID, on)
    local cfg = (SN._SettingsCfg and SN._SettingsCfg(noteID)) or GetCfg(noteID)
    cfg.locked = on and true or nil
    SaveCfg(noteID, cfg)
    if SN._RefreshSettingsStates then SN._RefreshSettingsStates(noteID) end
end

local function SaveGeometry(noteID, frame)
    if not noteID then return end
    local db = DB(); if not db then return end
    db.postits = db.postits or {}
    db.postits[noteID] = db.postits[noteID] or {}
    local rec = db.postits[noteID]
    local s   = frame:GetEffectiveScale()
    local cx, cy = frame:GetCenter()
    rec.x         = cx and (cx * s) or 0
    rec.y         = cy and (cy * s) or 0
    rec.w         = frame._savedW or DEF_W
    rec.h         = frame._savedH or DEF_H
    rec.shown     = (frame:IsShown() or frame._escOnly == true) and true or false
    rec.minimized = frame._minimized or false
end

local function LoadGeometry(noteID, frame)
    local rec = noteID and StickyDB()[noteID]
    local w = (rec and rec.w and rec.w >= MIN_W) and rec.w or DEF_W
    local h = (rec and rec.h and rec.h >= MIN_H) and rec.h or DEF_H
    frame._savedW = w
    frame._savedH = h
    if not (rec and rec.minimized) then frame:SetSize(w, h) end
    if rec and rec.x and rec.x ~= 0 then
        local s = frame:GetEffectiveScale()
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", rec.x / s, rec.y / s)
    else
        frame:ClearAllPoints()
        local off = CountOpen() * 26
        frame:SetPoint("CENTER", UIParent, "CENTER", 40 + off, 40 + off)
    end
end

-- ── Background texture registry ───────────────────────────────────────────────
-- Lives in UI/StickyBackgrounds.lua (BNB.StickyBG, ALL-110). BG_TEXTURES is
-- its LIST.
local BG_TEXTURES     = BNB.StickyBG.LIST
local GetBgTextureDef = BNB.StickyBG.Get
local BgTextureLabel  = BNB.StickyBG.Label

-- Background Lab "Try on stickies" (ALL-110): one def shown on every open
-- sticky instead of its own texture. Runtime only, never saved.
local _bgOverride

-- The background def a sticky draws, or nil for plain colour.
local function ActiveBgDef(cfg)
    if _bgOverride then return _bgOverride end
    local def = GetBgTextureDef(cfg and cfg.bgTexture)
    return def.file and def or nil
end

-- Returns the tint multiplied into the background art (vertex colour):
--   cop = 0.0  →  tint (1,1,1) = raw paper colour shows through unchanged
--   cop = 1.0  →  tint is the full chosen colour (cfg.bgR/G/B)
-- Lerp between white and the chosen colour using bgColorOpacity.
local function TintedBgColor(cfg)
    local cop = cfg and cfg.bgColorOpacity or 1.0
    local r = 1 + ((cfg.bgR or COL_BG[1]) - 1) * cop
    local g = 1 + ((cfg.bgG or COL_BG[2]) - 1) * cop
    local b = 1 + ((cfg.bgB or COL_BG[3]) - 1) * cop
    r = math.max(0, r); g = math.max(0, g); b = math.max(0, b)
    -- Safety: if the resulting colour is too dark the texture is invisible.
    -- Lift it toward white just enough to keep that floor, so the slider
    -- stays smooth (a jump to white made Colorize go black near 94 % and
    -- then do nothing above it, Dukul 2026-09-28). The stored bgR/G/B is
    -- never modified -- the user's colour choice is preserved and reapplies
    -- if they switch the texture back to None.
    local FLOOR = 0.12
    local luma = 0.299 * r + 0.587 * g + 0.114 * b
    if luma < FLOOR then
        local t = (FLOOR - luma) / (1 - luma)   -- white's luma is 1
        r, g, b = r + (1 - r) * t, g + (1 - g) * t, b + (1 - b) * t
    end
    return r, g, b
end

-- ── Visual config application ──────────────────────────────────────────────────
local function ApplyBorderToFrame(target, borderName, borderScale, borderOffset, cfg)
    pcall(function()
        if not target.SetBackdrop then return end
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        local bPath = borderName and borderName ~= "" and borderName ~= "None"
            and borderName ~= "Default"
            and LSM and LSM:Fetch("border", borderName)
        -- Always plain White8x8: a background texture is drawn by the
        -- texture layer under the border (ApplyBgLayer, ALL-110), which
        -- takes the inset recorded here.
        local bgFile, bgTile, bgTileSz = "Interface\\Buttons\\White8x8", true, 8
        if bPath then
            local es  = math.max(1, math.floor(16 * (borderScale or 100) / 100 + 0.5))
            local ins = math.max(0, math.floor(borderOffset or 4))
            target._bgInset = ins
            target:SetBackdrop({
                bgFile = bgFile, tile = bgTile, tileSize = bgTileSz,
                edgeFile = bPath, edgeSize = es,
                insets = { left = ins, right = ins, top = ins, bottom = ins },
            })
        elseif not borderName or borderName == "" or borderName == "None" then
            target._bgInset = 0
            target:SetBackdrop({
                bgFile = bgFile, tile = bgTile, tileSize = bgTileSz,
                edgeSize = 0,
                insets = { left = 0, right = 0, top = 0, bottom = 0 },
            })
            SetStickyBorder(target, cfg, 0)
        else
            -- "Default" border — the standard BNB backdrop
            target._bgInset = 3
            if target.SetBackdrop then
                target:SetBackdrop({
                    bgFile   = bgFile,   tile = bgTile, tileSize = bgTileSz,
                    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                    edgeSize = 14,
                    insets   = { left = 3, right = 3, top = 3, bottom = 3 },
                })
                pcall(function()
                    target:SetBackdropColor(COL_BG[1], COL_BG[2], COL_BG[3], 0.97)
                    SetStickyBorder(target, cfg, 1)
                end)
            end
        end
    end)
end

-- ── Icon border ──────────────────────────────────────────────────────────────
-- Applies an LSM border around the icon/mini-tile using a separate overlay
-- frame that grows outward with thickness. The icon texture is never clipped.
-- Always uses note.borderOverride (not cfg.borderName) so the sticky icon
-- matches the note list icon.
local function ApplyIconBorder(target, borderName, borderScale, borderOffset, borderBrightness)
    if not target then return end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local bPath = borderName and borderName ~= "" and borderName ~= "None"
        and LSM and LSM:Fetch("border", borderName)
    if bPath then
        if not target._borderOverlay then
            local bf = BNB.CreateBackdropFrame("Frame", nil, target)
            bf:SetFrameLevel(target:GetFrameLevel() + 1)
            bf:EnableMouse(false)
            target._borderOverlay = bf
        end
        local bf = target._borderOverlay
        local es = math.max(1, math.floor(12 * (borderScale or 100) / 100 + 0.5))
        local pad = borderOffset or 2
        bf:ClearAllPoints()
        bf:SetPoint("TOPLEFT",     target, "TOPLEFT",     -pad,  pad)
        bf:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT",  pad, -pad)
        pcall(function()
            bf:SetBackdrop({
                edgeFile = bPath, edgeSize = es,
                insets = { left = 0, right = 0, top = 0, bottom = 0 },
            })
            bf:SetBackdropColor(0, 0, 0, 0)
            BNB.BorderBright.SetBackdropBorder(bf, borderBrightness, 0.70, 0.70, 0.75, 0.85)
        end)
        bf:Show()
    else
        if target._borderOverlay then target._borderOverlay:Hide() end
    end
end

-- ALL-127: draws note.iconFrame on iconTex when set, else falls back to the
-- LSM edge border on target (the icon badge or mini tile frame). The two are
-- never both on: picking one in the picker clears the other.
local function ApplyIconDecoration(target, iconTex, note, borderName, borderScale, borderOffset, borderBright)
    local hasFrame = iconTex and BNB.ApplyIconFrame and BNB.ApplyIconFrame(iconTex, note, iconTex._size)
    ApplyIconBorder(target, not hasFrame and borderName, borderScale, borderOffset, borderBright)
end


-- ── Font outline helper ───────────────────────────────────────────────────────
-- Returns flags string and shadow (ox, oy, r, g, b, a) for a given outline name.
-- Used by ApplyConfig and PopulateStickySettings.
local OUTLINE_OPTIONS = {
    "None", "Outline", "Thick Outline", "Monochrome Outline",
    "Drop Shadow", "Strong Drop Shadow", "Strongest Drop Shadow",
}
local function GetOutlineFlagsAndShadow(outline)
    local flags, ox, oy, sr, sg, sb, sa = "", 0, 0, 0, 0, 0, 0
    if     outline == "Outline"              then flags = "OUTLINE"
    elseif outline == "Thick Outline"        then flags = "THICKOUTLINE"
    elseif outline == "Monochrome Outline"   then flags = "MONOCHROME,OUTLINE"
    elseif outline == "Drop Shadow"          then ox, oy, sr, sg, sb, sa =  1, -1, 0, 0, 0, 0.8
    elseif outline == "Strong Drop Shadow"   then ox, oy, sr, sg, sb, sa =  2, -2, 0, 0, 0, 1.0
    elseif outline == "Strongest Drop Shadow" then ox, oy, sr, sg, sb, sa = 3, -3, 0, 0, 0, 1.0
    end
    return flags, ox, oy, sr, sg, sb, sa
end

local function ApplyOutlineToEditBox(eb, outline)
    if not eb then return end
    local flags, ox, oy, sr, sg, sb, sa = GetOutlineFlagsAndShadow(outline or "None")
    local path, sz = eb:GetFont()
    if path then pcall(function() eb:SetFont(path, sz, flags) end) end
    pcall(function() eb:SetShadowOffset(ox, oy) end)
    pcall(function() eb:SetShadowColor(sr, sg, sb, sa) end)
end

-- Shows the sticky's background texture on its texture layer (ALL-110), or
-- hides the layer for plain colour. Colours and opacity: ApplyBgAlpha.
local function ApplyBgLayer(frame, cfg)
    local def = ActiveBgDef(cfg)
    if not (def or frame._bgLayer) then return end
    frame._bgLayer = frame._bgLayer or BNB.BgLayer.Create(frame)
    BNB.BgLayer.Set(frame._bgLayer, def, frame._bgInset)
end

-- Apply background opacity via backdrop alpha only — never frame:SetAlpha.
-- This keeps text opacity (bodyEb:SetAlpha) independent of background opacity.
local function ApplyBgAlpha(frame, bgAlpha, cfg)
    local a = bgAlpha or DEFAULT_CFG.alpha
    frame._bgA = a   -- where a hover fade starts from
    local c = frame._cfg
    local ec = cfg or c
    local br, bg2, bb = BorderRGB(ec)
    local effectiveBorder = ec and ec.borderName
    local borderA = (not effectiveBorder or effectiveBorder == "" or effectiveBorder == "None") and 0 or a
    if c and frame.SetBackdropColor then
        local layer = frame._bgLayer
        if layer and layer._def and ec then
            -- Texture layer (ALL-110): the note's colour as the base under
            -- the art, the Colorize tint and brightness on the art, opacity
            -- on the layer. The backdrop centre goes clear so only the
            -- border draws.
            local tr, tg, tb = TintedBgColor(ec)
            BNB.BgLayer.SetColors(layer, ec.bgR or COL_BG[1], ec.bgG or COL_BG[2], ec.bgB or COL_BG[3],
                tr, tg, tb, ec.bgBrightness)
            BNB.BgLayer.SetAlpha(layer, a)
            pcall(frame.SetBackdropColor, frame, 0, 0, 0, 0)
        else
            local tr = c.bgR or COL_BG[1]
            local tg = c.bgG or COL_BG[2]
            local tb = c.bgB or COL_BG[3]
            pcall(frame.SetBackdropColor, frame, tr, tg, tb, a)
        end
        SetStickyBorder(frame, ec, borderA)
    end
    -- Method + arguments, not a closure: this runs every frame of a hover
    -- fade (PERF-08)
    local hb = frame._headerBar
    if hb and hb.SetBackdropColor then
        local hr, hg, hbl = HeaderRGB(ec)   -- the skin preset's while the sticky follows it
        pcall(hb.SetBackdropColor, hb, hr, hg, hbl, a)
        pcall(hb.SetBackdropBorderColor, hb, br, bg2, bb, 0)
    end
end

-- ── Hover fade ───────────────────────────────────────────────────────────────
-- Hovering a sticky eases its background and body text up to full opacity and
-- back down to the note's own levels instead of flipping (Dukul, 2026-09-27).
-- Driven only by the sticky's hover poll (the "over" test in its OnUpdate,
-- which counts inline editing and task rows too), never by OnEnter/OnLeave:
-- rich text, task rows and scrollbars swallow those, so the note dimmed while
-- the pointer was still on it. One shared driver frame runs every fade.
-- ApplyBgAlpha records the current level in _bgA.
-- Every fade takes HOVER_FADE, however far it goes (ALL-209, Dukul
-- 2026-10-02): a fixed rate made 70 % -> 100 % last about 0.06 s, a snap.
local HOVER_FADE = 0.25  -- seconds per fade
local _hoverFades = {}   -- [frame] = { to, textTo, rate, textRate }
local _hoverDriver

local function StepTo(cur, to, step)
    if cur < to then return math.min(to, cur + step) end
    return math.max(to, cur - step)
end

local function HoverFadeTick(self, elapsed)
    local any
    for f, st in pairs(_hoverFades) do
        local a = StepTo(f._bgA or st.to, st.to, elapsed * st.rate)
        ApplyBgAlpha(f, a, f._cfg)
        local done = a == st.to
        local eb = f._bodyEb
        if eb then
            local ta = StepTo(eb:GetAlpha(), st.textTo, elapsed * st.textRate)
            eb:SetAlpha(ta)
            done = done and ta == st.textTo
        end
        if done then _hoverFades[f] = nil else any = true end
    end
    if not any then self:Hide() end
end

-- hovered = true eases to full opacity, false back to the note's own levels
local function HoverBgAlpha(frame, hovered)
    local c = frame._cfg
    local to     = hovered and 1 or (c and c.alpha or DEFAULT_CFG.alpha)
    local textTo = hovered and 1 or (c and c.textAlpha or 1.0)
    local from     = frame._bgA or to
    local textFrom = frame._bodyEb and frame._bodyEb:GetAlpha() or textTo
    -- Per-fade rates, so both reach their level in HOVER_FADE
    _hoverFades[frame] = {
        to = to, textTo = textTo,
        rate     = math.max(math.abs(to - from), 0.01) / HOVER_FADE,
        textRate = math.max(math.abs(textTo - textFrom), 0.01) / HOVER_FADE,
    }
    if not _hoverDriver then
        _hoverDriver = CreateFrame("Frame")
        _hoverDriver:SetScript("OnUpdate", HoverFadeTick)
    end
    _hoverDriver:Show()
end

-- A direct set (config applied, texture tried) ends any running fade and
-- makes the hover poll look again, so a hovered note fades back up
local function StopHoverFade(frame)
    _hoverFades[frame] = nil
    frame._bgHover = nil
end

-- ── Scroll frame anchor helper ───────────────────────────────────────────────
-- Anchors a scroll frame's TOPLEFT to front (the full-interior overlay) using
-- absolute offsets computed from the current header height.  This avoids
-- anchoring to header BOTTOMLEFT which WoW's layout engine does not reliably
-- reflow when the header is collapsed to height 0 (focus mode).
-- Only touches TOPLEFT; BOTTOMRIGHT is already anchored to front directly.
local function AnchorScrollTop(sf, front, headerH, fp)
    if not sf then return end
    local y = -(HEADER_BORDER_PAD + headerH + fp)
    local x = HEADER_BORDER_PAD + fp
    sf:SetPoint("TOPLEFT", front, "TOPLEFT", x, y)
end

-- Draws the note's icon into tex, the same way the note list does: NPC notes
-- get the NPC's face from the saved display ID (ALL-46, Features/TargetNote.lua)
-- and keep the note icon until it is resolved.
local STICKY_DEFAULT_ICON = "Interface\\Icons\\INV_Misc_Note_06"
local function SetStickyNoteIcon(tex, note)
    if not tex then return end
    local icon = note and (BNB.NpcNoteIcon and BNB.NpcNoteIcon(note) or note.icon)
    tex:SetTexture((icon and icon ~= "") and icon or STICKY_DEFAULT_ICON)
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if note and BNB.SetNpcNotePortrait then BNB.SetNpcNotePortrait(tex, note) end
    -- Its unit targeted now: the live portrait, as the note list row (ALL-208)
    if BNB.NoteMatchesTarget and BNB.NoteMatchesTarget(note) then
        pcall(SetPortraitTexture, tex, "target")
    end
end

-- A note's icon drawn as the sticky's badge draws it: icon or NPC portrait,
-- then its icon frame or LSM edge border on target. The note list's context
-- menu header uses it (ALL-148).
function SN.DrawNoteIcon(target, tex, note)
    SetStickyNoteIcon(tex, note)
    ApplyIconDecoration(target, tex, note, note.borderOverride,
        note.borderScale or 100, note.borderOffset or 2, note.borderBrightness or 100)
end

function ApplyConfig(frame, noteID)   -- the local declared above SN.ApplySkinColours
    local cfg  = GetCfg(noteID)
    local note = BNB.GetNote(noteID)
    frame._cfg = cfg
    -- Effective border for the main sticky frame: sticky cfg takes priority,
    -- falls back to note-level borderOverride from NoteConfig.
    local effectiveBorder = cfg.borderName
        or (note and note.borderOverride)
    local effectiveScale  = cfg.borderScale or 100
    local effectiveOffset = cfg.borderOffset or 4
    local focusMode = cfg.focusMode
    local borderA = (not effectiveBorder or effectiveBorder == "" or effectiveBorder == "None") and 0 or 1
    if focusMode then borderA = 0 end  -- border hidden in focus mode (lerped in OnUpdate on hover)
    pcall(function()
        ApplyBorderToFrame(frame, effectiveBorder, effectiveScale, effectiveOffset, cfg)
        -- Colours: ApplyBgAlpha further down, which also covers the texture layer
        frame:SetBackdropColor(cfg.bgR, cfg.bgG, cfg.bgB, cfg.alpha or DEFAULT_CFG.alpha)
        SetStickyBorder(frame, cfg, borderA)
    end)
    pcall(ApplyBgLayer, frame, cfg)

    -- Focus mode: reset lerp to 0 (hidden) so header animates in on first hover.
    -- Normal mode: snap lerp to 1 so header is immediately visible.
    if frame._setFocusLerp then
        frame._setFocusLerp(focusMode and 0.0 or 1.0)
    end
    -- In focus mode snap header height immediately; OnUpdate will animate from here.
    if frame._headerBar then
        if focusMode then
            frame._headerBar:SetHeight(0)
        else
            frame._headerBar:SetHeight(HEADER_H)
        end
    end
    if frame._titleLbl then
        frame._titleLbl:SetAlpha(focusMode and 0.0 or 1.0)
    end
    if frame._iconFrame then
        frame._iconFrame:SetAlpha(focusMode and 0.0 or 1.0)
    end
    if frame._taskFooter then
        frame._taskFooter:SetAlpha(focusMode and 0.0 or 1.0)
    end
    -- Snap scrollbar alpha to match focus mode immediately.
    -- In focus mode they start hidden; OnUpdate lerps them in on hover.
    -- In normal mode restore from _hasRange so they re-appear if needed.
    if frame._bodySB then
        frame._bodySB:SetAlpha(focusMode and 0.0 or (frame._bodySB._hasRange and 1.0 or 0))
    end
    if frame._richSB then
        frame._richSB:SetAlpha(focusMode and 0.0 or (frame._richSB._hasRange and 1.0 or 0))
    end
    if frame._taskSB then
        frame._taskSB:SetAlpha(focusMode and 0.0 or (frame._taskSB._hasRange and 1.0 or 0))
    end
    -- Re-anchor scroll frames when focus mode changes.
    -- TOPLEFT is now anchored to front (not header BOTTOMLEFT) via AnchorScrollTop
    -- to avoid WoW's stale-reflow bug when header height is collapsed to 0.
    local _refreshNoteID = frame._noteID
    local prevFocusMode  = frame._lastFocusMode
    local curFocusMode   = focusMode and true or false
    frame._lastFocusMode = curFocusMode
    if prevFocusMode ~= curFocusMode then
        local front = frame._frontFace
        local fp    = focusMode and FOCUS_PAD or PAD
        local hH    = focusMode and 0 or HEADER_H
        if frame._bodyScroll and front then
            frame._bodyScroll:ClearAllPoints()
            AnchorScrollTop(frame._bodyScroll, front, hH, fp)
            frame._bodyScroll:SetPoint("BOTTOMRIGHT", front, "BOTTOMRIGHT", -(fp+22),  fp)
        end
        if frame._richScroll and front then
            frame._richScroll:ClearAllPoints()
            AnchorScrollTop(frame._richScroll, front, hH, fp)
            frame._richScroll:SetPoint("BOTTOMRIGHT", front, "BOTTOMRIGHT", -(fp+22),  fp)
        end
        if frame._taskScroll and front then
            frame._taskScroll:ClearAllPoints()
            AnchorScrollTop(frame._taskScroll, front, hH, fp)
            frame._taskScroll:SetPoint("BOTTOMRIGHT", front, "BOTTOMRIGHT", -(fp+22),   fp + TASK_FOOTER_H + 2)
        end
        if frame._taskFooter and front then
            frame._taskFooter:ClearAllPoints()
            frame._taskFooter:SetHeight(TASK_FOOTER_H)
            frame._taskFooter:SetPoint("BOTTOMLEFT",  front, "BOTTOMLEFT",  fp,       fp)
            frame._taskFooter:SetPoint("BOTTOMRIGHT", front, "BOTTOMRIGHT", -(fp+22), fp)
        end
        -- Defer note refresh so WoW reflows geometry before content reads GetWidth()
        if _refreshNoteID then
            C_Timer.After(0.05, function()
                if openFrames[_refreshNoteID] == frame and not frame._taskViewActive then
                    BNB.Sticky.RefreshNote(_refreshNoteID)
                end
            end)
        end
    end
    -- Apply background opacity via backdrop, keep frame alpha at 1.0
    frame:SetAlpha(1.0)
    StopHoverFade(frame)
    ApplyBgAlpha(frame, cfg.alpha or DEFAULT_CFG.alpha, cfg)
    if frame._bodyEb then
        local r, g, b = cfg.textR or 0.88, cfg.textG or 0.88, cfg.textB or 0.88
        pcall(function() frame._bodyEb:SetTextColor(r, g, b) end)
        pcall(function() frame._bodyEb:SetAlpha(cfg.textAlpha or 1.0) end)
        pcall(function() frame._bodyEb:SetJustifyH(cfg.textAlign or "LEFT") end)
        local sz  = cfg.fontSize or (BigNoteBoxDB and BigNoteBoxDB.fontSize) or BNB.DEFAULTS.fontSize
        local fid = cfg.fontID
        local path
        if fid and BNB.ResolveFontDef then path = BNB.ResolveFontDef(fid).regular
        else path = BNB.GetBodyFont and select(1, BNB.GetBodyFont()) end
        local flags = GetOutlineFlagsAndShadow(cfg.fontOutline or "None")
        if path then pcall(function() frame._bodyEb:SetFont(path, BNB.FontPx(path, sz), flags) end) end
        ApplyOutlineToEditBox(frame._bodyEb, cfg.fontOutline or "None")
    end
    -- Icon badge and mini tile use note-level border with scale/offset (matches note list)
    local noteBorder = note and note.borderOverride
    local borderScale = note and note.borderScale or 100
    local borderOffset = note and note.borderOffset or 2
    local borderBright = note and note.borderBrightness or 100
    ApplyIconDecoration(frame._miniTile,  frame._miniTile  and frame._miniTile._iconTex,  note, noteBorder, borderScale, borderOffset, borderBright)
    ApplyIconDecoration(frame._iconFrame, frame._iconFrame and frame._iconFrame._iconTex, note, noteBorder, borderScale, borderOffset, borderBright)
    -- Refresh mini tile icon texture in case the note's icon changed since the
    -- tile was first built (tile._iconTex is set at CreateMiniTile time).
    if frame._miniTile and frame._miniTile._iconTex then
        SetStickyNoteIcon(frame._miniTile._iconTex, note)
    end
end

-- ── Hover forwarding ──────────────────────────────────────────────────────────
-- Used to set the hover alpha from each child's OnEnter/OnLeave. The hover
-- poll does that now (see Hover fade), so the handlers are empty; the calls
-- stay so the scripts they replace (scrollbar pieces included) stay as they
-- have always been.
local function ForwardHover(child, root)
    child:SetScript("OnEnter", function() end)
    child:SetScript("OnLeave", function() end)
end

-- ── Frame fade (replaces LibAnimate, ALL-64) ──────────────────────────────────
-- BNB.FadeTo (UI/GlowOverlay.lua): AnimationGroup alpha fade that never
-- touches the frame's OnUpdate script (see the note on buttons further down).
-- It started here as FadeFrame and became the shared helper in CMP-05.
local FadeFrame = BNB.FadeTo

-- Background Lab "Try on stickies" (ALL-110, developer tool): def shows on
-- every open sticky until it is called with nil, a sticky texture is picked
-- in its settings, or the UI reloads. Only the background is re-applied.
function SN.SetBgOverride(def)
    _bgOverride = def
    for _, f in pairs(openFrames) do
        local c = f._cfg
        if c then
            pcall(ApplyBgLayer, f, c)
            StopHoverFade(f)
            ApplyBgAlpha(f, c.alpha or DEFAULT_CFG.alpha, c)
        end
    end
end

-- Shared with UI/StickySettings.lua (ALL-65.10), which loads after this file.
-- The settings window and the note it edits stay private there: this file
-- asks through SN._IsSettingsOpenFor / _HideSettingsFor / _OpenSettings.
SN._kit = {
    openFrames            = openFrames,
    EnsureESCHook         = EnsureESCHook,
    GetCfg                = GetCfg,
    SaveCfg               = SaveCfg,
    BG_TEXTURES           = BG_TEXTURES,
    BgTextureLabel        = BgTextureLabel,
    OUTLINE_OPTIONS       = OUTLINE_OPTIONS,
    ApplyOutlineToEditBox = ApplyOutlineToEditBox,
    ApplyBgAlpha          = ApplyBgAlpha,
    ApplyConfig           = ApplyConfig,
    FadeFrame             = FadeFrame,
    TintedBgColor         = TintedBgColor,   -- UI/StickyBgPicker.lua thumbnails
    COL_BG                = COL_BG,
}

-- ── Resize handle ─────────────────────────────────────────────────────────────
local function AddResizeHandle(frame, noteID)
    -- The shared grip (UI/Widgets.lua, ALL-263); a locked sticky refuses the
    -- press (ALL-257). Shown and hidden by the hover poll in the OnUpdate.
    local h
    h = BNB.CreateResizeGrip(frame, {
        canSize = function() return not frame._minimized and not StickyLocked(noteID) end,
        onLeave = function() if not h._sizing then h:Hide() end end,
        onStop  = function()
            local w  = math.max(MIN_W, math.min(1200, frame:GetWidth()))
            local ht = math.max(MIN_H, math.min(800,  frame:GetHeight()))
            frame:SetSize(w, ht)
            frame._savedW = w
            frame._savedH = ht
            if frame._bodyScroll then
                local fm = frame._cfg and frame._cfg.focusMode
                local fp = fm and FOCUS_PAD or PAD
                local hH = fm and 0 or HEADER_H
                frame._bodyScroll:ClearAllPoints()
                AnchorScrollTop(frame._bodyScroll, frame._frontFace, hH, fp)
                frame._bodyScroll:SetPoint("BOTTOMRIGHT", frame._frontFace, "BOTTOMRIGHT", -(fp+22),  fp)
            end
            SaveGeometry(noteID, frame)
            -- Hide only if cursor has left the frame entirely
            if not frame:IsMouseOver() then h:Hide() end
        end,
    })

    -- Show/hide driven by the same IsMouseOver poll used for btnOverlay.
    -- This avoids relying on OnEnter/OnLeave from frame (which fires through
    -- ForwardHover on child frames and can race with sizing state).
    h:Hide()
    frame._resizeHandle = h
end

-- ── Minimized tile ────────────────────────────────────────────────────────────
-- 40×40 icon tile placed at the TOPRIGHT of the note's position.
-- Click-without-drag restores. Click-hold-drag moves the tile.
local function CreateMiniTile(frame, noteID, note)
    if frame._miniTile then return frame._miniTile end

    local tile = BNB.CreateBackdropFrame("Frame", nil, UIParent)
    tile:SetSize(MINI_SIZE, MINI_SIZE)
    tile:SetFrameStrata(SN.Strata())
    tile:SetToplevel(true)
    tile:SetMovable(true)
    tile:SetClampedToScreen(true)
    tile:EnableMouse(true)
    -- Same colours as the sticky's header and border (the skin preset's while
    -- it follows it); re-applied by SN.ApplySkinColours
    function tile._applyColours()
        local c = GetCfg(noteID)
        local hr, hg, hb = HeaderRGB(c)
        local br, bg2, bb = COL_BORDER[1], COL_BORDER[2], COL_BORDER[3]   -- normal mode: as before
        BNB.SetBackdrop(tile, hr, hg, hb, 0.95, br, bg2, bb, 1)
        if SkinFollowPreset(c) then SetStickyBorder(tile, c, 1) end
    end
    tile._applyColours()

    local iconTex = tile:CreateTexture(nil, "ARTWORK")
    iconTex:SetSize(MINI_SIZE - 8, MINI_SIZE - 8)
    iconTex:SetPoint("CENTER", tile, "CENTER")
    SetStickyNoteIcon(iconTex, note)
    tile._iconTex = iconTex   -- stored so ApplyConfig can refresh it on icon change

    -- Hover alpha
    tile:SetScript("OnEnter", function()
        local c = frame._cfg
        ApplyBgAlpha(frame, math.max(0.95, c and c.alpha or 0.95), c)
        GameTooltip:SetOwner(tile, "ANCHOR_RIGHT")
        GameTooltip:AddLine(note.title ~= "" and note.title or L["UNTITLED"], 1, 0.82, 0)
        GameTooltip:AddLine(L["STICKY_MINI_LEFTCLICK_TIP"],  0.6, 0.6, 0.6)
        GameTooltip:AddLine(L["STICKY_MINI_RIGHTCLICK_TIP"],   0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    tile:SetScript("OnLeave", function()
        local c = frame._cfg
        ApplyBgAlpha(frame, c and c.alpha or DEFAULT_CFG.alpha, c)
        GameTooltip:Hide()
    end)

    -- Click-vs-drag on the tile
    local _tileDownX, _tileDownY = nil, nil
    local _tileDragging = false
    tile:RegisterForDrag("LeftButton")
    tile:SetScript("OnDragStart", function(self)
        if StickyLocked(noteID) then return end
        _tileDragging = true
        self:StartMoving()
    end)
    tile:SetScript("OnDragStop", function(self)
        _tileDragging = false
        self:StopMovingOrSizing()
    end)
    tile:SetScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" then
            _tileDownX, _tileDownY = GetCursorPosition()
        end
    end)
    tile:SetScript("OnMouseUp", function(self, btn)
        if btn == "RightButton" then
            -- Same full menu as the header/body (ALL-83 follow-up, 2026-09-26:
            -- Kim expected right-click on the icon to bring the menu back,
            -- including "Restore", not a bare dismiss/close shortcut).
            if frame._showStickyCtxMenu then
                frame._showStickyCtxMenu(tile)
            end
            return
        end
        if btn ~= "LeftButton" then return end
        if not _tileDragging then
            local cx, cy = GetCursorPosition()
            local dx = cx - (_tileDownX or cx)
            local dy = cy - (_tileDownY or cy)
            if math.sqrt(dx*dx + dy*dy) < 5 then
                -- Dismiss alarm if glowing before restoring
                if BNB.Alarm and BNB.Alarm.IsAlarmActive and BNB.Alarm.IsAlarmActive(noteID) then
                    BNB.Alarm.Dismiss(noteID)
                end
                SN.SetMinimized(noteID, false)
            end
        end
        _tileDragging = false
    end)

    tile:Hide()
    frame._miniTile = tile
    -- A glow target from the start, like the icon: an alarm that rings while
    -- the sticky is already minimized (in combat it cannot open one) shows here
    if BNB.Alarm and BNB.Alarm.RegisterGlowTarget then
        BNB.Alarm.RegisterGlowTarget(noteID, tile)
    end
    return tile
end

-- ── Icon badge helper ─────────────────────────────────────────────────────────
-- Destroys any existing badge on f, then builds a new one if note.icon is set.
-- Returns the titleLeft offset for the header title anchor.
local ICON_SZ    = 36
local ICON_INSET = 6
local ICON_PAD   = 2

-- Situation and class markers on the icon badge, as on the note list icon.
local function UpdateStickyMarkers(iconFrame, note)
    if not (iconFrame and note) then return end
    if iconFrame._situTex then
        if BNB.HasSituation(note) then iconFrame._situTex:Show()
        else iconFrame._situTex:Hide() end
    end
    if iconFrame._scopeTex then
        local sc = note.scope
        local path = sc and sc:match("^char:") and BNB.Sidebar and BNB.Sidebar.IconForKey
                     and BNB.Sidebar.IconForKey(sc)
        if path then
            iconFrame._scopeTex:SetTexture(path)
            iconFrame._scopeTex:Show()
        else
            iconFrame._scopeTex:Hide()
        end
    end
end

local function BuildIconBadge(f, noteID, note)
    -- The badge is kept while the note has an icon and only redrawn (PERF-03):
    -- RefreshNote runs this on every save, and a new badge each time leaked a
    -- frame tree per save.
    if f._iconFrame and note.icon and note.icon ~= "" then
        local iconFrame = f._iconFrame
        SetStickyNoteIcon(f._badgeTex, note)
        ApplyIconDecoration(iconFrame, f._badgeTex, note, note.borderOverride,
            note.borderScale or 100, note.borderOffset or 2, note.borderBrightness or 100)
        UpdateStickyMarkers(iconFrame, note)
        if BNB.Alarm and BNB.Alarm.RegisterGlowTarget then   -- no-op when registered
            BNB.Alarm.RegisterGlowTarget(noteID, iconFrame)
        end
        return (ICON_SZ - ICON_INSET) - HEADER_BORDER_PAD + 6
    end

    -- Destroy existing badge if present
    if f._iconFrame then
        -- Unregister from alarm glow before destroying
        if BNB.Alarm and BNB.Alarm.UnregisterGlowTarget then
            BNB.Alarm.UnregisterGlowTarget(noteID, f._iconFrame)
        end
        f._iconFrame:Hide()
        f._iconFrame:SetParent(nil)
        f._iconFrame = nil
        f._badgeTex  = nil
    end

    if not (note.icon and note.icon ~= "") then
        return PAD   -- no icon — title starts at normal PAD
    end

    local iconFrame = BNB.CreateBackdropFrame("Button", nil, f)
    iconFrame:SetSize(ICON_SZ, ICON_SZ)
    iconFrame:SetFrameLevel(f:GetFrameLevel() + 20)
    iconFrame:SetPoint("TOPLEFT", f, "TOPLEFT", -ICON_INSET, ICON_INSET)
    BNB.SetBackdrop(iconFrame,
        COL_HEADER[1], COL_HEADER[2], COL_HEADER[3], 0.97,
        COL_BORDER[1], COL_BORDER[2], COL_BORDER[3], 1)

    local iconTex = iconFrame:CreateTexture(nil, "ARTWORK")
    iconTex:SetPoint("TOPLEFT",     iconFrame, "TOPLEFT",     ICON_PAD,  -ICON_PAD)
    iconTex:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -ICON_PAD,  ICON_PAD)
    SetStickyNoteIcon(iconTex, note)
    f._badgeTex = iconTex   -- re-drawn by SN.RefreshNpcPortraits
    iconFrame._iconTex = iconTex
    iconTex._size = ICON_SZ - 2 * ICON_PAD   -- two-anchor sized: no width until laid out

    -- Icon frame or note-level LSM border (matches note list icon; ALL-127:
    -- the icon frame takes over from the edge border when set)
    local noteBorder = note and note.borderOverride
    local borderScale = note and note.borderScale or 100
    local borderOffset = note and note.borderOffset or 2
    local borderBright = note and note.borderBrightness or 100
    ApplyIconDecoration(iconFrame, iconTex, note, noteBorder, borderScale, borderOffset, borderBright)

    -- Markers from the note list icon (UI/NoteList.lua): situation top-right,
    -- class icon of the owning character bottom-left. Same size ratio as the
    -- list's OverlaySize. Shown/hidden by UpdateStickyMarkers.
    local ovSz   = math.max(10, math.floor(ICON_SZ * 0.38))
    local ovHost = CreateFrame("Frame", nil, iconFrame)
    ovHost:SetAllPoints(iconFrame)
    ovHost:SetFrameLevel(iconFrame:GetFrameLevel() + 5)   -- above the icon border
    ovHost:EnableMouse(false)
    local situ = ovHost:CreateTexture(nil, "OVERLAY", nil, 1)
    situ:SetSize(ovSz, ovSz)
    situ:SetPoint("TOPRIGHT", iconFrame, "TOPRIGHT", 2, 2)
    situ:SetTexture("Interface\\AddOns\\BigNoteBox\\Assets\\Overlay\\ov-situation")
    situ:Hide()
    local scope = ovHost:CreateTexture(nil, "OVERLAY", nil, 1)
    scope:SetSize(ovSz, ovSz)
    scope:SetPoint("BOTTOMLEFT", iconFrame, "BOTTOMLEFT", -2, -2)
    scope:Hide()
    iconFrame._situTex  = situ
    iconFrame._scopeTex = scope
    UpdateStickyMarkers(iconFrame, note)

    -- Left-click: toggle minimize (both when normal and when minimized)
    -- Right-click: the same full context menu as the mini tile / header / body
    -- (ALL-83 follow-up, 2026-09-26: Kim expected the icon to behave the same
    -- whether the note is open or minimized)
    iconFrame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    iconFrame:SetScript("OnClick", function(self, btn)
        if btn == "RightButton" then
            if f._showStickyCtxMenu then f._showStickyCtxMenu(iconFrame) end
        elseif btn == "LeftButton" then
            -- The release that ends a drag is not a click (ALL-217)
            if iconFrame._dragged then iconFrame._dragged = nil; return end
            SN.SetMinimized(noteID, not f._minimized)
        end
    end)
    -- Drag the open sticky by its icon, as the minimized tile already moves
    -- (ALL-217); a locked sticky stays put (ALL-257)
    iconFrame:RegisterForDrag("LeftButton")
    iconFrame:SetScript("OnDragStart", function()
        if f._minimized or StickyLocked(noteID) then return end
        iconFrame._dragged = true
        f:StartMoving()
    end)
    iconFrame:SetScript("OnDragStop", function()
        if not iconFrame._dragged then return end
        f:StopMovingOrSizing(); SaveGeometry(noteID, f)
    end)
    -- Each press starts clean, whether or not the client sent a click after
    -- the last drag
    iconFrame:HookScript("OnMouseDown", function() iconFrame._dragged = nil end)

    ForwardHover(iconFrame, f)
    f._iconFrame = iconFrame
    -- Register iconFrame as a glow target for the alarm system.
    -- Must be called after assignment so the frame is valid.
    if BNB.Alarm and BNB.Alarm.RegisterGlowTarget then
        BNB.Alarm.RegisterGlowTarget(noteID, iconFrame)
    end
    -- Title offset from header's left edge. Icon right edge in frame coords =
    -- ICON_SZ - ICON_INSET = 30. Header left starts at HEADER_BORDER_PAD = 6.
    -- In header-local x: 30 - 6 = 24. Add a small gap.
    return (ICON_SZ - ICON_INSET) - HEADER_BORDER_PAD + 6
end

-- ── Sticky task view ──────────────────────────────────────────────────────────

-- Reads the persisted view preference for a sticky, falling back to the global
-- default. Returns "tasks" or "note".
local function GetStickyViewPref(noteID)
    local rec = noteID and StickyDB()[noteID]
    local saved = rec and rec.view
    if saved == "tasks" or saved == "note" then return saved end
    local def = BigNoteBoxDB and BigNoteBoxDB.taskStickyDefault or BNB.DEFAULTS.taskStickyDefault
    return def
end

-- Save which view the sticky is currently in.
local function SaveStickyView(noteID, view)
    local db = DB(); if not db then return end
    db.postits = db.postits or {}
    db.postits[noteID] = db.postits[noteID] or {}
    db.postits[noteID].view = view
end

-- Render (or re-render) the task list into f._taskScroll / f._taskContent.
-- Called on first show and whenever TasksChanged fires for this noteID.
-- HookFocusHover: hooks OnEnter/OnLeave on a frame (and all its children
-- recursively) to maintain f._focusHovered, a counter used by the OnUpdate
-- focus lerp. HookScript is used so existing tooltip handlers are preserved.
-- This is needed because f:IsMouseOver() can return false when the cursor is
-- over scroll-child frames (WoW clips them geometrically from the parent check).
local function HookFocusHover(child, root)
    child:HookScript("OnEnter", function()
        root._focusHovered = (root._focusHovered or 0) + 1
    end)
    child:HookScript("OnLeave", function()
        root._focusHovered = math.max(0, (root._focusHovered or 0) - 1)
    end)
    for _, ch in ipairs({child:GetChildren()}) do
        pcall(function() HookFocusHover(ch, root) end)
    end
end

-- Task rows are built once per sticky and reused (PERF-02): WoW never frees a
-- frame, and every TasksChanged used to orphan a new set. The scripts read
-- what a row shows now from row._noteID / row._task / row._taskID.
local SN_TASK_UI_A  = "Interface\\AddOns\\BigNoteBox\\Assets\\UI\\"
local RenderStickyTasks   -- forward declaration: rows re-render on collapse

-- Reset / situation icon on a sticky task row; tipFn(task) gives the first line.
local function MakeStickyTaskIcon(row, texPath, tipFn)
    local ico = CreateFrame("Button", nil, row)
    ico:SetSize(12, 12)
    ico:SetFrameLevel(row:GetFrameLevel() + 3)
    local tx = ico:CreateTexture(nil, "ARTWORK"); tx:SetAllPoints()
    tx:SetTexture(texPath)
    ico:SetScript("OnEnter", function(self)
        self:SetAlpha(1.0)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(tipFn(row._task), 1, 1, 1)
        GameTooltip:AddLine(L["STICKY_TASK_CLICK_EDIT_TIP"], 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    ico:SetScript("OnLeave", function(self) self:SetAlpha(0.8); GameTooltip:Hide() end)
    ico:SetScript("OnClick", function()
        if BNB.TaskEditWindow and BNB.TaskEditWindow.Open then
            BNB.TaskEditWindow.Open(row._noteID, row._taskID, row)
        end
    end)
    return ico
end

local function CreateStickyTaskRow(ct, f)
    local CB_SZ, TOG_SZ = 14, 14
    local row = CreateFrame("Frame", nil, ct)

    -- Checkbox
    local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    cb:SetSize(CB_SZ, CB_SZ)
    cb:SetPoint("LEFT", row, "LEFT", 0, 0)
    cb:SetScript("OnClick", function()
        if BNB.Task and BNB.Task.ToggleTask then
            BNB.Task.ToggleTask(row._noteID, row._taskID)
        end
    end)
    -- Stop click from bubbling to the row's collapse handler
    cb:SetScript("OnMouseDown", function(_, btn)
        if btn == "LeftButton" then
            -- consume; let CheckButton handle it
        end
    end)

    -- Toggle button: "right" (collapsed) / "down" (expanded), matches RefBox.
    -- Icon button: skin look in skin mode, like the Reference Box toggle (Dukul 2026-10-03).
    -- Hidden entirely for leaf tasks (no sub-tasks) — not functional in sticky.
    local function DoCollapse()
        local collapsed = _stickyCollapsed[row._noteID]
        if not collapsed then return end
        if collapsed[row._taskID] then collapsed[row._taskID] = nil
        else collapsed[row._taskID] = true end
        RenderStickyTasks(row._noteID)
    end
    local togBtn = BNB.CreateIconButton(row, TOG_SZ, "down", { tipAnchor = "ANCHOR_TOP",
        onClick = DoCollapse,
        tip = function()
            local collapsed = _stickyCollapsed[row._noteID]
            return (collapsed and collapsed[row._taskID]) and L["STICKY_EXPAND_SUBTASKS"] or L["STICKY_COLLAPSE_SUBTASKS"]
        end })
    togBtn:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    togBtn:SetFrameLevel(row:GetFrameLevel() + 3)
    -- Invisible hit area covering the row (except checkbox) for tap-to-collapse
    local hitBtn = CreateFrame("Button", nil, row)
    hitBtn:SetPoint("TOPLEFT",     row, "TOPLEFT",     CB_SZ + 2, 0)
    hitBtn:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0,         0)
    hitBtn:SetFrameLevel(row:GetFrameLevel() + 2)  -- below togBtn (+3)
    hitBtn:SetScript("OnClick", DoCollapse)
    row._togBtn, row._hitBtn = togBtn, hitBtn

    -- Reset and situation icons, chained left to right after togBtn by the fill
    row._rstIco = MakeStickyTaskIcon(row, SN_TASK_UI_A .. "ui-repeat", function(task)
        return task.resetType == "daily" and "Reset: Daily" or "Reset: Weekly"
    end)
    row._sitIco = MakeStickyTaskIcon(row, SN_TASK_UI_A .. "ui-situation", function(task)
        return string.format(L["STICKY_TASK_SITUATION_FMT"], task.situation or "")
    end)

    -- Task text label — anchored by the fill, after the last icon shown
    local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetJustifyH("LEFT"); lbl:SetMaxLines(1); lbl:SetWordWrap(false)
    -- Tooltip on truncation
    lbl:SetScript("OnEnter", function(self)
        if self:IsTruncated() then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(row._task.text or "", 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    lbl:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row._cb  = cb
    row._lbl = lbl
    -- Hook all children of this row into the focus-hover counter so the
    -- OnUpdate lerp stays active while the mouse is over any task row element.
    HookFocusHover(row, f)
    return row
end

-- Point a pooled sticky row at a task.
local function FillStickyTaskRow(row, noteID, task, depth, y, rowH, collapsed)
    local ct = row:GetParent()
    local INDENT = BNB.Task.SUBTASK_INDENT or 14
    row._noteID, row._task, row._taskID, row._depth = noteID, task, task.id, depth
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT",  ct, "TOPLEFT",  4 + depth * INDENT, y)   -- PAD_L 4
    row:SetPoint("TOPRIGHT", ct, "TOPRIGHT", -6, y)                   -- PAD_R 6
    row:SetHeight(rowH)
    row._cb:SetChecked(task.completed and true or false)

    local subs        = BNB.Task.GetSubTasks and BNB.Task.GetSubTasks(noteID, task.id)
    local hasSubs     = subs and #subs > 0
    local isCollapsed = collapsed[task.id]
    if hasSubs then
        row._togBtn:SetSymbol(isCollapsed and "right" or "down")
        row._togBtn:SetAlpha(1.0)
        row._togBtn:Show()
        row._hitBtn:Show()
    else
        row._togBtn:Hide()  -- no sub-tasks: hide the toggle entirely
        row._hitBtn:Hide()
    end

    -- Left-to-right icon chain after togBtn: [R?] [S?]
    local leftAnchor = row._togBtn  -- label anchors to the last icon (or togBtn if none)
    local rst, sit = row._rstIco, row._sitIco
    if task.resetType and task.resetType ~= "" and task.resetType ~= "none" then
        rst:ClearAllPoints()
        rst:SetPoint("LEFT", leftAnchor, "RIGHT", 2, 0)
        rst:SetAlpha(0.8)
        rst:Show()
        leftAnchor = rst
    else
        rst:Hide()
    end
    if task.situation and task.situation ~= "" then
        sit:ClearAllPoints()
        sit:SetPoint("LEFT", leftAnchor, "RIGHT", 2, 0)
        sit:SetAlpha(0.8)
        sit:Show()
        leftAnchor = sit
    else
        sit:Hide()
    end

    local lbl = row._lbl
    lbl:ClearAllPoints()
    lbl:SetPoint("LEFT",  leftAnchor, "RIGHT", 2, 0)
    lbl:SetPoint("RIGHT", row,        "RIGHT", 0, 0)
    local col = BNB.Task.GetTaskColor(task)
    lbl:SetTextColor(col.r, col.g, col.b)
    local stickyLblText = task.text or ""
    if hasSubs and isCollapsed then
        stickyLblText = stickyLblText .. " |cff888888(" .. #subs .. ")|r"
    end
    lbl:SetText(stickyLblText)
end

RenderStickyTasks = function(noteID)
    local f = openFrames[noteID]; if not f or not f._taskContent then return end
    local ct = f._taskContent

    -- Release the pooled rows; reset the hover counter, since rows hidden
    -- under the pointer may never send their OnLeave.
    f._focusHovered = 0
    local pool = ct._pool
    if not pool then pool = {}; ct._pool = pool end
    for _, row in ipairs(pool) do row:Hide() end
    ct._rows = {}

    if not (BNB.Task and BNB.Task.Shows(noteID)) then
        ct:SetHeight(1)
        if f._taskFooterLbl then f._taskFooterLbl:SetText("") end
        return
    end

    -- Row height and gap: focus mode forces compact; otherwise uses global setting
    local _cfg = f._cfg
    local _sp
    if _cfg and _cfg.focusMode then
        _sp = "compact"
    else
        _sp = BigNoteBoxDB and BigNoteBoxDB.taskSpacing or BNB.DEFAULTS.taskSpacing
    end
    local ROW_H, SUB_ROW_H, ROW_GAP
    if _sp == "compact"  then ROW_H, SUB_ROW_H, ROW_GAP = 18, 16, 1
    elseif _sp == "spacious" then ROW_H, SUB_ROW_H, ROW_GAP = 30, 28, 4
    else ROW_H, SUB_ROW_H, ROW_GAP = 22, 20, 2 end
    local collapsed = _stickyCollapsed[noteID] or {}
    _stickyCollapsed[noteID] = collapsed

    local y = -4
    local rows = {}

    local function AddRow(task, depth)
        local i = #rows + 1
        local row = pool[i]
        if not row then row = CreateStickyTaskRow(ct, f); pool[i] = row end
        local rowH = (depth > 0) and SUB_ROW_H or ROW_H
        FillStickyTaskRow(row, noteID, task, depth, y, rowH, collapsed)
        row:Show()
        rows[i] = row
        y = y - rowH - ROW_GAP
        return row
    end

    local topLevel = BNB.Task.GetTopLevel(noteID)
    for _, task in ipairs(topLevel) do
        AddRow(task, 0)
        if not collapsed[task.id] then
            local subs = BNB.Task.GetSubTasks(noteID, task.id)
            for _, sub in ipairs(subs) do
                AddRow(sub, 1)
            end
        end
    end

    local contentH = math.abs(y) + 4
    ct:SetHeight(math.max(contentH, f._taskScroll:GetHeight()))
    ct._rows = rows

    -- Update footer completion counter
    if f._taskFooterLbl then
        local tasks = BNB.Task.GetTasks(noteID)
        local topDone, topTotal = 0, 0
        local subDone, subTotal = 0, 0
        for _, t in ipairs(tasks) do
            if t.parentID then
                subTotal = subTotal + 1
                if t.completed then subDone = subDone + 1 end
            else
                topTotal = topTotal + 1
                if t.completed then topDone = topDone + 1 end
            end
        end
        local allDone = (topTotal > 0 and topDone == topTotal)
            and (subTotal == 0 or subDone == subTotal)
        local txt = topDone .. "/" .. topTotal .. " Tasks"
        if subTotal > 0 then
            txt = txt .. " - " .. subDone .. "/" .. subTotal .. " Sub-tasks"
        end
        f._taskFooterLbl:SetText(txt)
        if allDone then
            f._taskFooterLbl:SetTextColor(0.4, 0.85, 0.4)
        else
            f._taskFooterLbl:SetTextColor(0.65, 0.65, 0.65)
        end
    end

    -- Show/hide global reset and situation icons in footer
    local tl = BNB.Task.GetList(noteID)
    local hasGlobalRst = tl and tl.resetType and tl.resetType ~= "" and tl.resetType ~= "none"
    local hasGlobalSit = tl and tl.situation and tl.situation ~= ""
    if f._taskFtrRstIco then
        if hasGlobalRst then f._taskFtrRstIco:Show() else f._taskFtrRstIco:Hide() end
    end
    if f._taskFtrSitIco then
        if hasGlobalSit then f._taskFtrSitIco:Show() else f._taskFtrSitIco:Hide() end
    end
end

-- Switch the sticky between task view and note view.
-- view = "tasks" or "note". Saves preference to DB.
-- Swap the symbol on a header button built by HdrBtn (an icon button).
local function SetHdrBtnTex(btn, symbol)
    if btn and btn.SetSymbol then btn:SetSymbol(symbol) end
end

local function SN_SetTaskView(noteID, view)
    local f = openFrames[noteID]; if not f then return end
    local showTasks = (view == "tasks") and BNB.Task and BNB.Task.Shows(noteID)

    -- When switching to tasks, render first so content is ready
    if showTasks then
        RenderStickyTasks(noteID)
        f._bodyScroll:Hide()
        f._richScroll:Hide()
        f._taskScroll:Show()
        f._taskFooter:Show()
    else
        f._taskViewActive = false
        f._taskScroll:Hide()
        f._taskFooter:Hide()
        -- Restore note view via RefreshNote (handles plain/rich correctly)
        SN.RefreshNote(noteID)
    end

    f._taskViewActive = showTasks
    SaveStickyView(noteID, showTasks and "tasks" or "note")

    -- Swap the toggle button icon to reflect the view you can switch TO:
    --   showing tasks  -> bt-note  (click will return to note)
    --   showing note   -> bt-tasks (click will go to tasks)
    if f._tasksHdrBtn then
        SetHdrBtnTex(f._tasksHdrBtn, showTasks and "note" or "tasks")
    end
end

-- Expose so SN.Open and external callers can use it after SN is defined.
-- Forward-declared; assigned after SN table exists below.

-- A sticky showing its tasks whose last task went (Clear / Delete, ALL-205)
-- goes back to the note; it was left on an empty task list until reopened.
-- The saved view stays, as for the Tasks switch (SN.ApplyTasksModule), so the
-- sticky opens on its tasks again once it has some. Returns true when it switched.
local function LeaveEmptyTaskView(noteID)
    local f = openFrames[noteID]
    if not (f and f._taskViewActive) then return false end
    if BNB.Task and BNB.Task.Shows(noteID) then return false end
    local rec = StickyDB()[noteID]
    local saved = rec and rec.view
    SN_SetTaskView(noteID, "note")
    rec = StickyDB()[noteID]
    if rec then rec.view = saved end
    return true
end

-- Register TasksChanged callback once so open stickies re-render on data changes.
local function EnsureStickyTaskCallback()
    if _stickyTaskCallbackRegistered then return end
    _stickyTaskCallbackRegistered = true
    BNB.RegisterMessage("StickyNote", "TasksChanged", function(_, changedNoteID)
        local f = changedNoteID and openFrames[changedNoteID]
        if not f then return end
        if f._taskViewActive and not LeaveEmptyTaskView(changedNoteID) then
            RenderStickyTasks(changedNoteID)
        end
        -- Also update the tasks button tooltip state dynamically (via OnEnter)
    end)
end

-- ── Inline editing ────────────────────────────────────────────────────────────
-- Double-click the body of a plain note to edit it in the sticky. Rich notes,
-- and rich notes shown as plain text (markup stripped, so saving the visible
-- text would destroy it), open in the main window instead, as do locked notes.
-- Saves once, when editing ends: Escape, a click outside the sticky, the body
-- hiding (minimize, close, task view) or logout. On by default; turned off by
-- BigNoteBoxDB.stickyInlineEdit == false.
local EDIT_GLOW_KEY   = "bnbStickyEdit"
local EDIT_GLOW_COLOR = { 0.400, 0.733, 0.416, 1 }  -- BNB green, the alarm glow default
local DBLCLICK_TIME   = 0.35

local _editLCG
local function GetEditLCG()
    if not _editLCG then _editLCG = LibStub and LibStub("LibCustomGlow-1.0", true) end
    return _editLCG
end

-- Same rule as NoteIsLocked in NoteEditor.lua
local function StickyNoteIsLocked(note)
    if note.locked == true  then return true  end
    if note.locked == false then return false end
    return BigNoteBoxDB and BigNoteBoxDB.lockNotes == true
end

-- Title row: a lock before the title on locked notes, as in the note list.
-- f._titleLeft is the offset BuildIconBadge returned (clears the icon badge).
local TITLE_LOCK_SZ    = 14
local TITLE_LOCK_ALPHA = 0.65
local function LayoutStickyTitle(f, note)
    local lbl, hdr = f._titleLbl, f._headerBar
    if not (lbl and hdr) then return end
    local left = f._titleLeft or PAD
    local lock = f._titleLock
    if lock then
        if note and StickyNoteIsLocked(note) then
            lock:ClearAllPoints()
            lock:SetPoint("LEFT", hdr, "LEFT", left, 0)
            lock:Show()
            left = left + TITLE_LOCK_SZ + 3
        else
            lock:Hide()
        end
    end
    lbl:ClearAllPoints()
    lbl:SetPoint("LEFT",  hdr, "LEFT",  left, 0)
    lbl:SetPoint("RIGHT", hdr, "RIGHT", -PAD, 0)
end

-- Open the note in the main window with the cursor in the body, ready to type.
-- A rich note in view mode is switched to edit mode first.
local function OpenInMainEditor(noteID)
    CloseESCAndDo(function()
        if InCombatLockdown() then BNB:Print(L["STICKY_COMBAT"]); return end
        if not BNB.mainFrame then
            if BNB.CreateMainWindow then BNB.CreateMainWindow() end
        end
        if not BNB.mainFrame then return end
        BNB.mainFrame:Show()
        if BNB.SelectNote      then BNB.SelectNote(noteID) end
        -- SelectNote refuses the switch when the current note has no title
        if BNB._currentNoteID ~= noteID then return end
        if BNB._editorInViewMode and not BNB._editorLocked and BNB.AM_EnterEditMode then
            BNB.AM_EnterEditMode()
        end
        -- Same one-tick delay as the Quick Note button; cursor at the end.
        C_Timer.After(0.05, function()
            local eb = BNB._editorBody
            if eb and not BNB._editorLocked and BNB._currentNoteID == noteID then
                eb:SetFocus()
                eb:SetCursorPosition(#(eb:GetText() or ""))
            end
        end)
    end)
end

local function EndInlineEdit(f)
    if not (f and f._inlineEditing) then return end
    f._inlineEditing = false   -- cleared first: ClearFocus below re-enters via OnEditFocusLost
    local eb, noteID = f._bodyEb, f._noteID
    local lcg = GetEditLCG()
    if lcg then pcall(lcg.PixelGlow_Stop, f, EDIT_GLOW_KEY) end
    eb:ClearFocus()
    eb:SetEnabled(false)
    eb:SetScript("OnCursorChanged", nil)

    local note = BNB.GetNote(noteID)
    local text = eb:GetText() or ""
    -- A quick-note sticky (SN.OpenQuick) left empty on its first edit is
    -- removed outright: no trash, no note list entry. Deferred a tick when
    -- SN.Close is what ended the edit, so the purge's own Close cannot nest
    -- inside it; at logout there is no next tick, so it runs now.
    if f._quickNew then
        f._quickNew = nil
        if note and text:match("^%s*$") then
            local function Purge()
                if not BNB.GetNote(noteID) then return end
                BNB.PurgeNote(noteID)
                local db = DB()
                if db and db.postits then db.postits[noteID] = nil end
                if BNB.mainFrame and BNB.mainFrame:IsShown() and BNB.RefreshNoteList then
                    pcall(BNB.RefreshNoteList)
                end
            end
            if f._loggingOut then Purge() else C_Timer.After(0, Purge) end
            return
        end
    end
    if not note or text == (note.body or "") then return end
    BNB.UpdateNote(noteID, { body = text })
    -- Keep the main window in step when it holds this note
    if BNB._currentNoteID == noteID and BNB._editorBody and BNB.LoadNoteInEditor then
        pcall(BNB.LoadNoteInEditor, noteID)
    end
    if BNB.mainFrame and BNB.mainFrame:IsShown() and BNB.RefreshNoteList then
        pcall(BNB.RefreshNoteList)
    end
end

local function StartInlineEdit(f)
    local noteID = f._noteID
    local note = BNB.GetNote(noteID)
    if not note or f._inlineEditing or f._taskViewActive or f._minimized then return end

    local cfg  = GetCfg(noteID)
    local rich = BNB.AdvancedMode and BNB.AdvancedMode.IsRich(note)
    if not rich and cfg.richPlainText and BNB.AdvancedMode and BNB.AdvancedMode.StripMarkup then
        local body = note.body or ""
        rich = BNB.AdvancedMode.StripMarkup(body) ~= body
    end
    if rich or StickyNoteIsLocked(note) then OpenInMainEditor(noteID); return end

    -- Unsaved edits to this note in the main window go in first, so neither
    -- side overwrites the other. A failed save (no title) stops here.
    if BNB._currentNoteID == noteID and BNB._dirty and BNB.SaveCurrentNote then
        BNB.SaveCurrentNote()
        if BNB._dirty then return end
    end

    f._inlineEditing = true
    local eb = f._bodyEb
    if eb:GetText() ~= (note.body or "") then eb:SetText(note.body or "") end
    eb:SetEnabled(true)
    if f._cursorFollow then eb:SetScript("OnCursorChanged", f._cursorFollow) end
    eb:SetFocus()
    eb:SetCursorPosition(#(eb:GetText() or ""))
    local lcg = GetEditLCG()
    if lcg then
        pcall(lcg.PixelGlow_Start, f, EDIT_GLOW_COLOR, 8, 0.10, 10,
              nil, nil, nil, nil, EDIT_GLOW_KEY)
    end
end

-- A click anywhere outside an editing sticky ends the edit (via focus loss).
local _editWatch = CreateFrame("Frame")
_editWatch:SetScript("OnEvent", function()
    for _, f in pairs(openFrames) do
        if f._inlineEditing and not f:IsMouseOver() then
            f._bodyEb:ClearFocus()
        end
    end
end)
pcall(_editWatch.RegisterEvent, _editWatch, "GLOBAL_MOUSE_DOWN")

-- Logout saves any edit still open. Through BNB.RegisterEvent so it runs
-- before NoteHistory's logout snapshot, which then holds the new text.
BNB.RegisterEvent("PLAYER_LOGOUT", function()
    for _, f in pairs(openFrames) do
        f._loggingOut = true
        -- xpcall so a failed save is reported, not swallowed (SV-02)
        xpcall(function() EndInlineEdit(f) end, geterrorhandler())
    end
end)

-- ── Build a sticky note frame ─────────────────────────────────────────────────
local function CreateStickyFrame(noteID)
    local note = BNB.GetNote(noteID)
    if not note then return nil end

    local f = BNB.CreateBackdropFrame("Frame", nil, UIParent)
    f:SetFrameStrata(SN.Strata())
    f:SetToplevel(true)
    f:SetMovable(true)
    f:SetResizable(true)
    f:SetResizeBounds(MIN_W, MIN_H, 1200, 800)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if not StickyLocked(noteID) then self:StartMoving() end
    end)
    f:SetScript("OnDragStop",  function(self)
        self:StopMovingOrSizing(); SaveGeometry(noteID, self)
    end)
    BNB.SetBackdrop(f, COL_BG[1], COL_BG[2], COL_BG[3], 0.97,
        COL_BORDER[1], COL_BORDER[2], COL_BORDER[3], 1)

    -- ── FRONT face ────────────────────────────────────────────────────────────
    local front = CreateFrame("Frame", nil, f)
    front:SetAllPoints()
    f._frontFace = front
    ForwardHover(front, f)

    -- ── Header ────────────────────────────────────────────────────────────────
    -- Sits just inside the top border edge with a small padding gap.
    -- Left/right also inset to clear the side borders.
    -- The icon badge overhangs the top-left corner independently — untouched.
    local header = BNB.CreateBackdropFrame("Frame", nil, front)
    header:SetPoint("TOPLEFT",  f, "TOPLEFT",   HEADER_BORDER_PAD, -HEADER_BORDER_PAD)
    header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -HEADER_BORDER_PAD, -HEADER_BORDER_PAD)
    header:SetHeight(HEADER_H)
    -- Transparent background — the frame border shows cleanly, title text floats
    -- over the note body colour. No backdrop needed; drag still works via EnableMouse.
    if header.SetBackdrop then
        pcall(function() header:SetBackdrop(nil) end)
    end
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        if not StickyLocked(noteID) then f:StartMoving() end
    end)
    header:SetScript("OnDragStop",  function()
        f:StopMovingOrSizing(); SaveGeometry(noteID, f)
    end)
    ForwardHover(header, f)
    f._headerBar = header
    -- ALL-95, after ForwardHover (it uses SetScript); no move cursor while
    -- the sticky is locked (ALL-257)
    BNB.SetHoverCursor(header, function()
        if not StickyLocked(noteID) then return "move" end
    end)

    -- ── Overhanging icon badge ────────────────────────────────────────────────
    local titleLeft = BuildIconBadge(f, noteID, note)

    -- Header title — spans the full header width so the title text uses all
    -- available space. The icon button overlay will float above it on hover.
    local titleLbl = header:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    titleLbl:SetPoint("LEFT",  header, "LEFT",  titleLeft, 0)
    titleLbl:SetPoint("RIGHT", header, "RIGHT", -PAD, 0)
    titleLbl:SetJustifyH("LEFT"); titleLbl:SetMaxLines(1); titleLbl:SetWordWrap(false)
    -- Header font size (bump this value to change the sticky note title size)
    -- A font object, not a raw SetFont(GetFont(), 16): GetFont() returns only the
    -- Latin file, and setting it raw drops the per-alphabet fallback, so a Chinese
    -- or Korean note title drew as boxes. GameFontNormalLarge is the 16px sibling.
    titleLbl:SetFontObject("GameFontNormalLarge")
    local tc = note.titleColor
    if tc then titleLbl:SetTextColor(tc.r, tc.g, tc.b, 1)
    else        titleLbl:SetTextColor(unpack(COL_GOLD)) end
    titleLbl:SetText(note.title ~= "" and note.title or L["UNTITLED"])
    f._titleLbl = titleLbl

    -- Lock before the title on locked notes (same asset as the note list)
    local titleLock = header:CreateTexture(nil, "ARTWORK")
    titleLock:SetSize(TITLE_LOCK_SZ, TITLE_LOCK_SZ)
    titleLock:SetTexture("Interface\\AddOns\\BigNoteBox\\Assets\\" .. BNB.AbIcon("lock"))
    titleLock:SetAlpha(TITLE_LOCK_ALPHA)
    titleLock:Hide()
    f._titleLock  = titleLock
    f._titleLeft  = titleLeft
    LayoutStickyTitle(f, note)

    -- ── Icon button overlay ───────────────────────────────────────────────────
    -- A container frame that holds all header icon buttons, parented to the header
    -- at OVERLAY frame level so it renders above the title text.
    -- Starts hidden (alpha 0); fades in/out over 0.1 s when the root is hovered.
    local BTN_SZ = 25   -- smaller than HEADER_H (28) for a less chunky look

    local btnOverlay = CreateFrame("Frame", nil, header)
    btnOverlay:SetPoint("TOPLEFT",  header, "TOPLEFT",  0, 0)
    btnOverlay:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, 0)
    btnOverlay:SetHeight(HEADER_H)
    btnOverlay:SetFrameLevel(header:GetFrameLevel() + 4)
    f._btnOverlay = btnOverlay

    -- Button children do NOT inherit alpha from a parent Frame in WoW --
    -- each Button has its own independent alpha. We keep a table of every
    -- header button and set their alpha directly.
    -- We do NOT fade buttons with OnUpdate: SetScript("OnUpdate") on a
    -- Button conflicts with WoW's internal click dispatch and causes the wrong
    -- OnClick to fire. Direct SetAlpha is instant and reliable.
    local _hdrBtns = {}

    local function FadeBtns(toAlpha)
        for _, btn in ipairs(_hdrBtns) do
            btn:SetAlpha(toAlpha)
        end
    end

    -- Start all buttons hidden
    -- (registered into _hdrBtns at end of HdrBtn factory below)

    -- Gap between buttons and right edge, and between buttons
    local BTN_GAP  = 1
    local BTN_RIGHT_PAD = 1

    -- Icon button factory (right-to-left slot numbering, slot 1 = rightmost).
    -- Icon buttons (UI/IconButton.lua), skin look in skin mode (Dukul 2026-10-03).
    local function HdrBtn(slot, symbol, tip, onClick)
        local btn = BNB.CreateIconButton(btnOverlay, BTN_SZ, symbol, { onClick = onClick,
            tip = function(self)
                if self._dynTip then return self._dynTip() end
                if self == f._alarmHdrBtn then
                    local n = BNB.GetNote and BNB.GetNote(noteID)
                    return (n and n.alarm) and L["STICKY_EDIT_ALARM_TIP"] or L["STICKY_SET_ALARM_TIP"]
                end
                return tip
            end })
        -- Placed by f._layoutHdrBtns (right-aligned, hidden ones leave no gap)
        btn._slot = slot
        btn:SetFrameLevel(btnOverlay:GetFrameLevel() + 1)

        -- Start hidden; will be shown by FadeBtns when root is hovered
        btn:SetAlpha(0)
        table.insert(_hdrBtns, btn)

        -- keep all buttons visible while any button is hovered
        btn:HookScript("OnEnter", function() FadeBtns(1) end)
        return btn
    end

    -- slot 1 = close, slot 2 = minimize, slot 3 = settings, slot 4 = edit
    HdrBtn(1, "close", L["STICKY_UNPIN_TIP"], function() SN.Close(noteID) end)

    local minBtn = HdrBtn(2, "minimize", L["STICKY_MINIMIZE_TO_ICON_TIP"], function()
        SN.SetMinimized(noteID, not f._minimized)
    end)
    f._minBtn = minBtn

    HdrBtn(3, "settings", L["STICKY_SETTINGS_MENU"], function()
        -- Do NOT close the ESC menu here — settings open alongside the sticky
        -- so the user can see their changes live (OpenStickySettings raises
        -- the settings panel strata above GameMenuFrame automatically).
        if f._minimized then SN.SetMinimized(noteID, false); return end
        if SN._IsSettingsOpenFor(noteID) then
            SN.CloseSettings()
        else
            SN._OpenSettings(f, noteID)
        end
    end)

    HdrBtn(4, "edit", L["STICKY_OPEN_TO_EDIT_TIP"], function()
        -- Ends (and saves) an inline edit first, so BNB opens on the new text
        EndInlineEdit(f)
        OpenInMainEditor(noteID)
    end)

    -- slot 5 = alarm: opens alarm setter window anchored to this button
    -- Assets: Assets/UI/sn-alarm-normal.tga + sn-alarm-hover.tga
    local alarmHdrBtn = HdrBtn(5, "alarm", L["STICKY_SET_ALARM_TIP"], function()
        local note = BNB.GetNote and BNB.GetNote(noteID)
        local alarm = note and note.alarm
        -- If alarm glow is actively running, clicking the button dismisses it.
        -- Otherwise open the alarm window as normal.
        if alarm and not alarm.fired
           and BNB.Alarm and BNB.Alarm.IsAlarmActive and BNB.Alarm.IsAlarmActive(noteID) then
            BNB.Alarm.Dismiss(noteID)
            return
        end
        if BNB.AlarmWindow and BNB.AlarmWindow.Open then
            -- f._alarmHdrBtn: the local below is not in scope inside its own
            -- initialiser, so alarmHdrBtn here was a nil global
            BNB.AlarmWindow.Open(noteID, f._alarmHdrBtn, f)
        end
    end)
    f._alarmHdrBtn = alarmHdrBtn

    -- slot 6 = tasks: toggle task view / create first task
    local tasksHdrBtn = HdrBtn(6, "tasks", L["STICKY_CREATE_TASK_TIP"], function()
        local hasTasks = BNB.Task and BNB.Task.HasTasks(noteID)
        if not hasTasks then
            -- No tasks: close ESC menu, open main window, select note, open RefBox, add task
            CloseESCAndDo(function()
                if not BNB.mainFrame then
                    if BNB.CreateMainWindow then BNB.CreateMainWindow() end
                end
                if BNB.mainFrame then
                    BNB.mainFrame:Show()
                    if BNB.SelectNote      then BNB.SelectNote(noteID) end
                end
                local taskID = BNB.Task and BNB.Task.AddTask(noteID, "")
                if taskID then
                    if BNB.OpenReferenceBox then BNB.OpenReferenceBox(noteID) end
                    C_Timer.After(0.2, function()
                        if BNB.FocusTaskEditBox then BNB.FocusTaskEditBox(taskID) end
                    end)
                end
            end)
        else
            -- Has tasks: toggle between task view and note view (self-contained, no ESC close)
            local newView = f._taskViewActive and "note" or "tasks"
            SN_SetTaskView(noteID, newView)
        end
    end)
    tasksHdrBtn:SetScript("OnEnter", function(self)
        local hasTasks = BNB.Task and BNB.Task.HasTasks(noteID)
        local tip
        if not hasTasks then
            tip = L["STICKY_CREATE_TASK_TIP"]
        elseif f._taskViewActive then
            tip = L["STICKY_SHOW_NOTE_TIP"]
        else
            tip = L["STICKY_SHOW_TASKS_TIP"]
        end
        FadeBtns(1)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(tip, 1, 1, 1)
        GameTooltip:Show()
    end)
    f._tasksHdrBtn = tasksHdrBtn

    -- slot 7 = view: a rich note shown as rich text or as plain text, the
    -- sticky's own "Plain text" setting (cfg.richPlainText, ALL-357). The
    -- symbol and tip say what a click gives. Rich notes only.
    local function ShowsPlain()
        local c = (SN._SettingsCfg and SN._SettingsCfg(noteID)) or GetCfg(noteID)
        return c.richPlainText == true
    end
    local viewHdrBtn = HdrBtn(7, "normal", L["STICKY_VIEW_AS_NORMAL_TIP"], function()
        SN.SetPlainView(noteID, not ShowsPlain())
    end)
    viewHdrBtn._dynTip = function()
        return ShowsPlain() and L["STICKY_VIEW_AS_RICH_TIP"] or L["STICKY_VIEW_AS_NORMAL_TIP"]
    end
    f._syncViewBtn = function()
        local plain = ShowsPlain()
        viewHdrBtn:SetSymbol(plain and "rich" or "normal")
    end
    f._syncViewBtn()

    -- Settings > Modules > Sticky Notes can hide every button but Close
    -- (stickyHideBtn, ALL-266, minimize and view since ALL-357); the
    -- right-click menu keeps them all. Tasks also hides while the Tasks
    -- module is off (ALL-102), view on a note that is not rich.
    _hdrBtns[3]._hideKey, _hdrBtns[4]._hideKey = "settings", "edit"
    alarmHdrBtn._hideKey, tasksHdrBtn._hideKey = "alarm", "tasks"
    minBtn._hideKey, viewHdrBtn._hideKey = "minimize", "view"
    -- Right-aligned, slot order, hidden buttons leave no gap. Single anchor
    -- so SetSize is respected (two anchors stretch the button).
    f._layoutHdrBtns = function()
        local n = 0
        for _, btn in ipairs(_hdrBtns) do
            local show = not (btn._hideKey and SN.HdrBtnHidden(btn._hideKey))
            if btn == tasksHdrBtn and not BNB.TasksEnabled() then show = false end
            if btn == viewHdrBtn then
                local n = BNB.GetNote(noteID)
                if not (n and n.richMode == true) then show = false end
                if show then f._syncViewBtn() end
            end
            btn:ClearAllPoints()
            if show then
                btn:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT",
                    -BTN_RIGHT_PAD - n * (BTN_SZ + BTN_GAP), (HEADER_H - BTN_SZ) / 2)
                n = n + 1
            end
            btn:SetShown(show)
        end
    end
    f._layoutHdrBtns()

    -- ── Right-click context menu (ALL-83) ─────────────────────────────────────
    -- Same entries as the header buttons: Open in editor, Settings, Set/Edit
    -- alarm, Show tasks/note, then a divider, Minimize, Close.
    local function ShowStickyContextMenu(anchor)
        BNB.ContextMenu.Open(anchor, function(root)   -- ALL-148
            root:CreateButton(L["STICKY_OPEN_TO_EDIT_TIP"], function()
                EndInlineEdit(f)
                OpenInMainEditor(noteID)
            end)
            root:CreateButton(L["STICKY_SETTINGS_MENU"], function()
                -- Minimized: restore, then open the settings beside the shown
                -- sticky one frame later (ALL-144; it used to stop at restore)
                if f._minimized then
                    SN.SetMinimized(noteID, false)
                    C_Timer.After(0, function()
                        if f:IsShown() and not SN._IsSettingsOpenFor(noteID) then
                            SN._OpenSettings(f, noteID)
                        end
                    end)
                    return
                end
                if SN._IsSettingsOpenFor(noteID) then
                    SN.CloseSettings()
                else
                    SN._OpenSettings(f, noteID)
                end
            end)
            do
                local n = BNB.GetNote and BNB.GetNote(noteID)
                local alarm = n and n.alarm
                local label = alarm and L["STICKY_EDIT_ALARM_TIP"] or L["STICKY_SET_ALARM_TIP"]
                root:CreateButton(label, function()
                    if alarm and not alarm.fired and BNB.Alarm and BNB.Alarm.IsAlarmActive
                       and BNB.Alarm.IsAlarmActive(noteID) then
                        BNB.Alarm.Dismiss(noteID)
                        return
                    end
                    if BNB.AlarmWindow and BNB.AlarmWindow.Open then
                        BNB.AlarmWindow.Open(noteID, f._alarmHdrBtn, f)
                    end
                end)
            end
            if BNB.TasksEnabled() then   -- ALL-102
                local hasTasks = BNB.Task and BNB.Task.HasTasks(noteID)
                local label
                if not hasTasks then label = L["STICKY_CREATE_TASK_TIP"]
                elseif f._taskViewActive then label = L["STICKY_SHOW_NOTE_TIP"]
                else label = L["STICKY_SHOW_TASKS_TIP"] end
                root:CreateButton(label, function()
                    if not hasTasks then
                        CloseESCAndDo(function()
                            if not BNB.mainFrame then
                                if BNB.CreateMainWindow then BNB.CreateMainWindow() end
                            end
                            if BNB.mainFrame then
                                BNB.mainFrame:Show()
                                if BNB.SelectNote      then BNB.SelectNote(noteID) end
                            end
                            local taskID = BNB.Task and BNB.Task.AddTask(noteID, "")
                            if taskID then
                                if BNB.OpenReferenceBox then BNB.OpenReferenceBox(noteID) end
                                C_Timer.After(0.2, function()
                                    if BNB.FocusTaskEditBox then BNB.FocusTaskEditBox(taskID) end
                                end)
                            end
                        end)
                    else
                        -- Restore first so the toggled view is visible (from
                        -- the mini-tile menu, the note starts hidden).
                        if f._minimized then SN.SetMinimized(noteID, false) end
                        local newView = f._taskViewActive and "note" or "tasks"
                        SN_SetTaskView(noteID, newView)
                    end
                end)
            end
            root:CreateDivider()
            -- Lock sticky: position and size (ALL-257)
            local locked = StickyLocked(noteID)
            root:CreateButton(locked and L["STICKY_UNLOCK_LABEL"] or L["STICKY_LOCK_LABEL"], function()
                SN.SetLocked(noteID, not locked)
            end, { tip = L["STICKY_LOCK_TIP"] })
            root:CreateButton(f._minimized and L["STICKY_RESTORE_TIP"] or L["STICKY_MINIMIZE_TO_ICON_TIP"], function()
                SN.SetMinimized(noteID, not f._minimized)
            end)
            root:CreateButton(L["STICKY_CTX_CLOSE"], function()
                SN.Close(noteID)
            end)
        end)
    end
    f._showStickyCtxMenu = ShowStickyContextMenu

    header:SetScript("OnMouseUp", function(self, mouseBtn)
        if mouseBtn == "RightButton" then ShowStickyContextMenu(header) end
    end)
    -- OnEnter/OnLeave on the root are unreliable when the frame is fully covered
    -- by child frames (front, header, body) — the cursor may never "touch" the
    -- root's own hit rect, so Leave events can be swallowed.  Polling each frame
    -- is the standard WoW pattern for this; the IsMouseOver call is near-free.
    local _btnsShown  = false
    local _focusLerp  = 1.0   -- 1.0 = full header visible, 0.0 = fully hidden
    local _focusTarget = 1.0  -- target for the lerp
    local FOCUS_SPEED  = 6.0  -- units per second (lower = slower)
    -- Counter incremented by HookFocusHover on task row children so that
    -- IsMouseOver gaps between rows don't falsely signal "not hovered".
    f._focusHovered = 0

    f:HookScript("OnUpdate", function(self, elapsed)
        -- Inline editing counts as hovered: buttons and header stay visible
        local over = f._inlineEditing or f:IsMouseOver() or (f._focusHovered and f._focusHovered > 0)
        local cfg  = f._cfg
        local focusMode = cfg and cfg.focusMode

        -- ── Background / text hover fade (acts on a change only) ─────────────
        if over ~= f._bgHover then
            f._bgHover = over
            HoverBgAlpha(f, over)
        end

        -- ── Button fade ───────────────────────────────────────────────────────
        if over and not _btnsShown then
            _btnsShown = true
            FadeBtns(1)
        elseif not over and _btnsShown then
            _btnsShown = false
            FadeBtns(0)
        end

        -- ── Focus mode header lerp ────────────────────────────────────────────
        if focusMode then
            _focusTarget = over and 1.0 or 0.0
        else
            _focusTarget = 1.0
        end

        if _focusLerp ~= _focusTarget then
            local delta = elapsed * FOCUS_SPEED
            if _focusLerp < _focusTarget then
                _focusLerp = math.min(_focusTarget, _focusLerp + delta)
            else
                _focusLerp = math.max(_focusTarget, _focusLerp - delta)
            end

            -- Animate header height
            local hdr = f._headerBar
            local h = math.floor(_focusLerp * HEADER_H + 0.5)
            if hdr then
                hdr:SetHeight(math.max(0, h))
            end

            -- Slide visible scroll frame TOPLEFT to track header height.
            -- Scroll frames are anchored to front (not header) so we must
            -- update the y-offset explicitly as the header grows/shrinks.
            -- ClearAllPoints is safe here because it only runs during the
            -- short lerp animation, and both anchor points are re-set.
            local fp = FOCUS_PAD
            local vis = f._taskViewActive and f._taskScroll
                     or (f._richScroll and f._richScroll:IsShown() and f._richScroll)
                     or f._bodyScroll
            if vis and f._frontFace then
                local botY = fp
                if vis == f._taskScroll then botY = fp + TASK_FOOTER_H + 2 end
                vis:ClearAllPoints()
                AnchorScrollTop(vis, f._frontFace, h, fp)
                vis:SetPoint("BOTTOMRIGHT", f._frontFace, "BOTTOMRIGHT", -(fp+22), botY)
            end

            -- Animate title, icon, task footer, and scrollbar alpha
            if f._titleLbl   then f._titleLbl:SetAlpha(_focusLerp) end
            if f._titleLock  then f._titleLock:SetAlpha(_focusLerp * TITLE_LOCK_ALPHA) end
            if f._iconFrame  then f._iconFrame:SetAlpha(_focusLerp) end
            if f._taskFooter then f._taskFooter:SetAlpha(_focusLerp) end
            if f._bodySB then f._bodySB:SetAlpha(_focusLerp * (f._bodySB._hasRange and 1 or 0)) end
            if f._richSB then f._richSB:SetAlpha(_focusLerp * (f._richSB._hasRange and 1 or 0)) end
            if f._taskSB then f._taskSB:SetAlpha(_focusLerp * (f._taskSB._hasRange and 1 or 0)) end

            -- Animate border alpha (no closure per frame, PERF-08)
            if cfg then
                local note = BNB.GetNote(f._noteID)
                local effectiveBorder = cfg.borderName or (note and note.borderOverride)
                if effectiveBorder and effectiveBorder ~= "" and effectiveBorder ~= "None" then
                    SetStickyBorder(f, cfg, _focusLerp)
                end
            end
        end

        -- ── Resize handle ─────────────────────────────────────────────────────
        local rh = f._resizeHandle
        if rh then
            local shouldShow = (over or rh._sizing) and not f._minimized
                and not StickyLocked(f._noteID)
            if shouldShow and not rh:IsShown() then rh:Show()
            elseif not shouldShow and rh:IsShown() then rh:Hide() end
        end
    end)

    -- Store lerp state on frame so ApplyConfig can reset it
    f._focusLerp   = function() return _focusLerp end
    f._setFocusLerp = function(v)
        _focusLerp  = v
        _focusTarget = v
    end

    -- ── Body scroll ───────────────────────────────────────────────────────────
    local sf2, bodyEb = BNB.CreateScrolledEditBox(
        "BigNoteBoxSN_" .. noteID:gsub("-", ""):sub(1, 10),
        front, (BigNoteBoxDB and BigNoteBoxDB.fontSize) or BNB.DEFAULTS.fontSize)
    sf2:SetPoint("TOPLEFT",     front, "TOPLEFT",    HEADER_BORDER_PAD + PAD, -(HEADER_BORDER_PAD + HEADER_H + PAD))
    sf2:SetPoint("BOTTOMRIGHT", front,  "BOTTOMRIGHT", -(PAD+22),  PAD)
    f._bodyScroll = sf2
    f._bodyEb     = bodyEb
    bodyEb:SetEnabled(false)
    bodyEb:SetAlpha(0.90)
    -- Sticky note body is read-only — disable OnCursorChanged so SetText
    -- doesn't auto-scroll to the cursor position (which ends up mid-note).
    -- Kept on the frame so inline editing can turn cursor-follow back on.
    f._cursorFollow = bodyEb:GetScript("OnCursorChanged")
    bodyEb:SetScript("OnCursorChanged", nil)
    bodyEb:HookScript("OnEditFocusLost", function() EndInlineEdit(f) end)
    -- Esc or Ctrl+Enter ends an inline edit, saved like a click outside
    -- (Dukul, 2026-10-02). Plain Enter stays a new line: a multi-line EditBox
    -- types the newline itself only while it has no OnEnterPressed, so with
    -- this handler the newline is inserted here. Ctrl+Enter types nothing.
    bodyEb:HookScript("OnEscapePressed", function() EndInlineEdit(f) end)
    bodyEb:HookScript("OnEnterPressed", function(self)
        if not f._inlineEditing then return end
        if IsControlKeyDown() then
            EndInlineEdit(f)
        else
            self:Insert("\n")
        end
    end)
    -- Minimize, close, task view and HideAll all hide the body: end the edit
    sf2:HookScript("OnHide", function() EndInlineEdit(f) end)
    ForwardHover(sf2, f)
    ForwardHover(bodyEb, f)
    -- ScrollFrameTemplate scrollbar has nested children (track, thumb, buttons)
    -- that all need hover forwarding. Recurse through them all.
    local function ForwardHoverRecursive(frame, root)
        ForwardHover(frame, root)
        for _, child in ipairs({frame:GetChildren()}) do
            pcall(function() ForwardHoverRecursive(child, root) end)
        end
    end
    if sf2.ScrollBar then
        pcall(function() ForwardHoverRecursive(sf2.ScrollBar, f) end)
        -- Dim the scrollbar when there is nothing to scroll, restore when needed.
        -- Uses alpha only — never Show/Hide, which fights ScrollFrameTemplate.
        -- _hasRange tracks whether content is scrollable so the focus lerp can
        -- multiply against it rather than setting alpha directly here.
        sf2.ScrollBar:SetAlpha(0)
        sf2.ScrollBar._hasRange = false
        sf2:HookScript("OnScrollRangeChanged", function(_, _, yRange)
            if sf2.ScrollBar then
                sf2.ScrollBar._hasRange = (yRange or 0) > 1
                -- Alpha is now driven by OnUpdate when in focus mode.
                -- In normal mode set it directly here as before.
                local fm = f._cfg and f._cfg.focusMode
                if not fm then
                    sf2.ScrollBar:SetAlpha(sf2.ScrollBar._hasRange and 1.0 or 0)
                end
            end
        end)
        f._bodySB = sf2.ScrollBar
    end

    -- ── Rich render scroll frame ──────────────────────────────────────────────
    -- Sibling to _bodyScroll; identical anchors. Shown only for rich notes.
    -- SimpleHTML must be in a proper Frame scroll child — parenting to an
    -- EditBox is unreliable and causes raw markup to show instead of rendering.
    local richScroll = BNB.CreateScrollFrame(nil, front)
    richScroll:SetPoint("TOPLEFT",     front, "TOPLEFT",    HEADER_BORDER_PAD + PAD, -(HEADER_BORDER_PAD + HEADER_H + PAD))
    richScroll:SetPoint("BOTTOMRIGHT", front,  "BOTTOMRIGHT", -(PAD+22),  PAD)
    richScroll:Hide()
    f._richScroll = richScroll

    local richSB = richScroll.ScrollBar
    if richSB then
        richSB:SetAlpha(0)
        richSB._hasRange = false
        richScroll:HookScript("OnScrollRangeChanged", function(_, _, yRange)
            richSB._hasRange = (yRange or 0) > 1
            local fm = f._cfg and f._cfg.focusMode
            if not fm then
                richSB:SetAlpha(richSB._hasRange and 1.0 or 0)
            end
        end)
        pcall(function() ForwardHoverRecursive(richSB, f) end)
        f._richSB = richSB
    end

    local richRender = BNB.AdvancedMode.CreateRenderFrame(nil, richScroll)
    richRender:SetWidth(1); richRender:SetHeight(1)
    richScroll:SetScrollChild(richRender)
    f._richRender = richRender

    -- Keep render frame width synced with scroll frame so SimpleHTML reflows.
    -- Also re-renders on resize so content wraps correctly at the new width.
    richScroll:SetScript("OnSizeChanged", function(self)
        local w = self:GetWidth()
        if not w or w <= 0 then return end
        richRender:SetWidth(w)
        -- Re-render if a rich note is currently loaded (handles window resize)
        if f._richNoteID and richScroll:IsShown() then
            local rn = BNB.GetNote(f._richNoteID)
            if rn then
                local bs = rn.fontSize or (BigNoteBoxDB and BigNoteBoxDB.fontSize) or BNB.DEFAULTS.fontSize
                local fs = BNB.AdvancedMode.OutlineFlagStr(rn.fontOutline)
                BNB.AdvancedMode.ApplyFontsToRenderFrame(richRender, bs, fs)
                local rawST = getmetatable(richRender).__index.SetText
                rawST(richRender, BNB.AdvancedMode.ToHTML(rn.body or "", bs))
                richRender:SetHeight(richRender:GetContentHeight())
            end
        end
    end)

    ForwardHover(richScroll, f)

    -- Double-click on the body starts an inline edit (StartInlineEdit sends rich
    -- and locked notes to the main window). EditBox and ScrollFrame have no
    -- OnDoubleClick, so two left presses within DBLCLICK_TIME count as one.
    local function OnBodyMouseDown(_, button)
        if button ~= "LeftButton" or f._inlineEditing then return end
        local now = GetTime()
        if f._lastBodyClick and now - f._lastBodyClick <= DBLCLICK_TIME then
            f._lastBodyClick = nil
            if BigNoteBoxDB and BigNoteBoxDB.stickyInlineEdit == false then return end
            StartInlineEdit(f)
        else
            f._lastBodyClick = now
        end
    end
    bodyEb:HookScript("OnMouseDown", OnBodyMouseDown)
    sf2:HookScript("OnMouseDown", OnBodyMouseDown)
    richScroll:HookScript("OnMouseDown", OnBodyMouseDown)
    richRender:HookScript("OnMouseDown", OnBodyMouseDown)

    -- Right-click on the body (ALL-83). OnMouseDown above only reacts to
    -- LeftButton, so this cannot interfere with the double-click-to-edit timer.
    local function OnBodyMouseUp(_, button)
        if button == "RightButton" then ShowStickyContextMenu(bodyEb) end
    end
    bodyEb:HookScript("OnMouseUp", OnBodyMouseUp)
    sf2:HookScript("OnMouseUp", OnBodyMouseUp)
    -- ALL-95: the lock cursor over a locked note's text
    local function LockKind()
        local note = f._noteID and BNB.GetNote(f._noteID)
        if note and StickyNoteIsLocked(note) then return "lock" end
    end
    BNB.SetHoverCursor(bodyEb, LockKind)
    BNB.SetHoverCursor(sf2, LockKind)
    BNB.SetHoverCursor(richScroll, LockKind)   -- rich view too (ALL-239)
    BNB.SetHoverCursor(richRender, LockKind)
    richScroll:HookScript("OnMouseUp", OnBodyMouseUp)
    richRender:HookScript("OnMouseUp", OnBodyMouseUp)

    -- ── Task scroll frame ─────────────────────────────────────────────────────
    -- Sibling to _bodyScroll and _richScroll. Shown only when task view is active.
    -- Anchored identically to _bodyScroll but bottom leaves room for the footer.
    local taskScroll = BNB.CreateScrollFrame(nil, front)
    taskScroll:SetPoint("TOPLEFT",     front, "TOPLEFT",    HEADER_BORDER_PAD + PAD, -(HEADER_BORDER_PAD + HEADER_H + PAD))
    taskScroll:SetPoint("BOTTOMRIGHT", front,  "BOTTOMRIGHT", -(PAD+22), PAD + TASK_FOOTER_H + 2)
    taskScroll:Hide()
    f._taskScroll = taskScroll

    local taskSB = taskScroll.ScrollBar
    if taskSB then
        taskSB:SetAlpha(0)
        taskSB._hasRange = false
        taskScroll:HookScript("OnScrollRangeChanged", function(_, _, yRange)
            taskSB._hasRange = (yRange or 0) > 1
            local fm = f._cfg and f._cfg.focusMode
            if not fm then
                taskSB:SetAlpha(taskSB._hasRange and 1.0 or 0)
            end
        end)
        pcall(function() ForwardHoverRecursive(taskSB, f) end)
        f._taskSB = taskSB
    end

    local taskContent = CreateFrame("Frame", nil, taskScroll)
    taskContent:SetWidth(1); taskContent:SetHeight(1)
    taskScroll:SetScrollChild(taskContent)
    f._taskContent = taskContent

    -- Keep content width synced with scroll frame
    taskScroll:SetScript("OnSizeChanged", function(self)
        local w = self:GetWidth()
        if w and w > 0 then taskContent:SetWidth(w) end
    end)
    ForwardHover(taskScroll, f)
    -- Gap pixels between task rows land on taskScroll/taskContent, not on any
    -- row frame, so HookFocusHover them too to keep the counter > 0 in the gaps.
    HookFocusHover(taskScroll,   f)
    HookFocusHover(taskContent,  f)

    -- Task footer: completion counter pinned below the scroll frame
    local taskFooter = CreateFrame("Frame", nil, front)
    taskFooter:SetHeight(TASK_FOOTER_H)
    taskFooter:SetPoint("BOTTOMLEFT",  front, "BOTTOMLEFT",  PAD,       PAD)
    taskFooter:SetPoint("BOTTOMRIGHT", front, "BOTTOMRIGHT", -(PAD+22), PAD)
    taskFooter:Hide()
    f._taskFooter = taskFooter

    local taskFooterLbl = taskFooter:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    taskFooterLbl:SetPoint("LEFT",  taskFooter, "LEFT",  0, 0)
    taskFooterLbl:SetPoint("RIGHT", taskFooter, "RIGHT", -(12 + 4 + 12 + 4), 0)
    taskFooterLbl:SetJustifyH("LEFT")
    taskFooterLbl:SetTextColor(0.65, 0.65, 0.65)
    taskFooterLbl:SetText("")
    f._taskFooterLbl = taskFooterLbl

    -- Global reset icon (ui-repeat) — shown when note.taskList.resetType is set
    -- Anchored to the RIGHT of the footer; situation icon to its left.
    local FTR_ICO_SZ  = 12
    local FTR_ICO_PAD = 4
    local FTR_UI = "Interface\\AddOns\\BigNoteBox\\Assets\\UI\\"

    local ftrRstIco = CreateFrame("Frame", nil, taskFooter)
    ftrRstIco:SetSize(FTR_ICO_SZ, FTR_ICO_SZ)
    ftrRstIco:SetPoint("RIGHT", taskFooter, "RIGHT", 0, 0)
    ftrRstIco:EnableMouse(true)
    local ftrRstTx = ftrRstIco:CreateTexture(nil, "ARTWORK"); ftrRstTx:SetAllPoints()
    ftrRstTx:SetTexture(FTR_UI .. "ui-repeat")
    ftrRstIco:SetAlpha(0.6)
    ftrRstIco:Hide()
    ftrRstIco:SetScript("OnEnter", function(self)
        self:SetAlpha(1.0)
        local tl = BNB.Task and BNB.Task.GetList(noteID)
        local rt = tl and tl.resetType
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["STICKY_TASK_GLOBAL_RESET_TIP_TITLE"], 1, 1, 1)
        if rt == "daily" then
            GameTooltip:AddLine(L["STICKY_TASK_RESET_DAILY_TIP"], 0.78, 0.78, 0.78, true)
        elseif rt == "weekly" then
            GameTooltip:AddLine(L["STICKY_TASK_RESET_WEEKLY_TIP"], 0.78, 0.78, 0.78, true)
        end
        GameTooltip:Show()
    end)
    ftrRstIco:SetScript("OnLeave", function(self) self:SetAlpha(0.6); GameTooltip:Hide() end)
    f._taskFtrRstIco = ftrRstIco

    -- Global situation icon (ui-situation) — shown when note.taskList.situation is set
    local ftrSitIco = CreateFrame("Frame", nil, taskFooter)
    ftrSitIco:SetSize(FTR_ICO_SZ, FTR_ICO_SZ)
    ftrSitIco:SetPoint("RIGHT", ftrRstIco, "LEFT", -FTR_ICO_PAD, 0)
    ftrSitIco:EnableMouse(true)
    local ftrSitTx = ftrSitIco:CreateTexture(nil, "ARTWORK"); ftrSitTx:SetAllPoints()
    ftrSitTx:SetTexture(FTR_UI .. "ui-situation")
    ftrSitIco:SetAlpha(0.6)
    ftrSitIco:Hide()
    ftrSitIco:SetScript("OnEnter", function(self)
        self:SetAlpha(1.0)
        local tl = BNB.Task and BNB.Task.GetList(noteID)
        local sit = tl and tl.situation
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["STICKY_TASK_GLOBAL_SIT_TIP_TITLE"], 1, 1, 1)
        if sit and sit ~= "" then
            GameTooltip:AddLine(string.format(L["STICKY_TASK_BOUND_TO_FMT"], sit), 0.78, 0.78, 0.78, true)
        end
        GameTooltip:Show()
    end)
    ftrSitIco:SetScript("OnLeave", function(self) self:SetAlpha(0.6); GameTooltip:Hide() end)
    f._taskFtrSitIco = ftrSitIco

    ForwardHover(taskFooter, f)
    AddResizeHandle(f, noteID)

    -- ── Minimized tile ────────────────────────────────────────────────────────
    CreateMiniTile(f, noteID, note)

    -- ── Geometry + content ────────────────────────────────────────────────────
    LoadGeometry(noteID, f)

    -- Always populate note content at build time so switching back from task
    -- view always has something to show. Rich notes need a deferred render
    -- (GetWidth() is 0 on the same tick as Show()); plain notes set text now.
    local initCfg = GetCfg(noteID)
    local initIsRich = BNB.AdvancedMode and BNB.AdvancedMode.IsRich(note)
                       and not initCfg.richPlainText
    if not initIsRich then
        local body = note.body or ""
        if initCfg.richPlainText and BNB.AdvancedMode and BNB.AdvancedMode.StripMarkup then
            body = BNB.AdvancedMode.StripMarkup(body)
        end
        bodyEb:SetText(body)
    end

    ApplyConfig(f, noteID)
    f._noteID        = noteID
    f._minimized     = false
    f._taskViewActive = false

    -- Determine initial view.
    local initView = GetStickyViewPref(noteID)
    local openInTasks = initView == "tasks" and BNB.Task and BNB.Task.Shows(noteID)

    if openInTasks then
        -- Defer one tick so frame geometry is resolved, then switch to task view.
        -- Plain note text is already in bodyEb above; rich note content will be
        -- populated by RefreshNote when the user switches back to note view.
        C_Timer.After(0, function()
            if openFrames[noteID] == f then
                SN_SetTaskView(noteID, "tasks")
            end
        end)
    else
        -- Note view: populate rich content now (deferred), plain already set.
        if initIsRich then
            C_Timer.After(0, function()
                if openFrames[noteID] == f then
                    SN.RefreshNote(noteID)
                end
            end)
        else
            local function ScrollTop()
                if sf2 and sf2:IsVisible() then sf2:SetVerticalScroll(0) end
            end
            C_Timer.After(0.05, ScrollTop)
            C_Timer.After(0.15, ScrollTop)
            C_Timer.After(0.3,  ScrollTop)
        end
    end

    -- Ensure the TasksChanged callback is wired after first frame is built.
    EnsureStickyTaskCallback()

    return f
end

-- Bring a cached closed frame back for its note (PERF-03): the state
-- CreateStickyFrame starts a new frame in, then the note's current content.
local function ReopenStickyFrame(f, noteID)
    local note = BNB.GetNote(noteID)
    if not note then return nil end
    f._minimized, f._escOnly, f._quickNew = false, false, nil
    f._focusHovered, f._lastBodyClick = 0, nil
    f:SetFrameStrata(SN.Strata())
    if f._frontFace then f._frontFace:Show() end
    if f._miniTile then
        f._miniTile:Hide()
        f._miniTile:SetFrameStrata(SN.Strata())
        -- SN.Close unregistered it; a glow target from the start, as when built
        if BNB.Alarm and BNB.Alarm.RegisterGlowTarget then
            BNB.Alarm.RegisterGlowTarget(noteID, f._miniTile)
        end
    end
    if f._layoutHdrBtns then f._layoutHdrBtns() end
    LoadGeometry(noteID, f)

    local cfg = GetCfg(noteID)
    local isRich = BNB.AdvancedMode and BNB.AdvancedMode.IsRich(note) and not cfg.richPlainText
    if not isRich then
        local body = note.body or ""
        if cfg.richPlainText and BNB.AdvancedMode and BNB.AdvancedMode.StripMarkup then
            body = BNB.AdvancedMode.StripMarkup(body)
        end
        f._bodyEb:SetText(body)
    end
    ApplyConfig(f, noteID)
    -- Start in note view, as a new frame does; the saved view is left alone
    f._taskViewActive = false
    f._taskScroll:Hide()
    f._taskFooter:Hide()
    if f._tasksHdrBtn then SetHdrBtnTex(f._tasksHdrBtn, "tasks") end

    -- One tick later, as for a new frame (geometry resolved): the note view
    -- (title, icon badge and body as they are now), then tasks if preferred.
    local openInTasks = GetStickyViewPref(noteID) == "tasks" and BNB.Task and BNB.Task.Shows(noteID)
    C_Timer.After(0, function()
        if openFrames[noteID] ~= f then return end
        SN.RefreshNote(noteID)
        if openInTasks then SN_SetTaskView(noteID, "tasks") end
    end)
    return f
end

-- ── Minimize / restore ────────────────────────────────────────────────────────
function SN.SetMinimized(noteID, minimized)
    local f = openFrames[noteID]; if not f then return end
    f._minimized = minimized

    if minimized then
        -- Save current full size
        f._savedW = f._savedW or f:GetWidth()
        f._savedH = f._savedH or f:GetHeight()

        -- Close detached settings if open for this note
        SN._HideSettingsFor(noteID)
        if f._frontFace    then f._frontFace:Hide() end

        -- Hide resize handle while minimized
        if f._resizeHandle then f._resizeHandle:Hide() end

        -- Centre the tile on the icon badge, so the icon stays where it was
        -- clicked. Uses the badge's slot (BuildIconBadge anchors) rather than
        -- f._iconFrame, so a note without an icon minimizes to the same spot.
        local tile = f._miniTile
        if tile then
            local left = f:GetLeft()
            local top  = f:GetTop()
            local s    = f:GetEffectiveScale()
            local us   = UIParent:GetEffectiveScale()
            if left and top then
                local off = ICON_SZ / 2 - ICON_INSET   -- badge centre from the note's top-left
                tile:ClearAllPoints()
                tile:SetPoint("CENTER", UIParent, "BOTTOMLEFT",
                    ((left + off) * s) / us, ((top - off) * s) / us)
            else
                tile:ClearAllPoints()
                tile:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
            tile:Show(); tile:Raise()
        end

        f:Hide()
        -- Apply current config (border etc.) to mini tile
        ApplyConfig(f, noteID)

    else
        -- Restore note — position it opening down-left from the tile
        if f._miniTile then f._miniTile:Hide() end
        -- Resize handle stays hidden until the user hovers over the note

        f:SetSize(f._savedW or DEF_W, f._savedH or DEF_H)

        -- Place the note so its icon badge lands where the tile is (the
        -- inverse of the minimize placement above)
        local tile = f._miniTile
        if tile then
            local s      = UIParent:GetEffectiveScale()
            local ts     = tile:GetEffectiveScale()
            local tx, ty = tile:GetCenter()
            if tx and ty then
                local off = ICON_SZ / 2 - ICON_INSET
                f:ClearAllPoints()
                f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT",
                    (tx * ts) / s - off,
                    (ty * ts) / s + off)
            end
        end

        if f._frontFace then f._frontFace:Show() end
        f:Show(); f:Raise()
        SaveGeometry(noteID, f)
    end

    -- (icon buttons have no text state to toggle)
end

-- ── Public API ────────────────────────────────────────────────────────────────
-- How many stickies are open, against stickyMaxCount (ALL-234 opens several)
function SN.CountOpen() return CountOpen() end

function SN.IsOpen(noteID)
    local f = openFrames[noteID]
    if not f then return false end
    -- escOnly stickies are hidden in the world but are still "open" (they show
    -- when the ESC menu opens).  f._escOnly tracks this so IsOpen is truthful.
    return f:IsShown() or f._minimized or (f._escOnly == true)
end

-- noESCOpen: when true, suppress ShowUIPanel(GameMenuFrame) — used by the
-- login restore loop so reloading doesn't pop open the ESC menu.
function SN.Open(noteID, noESCOpen)
    if InCombatLockdown() then BNB:Print(L["STICKY_COMBAT"]); return end
    if not BNB.GetNote(noteID) then return end
    -- noESCOpen is the login restore (RestoreSession), not an open.
    if not noESCOpen then BNB.StampOpened(noteID) end
    if openFrames[noteID] then
        local f = openFrames[noteID]
        if f._minimized then SN.SetMinimized(noteID, false)
        else
            local cfg = GetCfg(noteID)
            if cfg.escOnly then
                EnsureESCHook()
                if not noESCOpen then ShowUIPanel(GameMenuFrame) end
            else
                f:Show(); f:Raise()
            end
        end
        SaveGeometry(noteID, f); return
    end
    if CountOpen() >= (BigNoteBoxDB and BigNoteBoxDB.stickyMaxCount or BNB.DEFAULTS.stickyMaxCount) then
        BNB:Print(string.format(L["STICKY_MAX"], BigNoteBoxDB and BigNoteBoxDB.stickyMaxCount or BNB.DEFAULTS.stickyMaxCount)); return
    end
    local f = closedFrames[noteID]
    closedFrames[noteID] = nil
    if f then f = ReopenStickyFrame(f, noteID)
    else      f = CreateStickyFrame(noteID) end
    if not f then return end
    openFrames[noteID] = f

    local cfg = GetCfg(noteID)
    -- Apply global "Default to ESC screen only" only when escOnly is nil (truly
    -- unset).  explicit false means the user intentionally reset to normal via X.
    if cfg.escOnly == nil then
        local db = DB()
        if db and db.stickyEscDefault then
            cfg.escOnly = true
            SaveCfg(noteID, cfg)
        end
    end
    EnsureESCHook()

    if cfg.escOnly then
        f._escOnly = true
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetAlpha(1.0)
        f:Hide()
        if not noESCOpen then ShowUIPanel(GameMenuFrame) end
    else
        f._escOnly = false
        f:SetAlpha(0); f:Show()
        -- A new sticky starts at the same frame level as the open ones, so
        -- their child frames interleaved: it could draw behind an older one
        -- and a click could land on the one underneath (ALL-198)
        f:Raise()
        FadeFrame(f, 0, 1.0, FLIP_TIME)
    end

    local db = DB()
    if db then
        db.postits = db.postits or {}
        db.postits[noteID] = db.postits[noteID] or {}
        db.postits[noteID].shown = true
    end
    local rec = StickyDB()[noteID]
    if rec and rec.minimized then SN.SetMinimized(noteID, true) end
    if BNB.RefreshStickyEyeBtn then BNB.RefreshStickyEyeBtn() end   -- ALL-237
end

-- Quick-note key in sticky mode (the default: BigNoteBoxDB.quickNoteKeyMode ~= "main"):
-- opens a new note as a sticky at screen centre, each further open sticky
-- offset down-right, and starts an inline edit. Returns false, with nothing
-- opened, when the sticky cannot be typed in (inline edit off, rich or locked
-- note) or the sticky limit is reached ("max" as the second value); the caller
-- then uses the main window.
function SN.OpenQuick(noteID)
    local note = BNB.GetNote(noteID)
    if not note or InCombatLockdown() then return false end
    local db = DB()
    if db and db.stickyInlineEdit == false then return false end
    if (BNB.AdvancedMode and BNB.AdvancedMode.IsRich(note)) or StickyNoteIsLocked(note) then
        return false
    end
    local max = db and db.stickyMaxCount or BNB.DEFAULTS.stickyMaxCount
    if CountOpen() >= max then return false, "max" end

    -- Each quick sticky steps 26 px down-right from the last one still open;
    -- the first (or the next after those are closed) sits at screen centre.
    -- Counting every open sticky, as before, jumped when unrelated stickies
    -- were open elsewhere (ALL-198).
    local prev = SN._lastQuickID and openFrames[SN._lastQuickID]
    local px, py
    if prev and prev:IsShown() and not prev._minimized then
        local cx, cy = prev:GetCenter()
        local ux, uy = UIParent:GetCenter()
        local s = prev:GetEffectiveScale() / UIParent:GetEffectiveScale()
        if cx and ux then px, py = cx * s - ux + 26, cy * s - uy - 26 end
    end
    local cfg = GetCfg(noteID)
    cfg.escOnly = false   -- a note to type in now, never an ESC-screen sticky
    SaveCfg(noteID, cfg)
    SN.Open(noteID)
    local f = openFrames[noteID]
    if not f then return false end
    -- px/py are UIParent units; SetPoint offsets are in the frame's own
    local fs = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", (px or 0) / fs, (py or 0) / fs)
    f:Raise()
    SN._lastQuickID = noteID
    SaveGeometry(noteID, f)
    f._quickNew = true
    StartInlineEdit(f)
    if not f._inlineEditing then f._quickNew = nil end
    return true
end

function SN.Close(noteID)
    local f = openFrames[noteID]; if not f then return end
    EndInlineEdit(f)   -- save before the frame fades out
    -- Clear per-note task collapse state
    _stickyCollapsed[noteID] = nil
    -- If this was an ESC-only sticky, clear the flag so the next open is a
    -- regular world sticky (the X button acts as a "reset to normal" gesture).
    -- Write explicit false (not nil) so the tri-state is respected:
    --   nil   = unset, apply global stickyEscDefault on next open
    --   true  = pinned to ESC screen
    --   false = explicitly normal (ignore global default)
    -- Persist immediately so the choice survives reload.
    if f._escOnly then
        f._escOnly = false
        local cfg = GetCfg(noteID)
        cfg.escOnly = false   -- explicit false, NOT nil
        SaveCfg(noteID, cfg)
        f._cfg = cfg
    end
    -- Dismiss alarm if it is active (fired but not yet dismissed) when sticky closes.
    -- Uses IsAlarmActive rather than IsGlowing so it works regardless of glow timing.
    if BNB.Alarm and BNB.Alarm.IsAlarmActive and BNB.Alarm.IsAlarmActive(noteID) then
        BNB.Alarm.Dismiss(noteID)
    end
    -- Close detached settings window if open for this note
    SN._HideSettingsFor(noteID)
    if f._miniTile then
        f._miniTile:Hide()
        if BNB.Alarm and BNB.Alarm.UnregisterGlowTarget then
            BNB.Alarm.UnregisterGlowTarget(noteID, f._miniTile)
        end
    end
    SaveGeometry(noteID, f)
    -- Exit fade (FadeFrame, ALL-64)
    openFrames[noteID] = nil   -- remove from open set immediately so
                               -- re-open during fade doesn't conflict
    if BNB.RefreshStickyEyeBtn then BNB.RefreshStickyEyeBtn() end   -- ALL-237
    local db2 = DB()
    if db2 and db2.postits and db2.postits[noteID] then
        db2.postits[noteID].shown = false
    end
    FadeFrame(f, f:GetAlpha(), 0, FLIP_TIME, function()
        f:Hide()
        -- Kept for the next open of this note (PERF-03), unless it was opened
        -- again during the fade (that built a frame of its own)
        if not openFrames[noteID] and not closedFrames[noteID] then
            closedFrames[noteID] = f
        end
    end)
end

-- Hide all open sticky frames and tiles without closing them.
-- Positions and content are preserved; stickies reappear on ShowAll().
-- Sets BigNoteBoxDB.stickiesHidden = true (transient; cleared on login unless
-- stickiesHiddenPersist is enabled in Config > Features > Sticky Notes).
function SN.HideAll()
    local db = BigNoteBoxDB
    if db then db.stickiesHidden = true end
    for _, f in pairs(openFrames) do
        -- Skip ESC-only stickies — they have their own show/hide lifecycle.
        if not (f._cfg and f._cfg.escOnly) then
            f:Hide()
            if f._miniTile then f._miniTile:Hide() end
        end
    end
    if BNB.RefreshStickyEyeBtn then BNB.RefreshStickyEyeBtn() end
end

-- Restore all open sticky frames and tiles that were hidden by HideAll().
function SN.ShowAll()
    local db = BigNoteBoxDB
    if db then db.stickiesHidden = false end
    for _, f in pairs(openFrames) do
        -- Skip ESC-only stickies — they show only when the ESC menu is open.
        if not (f._cfg and f._cfg.escOnly) then
            if f._minimized then
                -- Minimized stickies show only as tile
                if f._miniTile then f._miniTile:Show() end
            else
                f:Show()
            end
        end
    end
    if BNB.RefreshStickyEyeBtn then BNB.RefreshStickyEyeBtn() end
end

-- Open stickies that live in the world (ESC-screen ones left out): what Hide
-- all hides. The main window's eye greys out at 0 (ALL-237).
function SN.WorldCount()
    local n = 0
    for _, f in pairs(openFrames) do
        if not (f._cfg and f._cfg.escOnly) then n = n + 1 end
    end
    return n
end

-- ALL-101: hiding is otherwise silent, so an accidental Ctrl+H looked like
-- lost stickies. How many world stickies the hide flag is holding back.
function SN.HiddenCount()
    local db = BigNoteBoxDB
    if not (db and db.stickiesHidden) then return 0 end
    return SN.WorldCount()
end

-- The hide-all keybind as the player sees it ("CTRL-H"), or nil when unbound.
function SN.HideKeyText()
    local key = GetBindingKey("BIGNOTEBOXHIDESTICKIES")
    return key and GetBindingText(key) or nil
end

-- Chat line saying how many are hidden and how to show them. atLogin picks
-- the "still hidden" wording (stickiesHiddenPersist).
function SN.PrintHiddenNotice(atLogin)
    local n = SN.HiddenCount()
    if n == 0 then return end
    local key = SN.HideKeyText()
    if key then
        BNB:Print(string.format(L[atLogin and "STICKY_HIDDEN_LOGIN_KEY_FMT" or "STICKY_HIDDEN_KEY_FMT"], n, key))
    else
        BNB:Print(string.format(L[atLogin and "STICKY_HIDDEN_LOGIN_BTN_FMT" or "STICKY_HIDDEN_BTN_FMT"], n))
    end
end

-- Toggle between HideAll and ShowAll based on current stickiesHidden flag.
-- Ctrl+J (ALL-200): raise every open sticky and minimized tile above other
-- windows of their strata. ESC-screen stickies are left where they are.
function SN.BringAllToFront()
    for _, f in pairs(openFrames) do
        if not f._escOnly then
            if f:IsShown() then f:Raise() end
            if f._miniTile and f._miniTile:IsShown() then f._miniTile:Raise() end
        end
    end
end

function SN.ToggleHidden()
    local db = BigNoteBoxDB
    -- Nothing to hide: the key does nothing, as the greyed eye (ALL-237)
    if not (db and db.stickiesHidden) and SN.WorldCount() == 0 then return end
    if db and db.stickiesHidden then
        SN.ShowAll()
    else
        SN.HideAll()
        SN.PrintHiddenNotice(false)
    end
end

-- Minimize all open stickies that are not already minimized.
-- Tracks which notes were minimized by this call so UnminimizeAll can restore
-- only those, leaving notes the user had already minimized untouched.
local _minimizedByCombat = {}
function SN.MinimizeAll()
    _minimizedByCombat = {}
    for noteID, f in pairs(openFrames) do
        if not f._minimized then
            SN.SetMinimized(noteID, true)
            _minimizedByCombat[noteID] = true
        end
    end
end

-- Restore only the stickies that MinimizeAll collapsed.
function SN.UnminimizeAll()
    for noteID in pairs(_minimizedByCombat) do
        if openFrames[noteID] then
            SN.SetMinimized(noteID, false)
        end
    end
    _minimizedByCombat = {}
end

-- Called by AlarmManager when an alarm fires with showSticky = true.
-- If the note already has a sticky open: minimizes it.
-- If no sticky is open: opens one in minimized state.
function SN.EnsureMinimizedForAlarm(noteID)
    if not noteID then return end
    if openFrames[noteID] then
        -- Already open: just minimize it
        if not openFrames[noteID]._minimized then
            SN.SetMinimized(noteID, true)
        end
        -- Register miniTile as glow target (it's the visible element when minimized)
        local tile = openFrames[noteID]._miniTile
        if tile and BNB.Alarm and BNB.Alarm.RegisterGlowTarget then
            BNB.Alarm.RegisterGlowTarget(noteID, tile)
        end
    else
        -- Not open: open it then immediately minimize
        SN.Open(noteID)
        C_Timer.After(0.05, function()
            if openFrames[noteID] and not openFrames[noteID]._minimized then
                SN.SetMinimized(noteID, true)
            end
            -- Register miniTile after minimize completes
            local tile = openFrames[noteID] and openFrames[noteID]._miniTile
            if tile and BNB.Alarm and BNB.Alarm.RegisterGlowTarget then
                BNB.Alarm.RegisterGlowTarget(noteID, tile)
            end
        end)
    end
end

function SN.Toggle(noteID)
    if SN.IsOpen(noteID) then
        SN.Close(noteID)
    else
        -- Action bar toggle always opens as a regular world sticky.
        -- Write explicit false so the global stickyEscDefault doesn't re-apply.
        local cfg = GetCfg(noteID)
        if cfg.escOnly ~= false then
            cfg.escOnly = false
            SaveCfg(noteID, cfg)
        end
        SN.Open(noteID)
    end
end

-- Open as a regular world sticky, never a toggle (unit portrait menu, ALL-204):
-- an open sticky comes forward and a minimized one is restored (SN.Open), an
-- ESC-screen sticky becomes a normal one. SN.Close is what resets escOnly on
-- an ESC sticky, so close first, then write escOnly, then open.
function SN.OpenWorld(noteID)
    local f = openFrames[noteID]
    if f and f._escOnly then SN.Close(noteID) end
    local cfg = GetCfg(noteID)
    if cfg.escOnly ~= false then
        cfg.escOnly = false
        SaveCfg(noteID, cfg)
    end
    SN.Open(noteID)
end

-- Re-lay the title lock after a lock change. noteID nil = every open sticky
-- (the global "lock notes" setting). Title row only, so the body keeps its scroll.
function SN.RefreshLockIcons(noteID)
    for id, f in pairs(openFrames) do
        if not noteID or id == noteID then
            LayoutStickyTitle(f, BNB.GetNote(id))
        end
    end
end

-- Autosave from the main window (ALL-52): update the title and body in place,
-- keeping the scroll position. RefreshNote would scroll to the top and rebuild
-- the icon badge on every save while typing.
function SN.RefreshBodyLive(noteID)
    local f = openFrames[noteID]; if not f then return end
    local note = BNB.GetNote(noteID); if not note then return end
    if f._titleLbl then
        f._titleLbl:SetText(note.title ~= "" and note.title or L["UNTITLED"])
    end
    if f._inlineEditing or f._taskViewActive then return end
    if f._richNoteID == noteID and f._richScroll:IsShown() then
        local rf, rs = f._richRender, f._richScroll
        local y  = rs:GetVerticalScroll()
        local bs = note.fontSize or (BigNoteBoxDB and BigNoteBoxDB.fontSize) or BNB.DEFAULTS.fontSize
        BNB.AdvancedMode.ApplyFontsToRenderFrame(rf, bs, BNB.AdvancedMode.OutlineFlagStr(note.fontOutline))
        local rawST = getmetatable(rf).__index.SetText
        rawST(rf, BNB.AdvancedMode.ToHTML(note.body or "", bs))
        rf:SetHeight(rf:GetContentHeight())
        C_Timer.After(0, function()
            rs:SetVerticalScroll(math.min(y, rs:GetVerticalScrollRange() or y))
        end)
    elseif f._bodyScroll:IsShown() then
        local body = note.body or ""
        if GetCfg(noteID).richPlainText and BNB.AdvancedMode and BNB.AdvancedMode.StripMarkup then
            body = BNB.AdvancedMode.StripMarkup(body)
        end
        if f._bodyEb:GetText() ~= body then
            local sf, y = f._bodyScroll, f._bodyScroll:GetVerticalScroll()
            f._bodyEb:SetText(body)
            -- Runs after the SetText hook in Widgets.lua, which scrolls to 0
            C_Timer.After(0, function()
                sf:SetVerticalScroll(math.min(y, sf:GetVerticalScrollRange() or y))
            end)
        end
    end
end

-- Re-show the situation/class markers after a context or scope change.
function SN.RefreshMarkers(noteID)
    local f = noteID and openFrames[noteID]
    if f then UpdateStickyMarkers(f._iconFrame, BNB.GetNote(noteID)) end
end

-- Re-draw the icon badge and mini tile of every open sticky. Called by
-- TargetNote.lua once an NPC's display ID has been looked up, so the portrait
-- replaces the placeholder icon without reopening the sticky.
function SN.RefreshNpcPortraits()
    for id, f in pairs(openFrames) do
        local note = BNB.GetNote(id)
        if note and (note.source == "target" or note.source == "inspect") then
            SetStickyNoteIcon(f._badgeTex, note)
            if f._miniTile then SetStickyNoteIcon(f._miniTile._iconTex, note) end
        end
    end
end
-- A target or inspect note's badge follows the target: live portrait while
-- its unit is targeted, its icon again when the target goes (ALL-208)
BNB.RegisterEvent("PLAYER_TARGET_CHANGED", function() SN.RefreshNpcPortraits() end)

-- Header buttons the player switched off on Settings > Modules > Sticky
-- Notes (ALL-266): BigNoteBoxDB.stickyHideBtn[key] = true, key = "settings",
-- "edit", "alarm", "tasks", "minimize" or "view" (ALL-357); nil = shown.
-- Close always shows.
function SN.HdrBtnHidden(key)
    local h = BigNoteBoxDB and BigNoteBoxDB.stickyHideBtn
    return h ~= nil and h[key] == true
end

function SN.ApplyHeaderButtons()
    for _, f in pairs(openFrames) do
        if f._layoutHdrBtns then f._layoutHdrBtns() end
    end
end

-- The Tasks switch changed (UI/Config/Modules.lua, ALL-102): show or hide
-- each open sticky's Tasks header button; a sticky showing its tasks goes
-- back to the note.
function SN.ApplyTasksModule()
    local on = BNB.TasksEnabled()
    for id, f in pairs(openFrames) do
        if f._layoutHdrBtns then f._layoutHdrBtns() end
        if not on and f._taskViewActive then
            -- Keep the saved view, so Tasks back on reopens it in task view
            local rec = StickyDB()[id]
            local saved = rec and rec.view
            SN_SetTaskView(id, "note")
            rec = StickyDB()[id]
            if rec then rec.view = saved end
        end
    end
end

-- Re-render the task view for a sticky (called when spacing setting changes).
function SN.RefreshTaskView(noteID)
    local f = openFrames[noteID]
    if f and f._taskViewActive then
        RenderStickyTasks(noteID)
    end
end

function SN.RefreshNote(noteID)
    local f = openFrames[noteID]; if not f then return end
    local note = BNB.GetNote(noteID)
    if not note then SN.Close(noteID); return end
    if f._titleLbl then
        local t = note.titleColor
        if t then f._titleLbl:SetTextColor(t.r, t.g, t.b, 1)
        else       f._titleLbl:SetTextColor(unpack(COL_GOLD)) end
        f._titleLbl:SetText(note.title ~= "" and note.title or L["UNTITLED"])
    end
    -- Rebuild icon badge (handles icon added, changed, or cleared)
    f._titleLeft = BuildIconBadge(f, noteID, note)
    LayoutStickyTitle(f, note)
    -- Mid-edit: leave the body alone, SetText would move the cursor and drop typing
    if f._bodyEb and not f._inlineEditing then
        -- If task view is currently active, don't clobber it — just update
        -- the title and badge above which we've already done.
        if f._taskViewActive then
            -- No tasks left: back to the note (ALL-205), which runs this again
            if LeaveEmptyTaskView(noteID) then return end
            -- Re-render tasks in case text/completion changed
            RenderStickyTasks(noteID)
            return
        end
        local stickyCfg = GetCfg(noteID)
        local renderRich = BNB.AdvancedMode and BNB.AdvancedMode.IsRich(note)
                           and not stickyCfg.richPlainText
        if renderRich then
            -- Rich note: show _richScroll / _richRender, hide plain body scroll.
            -- _richScroll and _richRender are pre-built in CreateStickyFrame.
            f._richNoteID = noteID  -- stored so OnSizeChanged can re-render on resize
            f._bodyScroll:Hide()
            f._bodyEb:Hide()
            f._richScroll:Show()

            -- Generation counter: stale deferred ticks must not overwrite content
            -- when the note is switched before the timer fires.
            f._richGen = (f._richGen or 0) + 1
            local gen = f._richGen

            -- Defer one tick so the layout engine resolves richScroll width.
            -- On the same tick as Show(), GetWidth() can return 0.
            C_Timer.After(0, function()
                if (f._richGen or 0) ~= gen then return end
                if not f._richScroll:IsShown() then return end
                local w = f._richScroll:GetWidth()
                if not w or w <= 0 then return end
                local rf  = f._richRender
                local rn  = BNB.GetNote(noteID)
                if not rn then return end
                local bs  = rn.fontSize or (BigNoteBoxDB and BigNoteBoxDB.fontSize) or BNB.DEFAULTS.fontSize
                rf:SetWidth(w)
                local fs = BNB.AdvancedMode.OutlineFlagStr(rn.fontOutline)
                BNB.AdvancedMode.ApplyFontsToRenderFrame(rf, bs, fs)
                -- Use the raw SetText (bypasses SetHTML height-set) then set height
                local rawST = getmetatable(rf).__index.SetText
                rawST(rf, BNB.AdvancedMode.ToHTML(rn.body or "", bs))
                rf:SetHeight(rf:GetContentHeight())
                f._richScroll:SetVerticalScroll(0)
            end)
        else
            -- Plain note: normal editbox display
            f._richGen = (f._richGen or 0) + 1  -- cancel any pending rich tick
            f._richNoteID = nil
            f._richScroll:Hide()
            -- Strip markup tags when a rich note is being shown as plain text,
            -- so the user sees readable content rather than raw {h1}...{/h1} tags.
            local body = note.body or ""
            if stickyCfg.richPlainText and BNB.AdvancedMode and BNB.AdvancedMode.StripMarkup then
                body = BNB.AdvancedMode.StripMarkup(body)
            end
            f._bodyEb:SetText(body)
            f._bodyEb:Show()
            f._bodyScroll:Show()
            local function ScrollTop()
                if f._bodyScroll and f._bodyScroll:IsVisible() then
                    f._bodyScroll:SetVerticalScroll(0)
                end
            end
            C_Timer.After(0.05, ScrollTop)
            C_Timer.After(0.15, ScrollTop)
            C_Timer.After(0.3,  ScrollTop)
        end
    end
    ApplyConfig(f, noteID)
    -- Belt-and-suspenders: re-apply border to icon badge and mini tile
    -- in case ApplyConfig ran before the new _iconFrame was fully registered.
    local note3 = BNB.GetNote(noteID)
    local noteBorder3 = note3 and note3.borderOverride
    local borderScale3 = note3 and note3.borderScale or 100
    local borderOffset3 = note3 and note3.borderOffset or 2
    local borderBright3 = note3 and note3.borderBrightness or 100
    ApplyIconDecoration(f._iconFrame, f._iconFrame and f._iconFrame._iconTex, note3, noteBorder3, borderScale3, borderOffset3, borderBright3)
    ApplyIconDecoration(f._miniTile,  f._miniTile  and f._miniTile._iconTex,  note3, noteBorder3, borderScale3, borderOffset3, borderBright3)
end

function SN.RestoreSession()
    local db = DB(); if not db or not db.postits then return end
    -- If the player enabled "keep stickies hidden" and the hide flag is still
    -- set from last session, honour it — don't auto-show anything.
    local keepHidden = BigNoteBoxDB
        and BigNoteBoxDB.stickiesHiddenPersist
        and BigNoteBoxDB.stickiesHidden
    for noteID, rec in pairs(db.postits) do
        if rec and rec.shown and BNB.GetNote(noteID) then
            C_Timer.After(0.1, function()
                -- noESCOpen=true: suppress ShowUIPanel(GameMenuFrame) on restore
                -- so reloading/relogging doesn't pop the ESC menu open.
                SN.Open(noteID, true)
                -- If the persist-hidden flag is active, immediately hide the
                -- frame after Open() so it restores position data but stays
                -- invisible until the player manually shows stickies again.
                if keepHidden then
                    C_Timer.After(0, function()
                        local f = openFrames[noteID]
                        if f then
                            f:Hide()
                            if f._miniTile then f._miniTile:Hide() end
                        end
                    end)
                end
            end)
        end
    end
    -- ALL-101: say so when they come back hidden (after the 0.1s opens above)
    if keepHidden then C_Timer.After(1, function() SN.PrintHiddenNotice(true) end) end
end

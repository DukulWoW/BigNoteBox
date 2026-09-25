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
-- header). "< Back" reverses the crossfade. Uses BNB.CreateSlider (retail
-- MinimalSliderWithSteppersTemplate) and WowStyle1DropdownTemplate for border.
--
-- HOVER: every child frame forwards OnEnter/OnLeave to the root so the full
-- note surface responds to hover alpha.

local BNB = BigNoteBox
local L   = BNB.L

BNB.Sticky = BNB.Sticky or {}
local SN = BNB.Sticky

-- ── Constants ─────────────────────────────────────────────────────────────────
local MAX_NOTES  = 10
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

-- Returns border RGB scaled by cfg.borderBrightness (100 = default, 200 = double).
local function BorderRGB(cfg)
    local m = ((cfg and cfg.borderBrightness) or 100) / 100
    return math.min(1, COL_BORDER[1] * m),
           math.min(1, COL_BORDER[2] * m),
           math.min(1, COL_BORDER[3] * m)
end

local DEFAULT_CFG = {
    bgR = 0.07, bgG = 0.07, bgB = 0.09,
    alpha      = 0.96,
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
    bgTexture      = "none", -- key into BG_TEXTURES; "none" = plain colour, no texture
    bgColorOpacity = 1.0,    -- 0.0 = raw paper colour (white tint), 1.0 = full chosen colour
}

-- ── State ──────────────────────────────────────────────────────────────────────
local openFrames = {}
BNB._stickyFrames = openFrames

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
    local ov = CreateFrame("Frame", "BNBEscDimOverlay", UIParent)
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

local function GetCfg(noteID)
    local rec = noteID and StickyDB()[noteID]
    local cfg = (rec and rec.cfg) and rec.cfg or {}
    for k, v in pairs(DEFAULT_CFG) do
        if cfg[k] == nil then cfg[k] = v end
    end
    return cfg
end

local function SaveCfg(noteID, cfg)
    local db = DB(); if not db then return end
    db.postits = db.postits or {}
    db.postits[noteID] = db.postits[noteID] or {}
    db.postits[noteID].cfg = cfg
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
-- Each entry: { key, label, path }. "none" is always first (plain colour).
-- Add new textures here as assets are created; no other file needs changing.
local BG_TEXTURES = {
    { key = "none",         label = L["STICKY_BG_NONE"] },
    { key = "bg-stone",     label = L["STICKY_BG_STONE"],          tile = true,
      path = "Interface\\AddOns\\BigNoteBox\\Assets\\UI\\ui-bg-stone.tga" },
    { key = "bgtexture-01", label = L["STICKY_BG_OLD_WHITE_PAPER"],
      path = "Interface\\AddOns\\BigNoteBox\\Assets\\Backgrounds\\bgtexture-01.tga" },
    { key = "bgtexture-02", label = L["STICKY_BG_DAMAGED_STONE"],  tile = true,
      path = "Interface\\AddOns\\BigNoteBox\\Assets\\Backgrounds\\bgtexture-02.tga" },
    { key = "bgtexture-03", label = L["STICKY_BG_BLACK_MARBLE"],   tile = true,
      path = "Interface\\AddOns\\BigNoteBox\\Assets\\Backgrounds\\bgtexture-03.tga" },
    { key = "bgtexture-04", label = L["STICKY_BG_GOLDEN_PAPER"],
      path = "Interface\\AddOns\\BigNoteBox\\Assets\\Backgrounds\\bgtexture-04.tga" },
    { key = "bgtexture-05", label = L["STICKY_BG_OLD_DUTCH_PAPER"],
      path = "Interface\\AddOns\\BigNoteBox\\Assets\\Backgrounds\\bgtexture-05.tga" },
    { key = "bgtexture-06", label = L["STICKY_BG_PARCHMENT"],      tile = true,
      path = "Interface\\AddOns\\BigNoteBox\\Assets\\Backgrounds\\bgtexture-06.tga" },
    { key = "bgtexture-08", label = L["STICKY_BG_CREASED_PAPER"],  tile = true,
      path = "Interface\\AddOns\\BigNoteBox\\Assets\\Backgrounds\\bgtexture-08.tga" },
    { key = "bgtexture-12", label = L["STICKY_BG_DARK_MARBLE"],
      path = "Interface\\AddOns\\BigNoteBox\\Assets\\Backgrounds\\bgtexture-12.tga" },
    { key = "bgtexture-16", label = L["STICKY_BG_SANDSTONE"],
      path = "Interface\\AddOns\\BigNoteBox\\Assets\\Backgrounds\\bgtexture-16.tga" },
    { key = "bgtexture-17", label = L["STICKY_BG_WORN_LEATHER"],
      path = "Interface\\AddOns\\BigNoteBox\\Assets\\Backgrounds\\bgtexture-17.tga" },
    { key = "bgtexture-19", label = L["STICKY_BG_DARK_GRANITE"],   tile = true,
      path = "Interface\\AddOns\\BigNoteBox\\Assets\\Backgrounds\\bgtexture-19.tga" },
    { key = "bgtexture-20", label = L["STICKY_BG_DARK_STONE"],
      path = "Interface\\AddOns\\BigNoteBox\\Assets\\Backgrounds\\bgtexture-20.tga" },
}

local function GetBgTextureDef(key)
    if key and key ~= "none" then
        for _, t in ipairs(BG_TEXTURES) do
            if t.key == key then return t end
        end
    end
    return BG_TEXTURES[1]
end

local function BgTextureLabel(key)
    return GetBgTextureDef(key).label
end

-- Returns the tinted backdrop colour for the paper texture.
-- SetBackdropColor multiplies against the bgFile texture, so:
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
    -- Clamp to white so the texture always shows. The stored bgR/G/B is
    -- never modified -- the user's colour choice is preserved and reapplies
    -- if they switch the texture back to None.
    local luma = 0.299 * r + 0.587 * g + 0.114 * b
    if luma < 0.12 then r, g, b = 1, 1, 1 end
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
        -- Paper texture: use as bgFile so tiling is handled natively by the
        -- backdrop system. tileSize matches the texture's pixel dimensions.
        -- Falls back to White8x8 when no texture is selected.
        local texDef = GetBgTextureDef(cfg and cfg.bgTexture)
        local bgFile, bgTile, bgTileSz
        if texDef and texDef.path then
            bgFile   = texDef.path
            bgTile   = texDef.tile and true or false
            bgTileSz = texDef.tile and 256 or 0
        else
            -- No texture — plain White8x8 so SetBackdropColor works as normal
            bgFile   = "Interface\\Buttons\\White8x8"
            bgTile   = true
            bgTileSz = 8
        end
        if bPath then
            local es  = math.max(1, math.floor(16 * (borderScale or 100) / 100 + 0.5))
            local ins = math.max(0, math.floor(borderOffset or 4))
            target:SetBackdrop({
                bgFile = bgFile, tile = bgTile, tileSize = bgTileSz,
                edgeFile = bPath, edgeSize = es,
                insets = { left = ins, right = ins, top = ins, bottom = ins },
            })
        elseif not borderName or borderName == "" or borderName == "None" then
            target:SetBackdrop({
                bgFile = bgFile, tile = bgTile, tileSize = bgTileSz,
                edgeSize = 0,
                insets = { left = 0, right = 0, top = 0, bottom = 0 },
            })
            local br, bg2, bb = BorderRGB(cfg)
            pcall(function() target:SetBackdropBorderColor(br, bg2, bb, 0) end)
        else
            -- "Default" border — use the standard BNB backdrop but preserve
            -- any selected background texture in bgFile/tile/tileSize.
            local br, bg2, bb = BorderRGB(cfg)
            if target.SetBackdrop then
                target:SetBackdrop({
                    bgFile   = bgFile,   tile = bgTile, tileSize = bgTileSz,
                    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                    edgeSize = 14,
                    insets   = { left = 3, right = 3, top = 3, bottom = 3 },
                })
                pcall(function()
                    target:SetBackdropColor(COL_BG[1], COL_BG[2], COL_BG[3], 0.97)
                    target:SetBackdropBorderColor(br, bg2, bb, 1)
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
        local m = (borderBrightness or 100) / 100
        bf:ClearAllPoints()
        bf:SetPoint("TOPLEFT",     target, "TOPLEFT",     -pad,  pad)
        bf:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT",  pad, -pad)
        pcall(function()
            bf:SetBackdrop({
                edgeFile = bPath, edgeSize = es,
                insets = { left = 0, right = 0, top = 0, bottom = 0 },
            })
            bf:SetBackdropColor(0, 0, 0, 0)
            bf:SetBackdropBorderColor(
                math.min(1, 0.70 * m),
                math.min(1, 0.70 * m),
                math.min(1, 0.75 * m),
                0.85)
        end)
        bf:Show()
    else
        if target._borderOverlay then target._borderOverlay:Hide() end
    end
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

-- Apply background opacity via backdrop alpha only — never frame:SetAlpha.
-- This keeps text opacity (bodyEb:SetAlpha) independent of background opacity.
local function ApplyBgAlpha(frame, bgAlpha, cfg)
    local a = bgAlpha or 0.96
    local c = frame._cfg
    local ec = cfg or c
    local br, bg2, bb = BorderRGB(ec)
    local effectiveBorder = ec and ec.borderName
    local borderA = (not effectiveBorder or effectiveBorder == "" or effectiveBorder == "None") and 0 or a
    if c and frame.SetBackdropColor then
        local hasTexture = ec and ec.bgTexture and ec.bgTexture ~= "none"
        local tr, tg, tb
        if hasTexture then
            tr, tg, tb = TintedBgColor(ec)
        else
            tr = c.bgR or COL_BG[1]
            tg = c.bgG or COL_BG[2]
            tb = c.bgB or COL_BG[3]
        end
        pcall(function() frame:SetBackdropColor(tr, tg, tb, a) end)
        pcall(function() frame:SetBackdropBorderColor(br, bg2, bb, borderA) end)
    end
    if frame._headerBar and frame._headerBar.SetBackdropColor then
        pcall(function() frame._headerBar:SetBackdropColor(COL_HEADER[1], COL_HEADER[2], COL_HEADER[3], a) end)
        pcall(function() frame._headerBar:SetBackdropBorderColor(br, bg2, bb, 0) end)
    end
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
end

local function ApplyConfig(frame, noteID)
    local cfg  = GetCfg(noteID)
    local note = BNB.GetNote(noteID)
    frame._cfg = cfg
    -- Effective border for the main sticky frame: sticky cfg takes priority,
    -- falls back to note-level borderOverride from NoteConfig.
    local effectiveBorder = cfg.borderName
        or (note and note.borderOverride)
    local effectiveScale  = cfg.borderScale or 100
    local effectiveOffset = cfg.borderOffset or 4
    local br, bg2, bb = BorderRGB(cfg)
    local focusMode = cfg.focusMode
    local borderA = (not effectiveBorder or effectiveBorder == "" or effectiveBorder == "None") and 0 or 1
    if focusMode then borderA = 0 end  -- border hidden in focus mode (lerped in OnUpdate on hover)
    pcall(function()
        ApplyBorderToFrame(frame, effectiveBorder, effectiveScale, effectiveOffset, cfg)
        local hasTexture = cfg.bgTexture and cfg.bgTexture ~= "none"
        local tr, tg, tb
        if hasTexture then
            tr, tg, tb = TintedBgColor(cfg)
        else
            tr, tg, tb = cfg.bgR, cfg.bgG, cfg.bgB
        end
        frame:SetBackdropColor(tr, tg, tb, cfg.alpha or 0.96)
        frame:SetBackdropBorderColor(br, bg2, bb, borderA)
    end)

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
    ApplyBgAlpha(frame, cfg.alpha or 0.96, cfg)
    if frame._bodyEb then
        local r, g, b = cfg.textR or 0.88, cfg.textG or 0.88, cfg.textB or 0.88
        pcall(function() frame._bodyEb:SetTextColor(r, g, b) end)
        pcall(function() frame._bodyEb:SetAlpha(cfg.textAlpha or 1.0) end)
        pcall(function() frame._bodyEb:SetJustifyH(cfg.textAlign or "LEFT") end)
        local sz  = cfg.fontSize or (BigNoteBoxDB and BigNoteBoxDB.fontSize) or 13
        local fid = cfg.fontID
        local path
        if fid and BNB.ResolveFontDef then path = BNB.ResolveFontDef(fid).regular
        else path = BNB.GetBodyFont and select(1, BNB.GetBodyFont()) end
        local flags = GetOutlineFlagsAndShadow(cfg.fontOutline or "None")
        if path then pcall(function() frame._bodyEb:SetFont(path, sz, flags) end) end
        ApplyOutlineToEditBox(frame._bodyEb, cfg.fontOutline or "None")
    end
    -- Icon badge and mini tile use note-level border with scale/offset (matches note list)
    local noteBorder = note and note.borderOverride
    local borderScale = note and note.borderScale or 100
    local borderOffset = note and note.borderOffset or 2
    local borderBright = note and note.borderBrightness or 100
    ApplyIconBorder(frame._miniTile,  noteBorder, borderScale, borderOffset, borderBright)
    ApplyIconBorder(frame._iconFrame, noteBorder, borderScale, borderOffset, borderBright)
    -- Refresh mini tile icon texture in case the note's icon changed since the
    -- tile was first built (tile._iconTex is set at CreateMiniTile time).
    if frame._miniTile and frame._miniTile._iconTex then
        SetStickyNoteIcon(frame._miniTile._iconTex, note)
    end
end

-- ── Hover forwarding ──────────────────────────────────────────────────────────
-- Every child frame that covers the root must forward hover events, otherwise
-- only the thin backdrop border of the root fires OnEnter/OnLeave.
local function ForwardHover(child, root)
    child:SetScript("OnEnter", function()
        local c = root._cfg
        ApplyBgAlpha(root, math.max(0.95, c and c.alpha or 0.95), c)
        -- Also bring text alpha up to match background hover level
        if root._bodyEb then
            local ta = c and c.textAlpha or 1.0
            pcall(function() root._bodyEb:SetAlpha(math.max(0.95, ta)) end)
        end
    end)
    child:SetScript("OnLeave", function()
        if root._inlineEditing then return end   -- stays at hover alpha while editing
        local c = root._cfg
        ApplyBgAlpha(root, c and c.alpha or 0.96, c)
        -- Restore text alpha to its configured value
        if root._bodyEb then
            pcall(function() root._bodyEb:SetAlpha(c and c.textAlpha or 1.0) end)
        end
    end)
end

-- ── Frame fade (replaces LibAnimate, ALL-64) ──────────────────────────────────
-- Alpha fade on a native AnimationGroup, so it never touches the frame's
-- OnUpdate script (see the note on buttons further down).
-- Starting a fade stops the one already running on that frame and drops its
-- onDone: a sticky reopened while it is still fading out is not hidden by the
-- old fade's Hide. Same contract LibAnimate had (it stopped the running
-- animation on the frame first).
local function FadeFrame(target, fromAlpha, toAlpha, duration, onDone)
    local ag = target._bnbFadeAG
    if not ag then
        ag = target:CreateAnimationGroup()
        ag:SetToFinalAlpha(true)
        ag._alpha = ag:CreateAnimation("Alpha")
        local function Complete(self)
            self:GetParent():SetAlpha(self._toAlpha)
            local cb = self._onDone
            self._onDone = nil
            if cb then cb() end
        end
        ag:SetScript("OnFinished", Complete)
        -- Stopped by anything but a new fade (e.g. the frame hidden mid-fade):
        -- land on the final alpha and run onDone, so a note is never left
        -- half transparent
        ag:SetScript("OnStop", function(self)
            if not self._restarting then Complete(self) end
        end)
        target._bnbFadeAG = ag
    end
    -- A new fade replaces the running one: the old onDone never runs
    ag._restarting = true
    ag:Stop()
    ag._restarting = false
    ag._toAlpha, ag._onDone = toAlpha, onDone
    ag._alpha:SetFromAlpha(fromAlpha)
    ag._alpha:SetToAlpha(toAlpha)
    ag._alpha:SetDuration(duration)
    target:SetAlpha(fromAlpha)
    ag:Play()
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
}

-- ── Resize handle ─────────────────────────────────────────────────────────────
local function AddResizeHandle(frame, noteID)
    local h = CreateFrame("Button", nil, frame)
    h:SetSize(16, 16)
    h:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    h:SetFrameLevel(frame:GetFrameLevel() + 10)
    h:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    h:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    h:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

    -- Hover forwarding — inline so we can also control visibility.
    -- ForwardHover is NOT called here; it uses SetScript which would overwrite these.
    h:SetScript("OnEnter", function()
        h:Show()
        local c = frame._cfg
        ApplyBgAlpha(frame, math.max(0.95, c and c.alpha or 0.95), c)
        if frame._bodyEb then
            local ta = c and c.textAlpha or 1.0
            pcall(function() frame._bodyEb:SetAlpha(math.max(0.95, ta)) end)
        end
    end)
    h:SetScript("OnLeave", function()
        if not h._sizing then h:Hide() end
        local c = frame._cfg
        ApplyBgAlpha(frame, c and c.alpha or 0.96, c)
        if frame._bodyEb then
            pcall(function() frame._bodyEb:SetAlpha(c and c.textAlpha or 1.0) end)
        end
    end)

    h:SetScript("OnMouseDown", function(_, btn)
        if btn ~= "LeftButton" or frame._minimized then return end
        h._sizing = true
        local left = frame:GetLeft()
        local top  = frame:GetTop()
        if left and top then
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        end
        frame:StartSizing("BOTTOMRIGHT")
    end)
    h:SetScript("OnMouseUp", function()
        h._sizing = false
        frame:StopMovingOrSizing()
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
    end)

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
    tile:SetFrameStrata("HIGH")
    tile:SetToplevel(true)
    tile:SetMovable(true)
    tile:SetClampedToScreen(true)
    tile:EnableMouse(true)
    BNB.SetBackdrop(tile, COL_HEADER[1], COL_HEADER[2], COL_HEADER[3], 0.95,
        COL_BORDER[1], COL_BORDER[2], COL_BORDER[3], 1)

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
        ApplyBgAlpha(frame, c and c.alpha or 0.96, c)
        GameTooltip:Hide()
    end)

    -- Click-vs-drag on the tile
    local _tileDownX, _tileDownY = nil, nil
    local _tileDragging = false
    tile:RegisterForDrag("LeftButton")
    tile:SetScript("OnDragStart", function(self)
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
            -- Show context menu: Dismiss Alarm (if active) + Close Sticky
            local note = BNB.GetNote and BNB.GetNote(noteID)
            local alarm = note and note.alarm
            local hasActiveAlarm = alarm and not alarm.fired
                and BNB.Alarm and BNB.Alarm.IsAlarmActive and BNB.Alarm.IsAlarmActive(noteID)

            if hasActiveAlarm and C_XMLUtil and C_XMLUtil.GetTemplateInfo
               and C_XMLUtil.GetTemplateInfo("WowStyle1DropdownTemplate") then
                if not tile._ctxDD then
                    tile._ctxDD = CreateFrame("DropdownButton", nil, UIParent,
                        "WowStyle1DropdownTemplate")
                    tile._ctxDD:SetSize(1,1); tile._ctxDD:SetAlpha(0)
                end
                tile._ctxDD:ClearAllPoints()
                tile._ctxDD:SetPoint("TOPLEFT", tile, "TOPRIGHT", 0, 0)
                tile._ctxDD:SetupMenu(function(_, root)
                    root:CreateButton("|cffff9900" .. L["STICKY_CTX_DISMISS_ALARM"] .. "|r", function()
                        if BNB.Alarm and BNB.Alarm.Dismiss then
                            BNB.Alarm.Dismiss(noteID)
                        end
                    end)
                    root:CreateDivider()
                    root:CreateButton(L["STICKY_CTX_CLOSE"], function()
                        SN.Close(noteID)
                    end)
                end)
                tile._ctxDD:OpenMenu()
            else
                -- No active alarm or no modern menu: just close
                SN.Close(noteID)
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
        if note.context and note.context ~= "" then iconFrame._situTex:Show()
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

    -- Apply note-level border (matches note list icon)
    local noteBorder = note and note.borderOverride
    local borderScale = note and note.borderScale or 100
    local borderOffset = note and note.borderOffset or 2
    local borderBright = note and note.borderBrightness or 100
    ApplyIconBorder(iconFrame, noteBorder, borderScale, borderOffset, borderBright)

    local iconTex = iconFrame:CreateTexture(nil, "ARTWORK")
    iconTex:SetPoint("TOPLEFT",     iconFrame, "TOPLEFT",     ICON_PAD,  -ICON_PAD)
    iconTex:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -ICON_PAD,  ICON_PAD)
    SetStickyNoteIcon(iconTex, note)
    f._badgeTex = iconTex   -- re-drawn by SN.RefreshNpcPortraits

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
    -- Right-click: close the sticky note entirely, open or minimized, the same
    --   as right-clicking the mini tile (Dukul, 2026-09-24)
    iconFrame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    iconFrame:SetScript("OnClick", function(self, btn)
        if btn == "RightButton" then
            SN.Close(noteID)
        elseif btn == "LeftButton" then
            SN.SetMinimized(noteID, not f._minimized)
        end
    end)

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
    local def = BigNoteBoxDB and BigNoteBoxDB.taskStickyDefault or "tasks"
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

local function RenderStickyTasks(noteID)
    local f = openFrames[noteID]; if not f or not f._taskContent then return end
    local ct = f._taskContent

    -- Clear previous rows; reset hover counter since old row frames are orphaned.
    f._focusHovered = 0
    for _, child in ipairs({ct:GetChildren()}) do child:Hide(); child:SetParent(nil) end
    for _, region in ipairs({ct:GetRegions()}) do region:Hide(); region:SetParent(nil) end
    ct._rows = {}

    if not (BNB.Task and BNB.Task.HasTasks(noteID)) then
        ct:SetHeight(1)
        if f._taskFooterLbl then f._taskFooterLbl:SetText("") end
        return
    end

    local INDENT    = BNB.Task.SUBTASK_INDENT or 14
    local CB_SZ     = 14
    local PAD_L     = 4
    local PAD_R     = 6
    -- Row height and gap: focus mode forces compact; otherwise uses global setting
    local _cfg = f._cfg
    local _sp
    if _cfg and _cfg.focusMode then
        _sp = "compact"
    else
        _sp = BigNoteBoxDB and BigNoteBoxDB.taskSpacing or "normal"
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
        local indent = depth * INDENT
        local row = CreateFrame("Frame", nil, ct)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT",  ct, "TOPLEFT",  PAD_L + indent, y)
        row:SetPoint("TOPRIGHT", ct, "TOPRIGHT", -PAD_R, y)
        row._taskID = task.id
        row._depth  = depth
        local rowH = (depth > 0) and SUB_ROW_H or ROW_H
        row:SetHeight(rowH)

        -- Checkbox
        local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        cb:SetSize(CB_SZ, CB_SZ)
        cb:SetPoint("LEFT", row, "LEFT", 0, 0)
        cb:SetChecked(task.completed and true or false)
        cb:SetScript("OnClick", function(self)
            if BNB.Task and BNB.Task.ToggleTask then
                BNB.Task.ToggleTask(noteID, task.id)
            end
        end)
        -- Stop click from bubbling to the row's collapse handler
        cb:SetScript("OnMouseDown", function(_, btn)
            if btn == "LeftButton" then
                -- consume; let CheckButton handle it
            end
        end)

        -- Toggle button: bt-right (collapsed) / bt-down (expanded), matches RefBox.
        -- Hidden entirely for leaf tasks (no sub-tasks) — not functional in sticky.
        local SN_ASSETS  = "Interface\\AddOns\\BigNoteBox\\Assets\\"
        local SN_BTN_A   = SN_ASSETS .. "Buttons\\"
        local SN_UI_A    = SN_ASSETS .. "UI\\"
        local hasSubs    = BNB.Task.GetSubTasks and #BNB.Task.GetSubTasks(noteID, task.id) > 0
        local isCollapsed = collapsed[task.id]
        local TOG_SZ     = 14
        local ICO_SZ     = 12
        local ICO_GAP    = 2

        local togBtn = CreateFrame("Button", nil, row)
        togBtn:SetSize(TOG_SZ, TOG_SZ)
        togBtn:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        togBtn:SetFrameLevel(row:GetFrameLevel() + 3)
        local togTex = togBtn:CreateTexture(nil, "ARTWORK"); togTex:SetAllPoints()
        if hasSubs then
            togTex:SetTexture(SN_BTN_A .. (isCollapsed and "bt-right-normal" or "bt-down-normal"))
            togBtn:SetAlpha(1.0)
            local function DoCollapse()
                if collapsed[task.id] then collapsed[task.id] = nil
                else collapsed[task.id] = true end
                RenderStickyTasks(noteID)
            end
            togBtn:SetScript("OnClick", DoCollapse)
            togBtn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(collapsed[task.id] and L["STICKY_EXPAND_SUBTASKS"] or L["STICKY_COLLAPSE_SUBTASKS"], 1, 1, 1)
                GameTooltip:Show()
            end)
            togBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            -- Invisible hit area covering the row (except checkbox) for tap-to-collapse
            local hitBtn = CreateFrame("Button", nil, row)
            hitBtn:SetPoint("TOPLEFT",     row, "TOPLEFT",     CB_SZ + 2, 0)
            hitBtn:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0,         0)
            hitBtn:SetFrameLevel(row:GetFrameLevel() + 2)  -- below togBtn (+3)
            hitBtn:SetScript("OnClick", DoCollapse)
        else
            togBtn:Hide()  -- no sub-tasks: hide the toggle entirely
        end

        -- Left-to-right icon chain after togBtn: [R?] [S?]
        -- Each anchors LEFT to the previous element's RIGHT.
        local leftAnchor = togBtn  -- label will anchor to the last icon (or togBtn if none)

        local hasRst = task.resetType and task.resetType ~= "" and task.resetType ~= "none"
        if hasRst then
            local rstIco = CreateFrame("Button", nil, row)
            rstIco:SetSize(ICO_SZ, ICO_SZ)
            rstIco:SetPoint("LEFT", leftAnchor, "RIGHT", ICO_GAP, 0)
            rstIco:SetFrameLevel(row:GetFrameLevel() + 3)
            local rstTx = rstIco:CreateTexture(nil, "ARTWORK"); rstTx:SetAllPoints()
            rstTx:SetTexture(SN_UI_A .. "ui-repeat")
            rstIco:SetAlpha(0.8)
            local resetTip = task.resetType == "daily" and "Reset: Daily" or "Reset: Weekly"
            rstIco:SetScript("OnEnter", function(self)
                self:SetAlpha(1.0)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(resetTip, 1, 1, 1)
                GameTooltip:AddLine(L["STICKY_TASK_CLICK_EDIT_TIP"], 0.8, 0.8, 0.8)
                GameTooltip:Show()
            end)
            rstIco:SetScript("OnLeave", function(self) self:SetAlpha(0.8); GameTooltip:Hide() end)
            rstIco:SetScript("OnClick", function()
                if BNB.TaskEditWindow and BNB.TaskEditWindow.Open then
                    BNB.TaskEditWindow.Open(noteID, task.id, row)
                end
            end)
            leftAnchor = rstIco
        end

        local hasSit = task.situation and task.situation ~= ""
        if hasSit then
            local sitIco = CreateFrame("Button", nil, row)
            sitIco:SetSize(ICO_SZ, ICO_SZ)
            sitIco:SetPoint("LEFT", leftAnchor, "RIGHT", ICO_GAP, 0)
            sitIco:SetFrameLevel(row:GetFrameLevel() + 3)
            local sitTx = sitIco:CreateTexture(nil, "ARTWORK"); sitTx:SetAllPoints()
            sitTx:SetTexture(SN_UI_A .. "ui-situation")
            sitIco:SetAlpha(0.8)
            sitIco:SetScript("OnEnter", function(self)
                self:SetAlpha(1.0)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(string.format(L["STICKY_TASK_SITUATION_FMT"], task.situation), 1, 1, 1)
                GameTooltip:AddLine(L["STICKY_TASK_CLICK_EDIT_TIP"], 0.8, 0.8, 0.8)
                GameTooltip:Show()
            end)
            sitIco:SetScript("OnLeave", function(self) self:SetAlpha(0.8); GameTooltip:Hide() end)
            sitIco:SetScript("OnClick", function()
                if BNB.TaskEditWindow and BNB.TaskEditWindow.Open then
                    BNB.TaskEditWindow.Open(noteID, task.id, row)
                end
            end)
            leftAnchor = sitIco
        end

        -- Task text label — anchors from last icon (or togBtn if no icons)
        local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("LEFT",  leftAnchor, "RIGHT", ICO_GAP, 0)
        lbl:SetPoint("RIGHT", row,        "RIGHT", 0,       0)
        lbl:SetJustifyH("LEFT"); lbl:SetMaxLines(1); lbl:SetWordWrap(false)
        local col = BNB.Task.GetTaskColor(task)
        lbl:SetTextColor(col.r, col.g, col.b)
        local stickyLblText = task.text or ""
        if hasSubs and isCollapsed then
            local subs = BNB.Task.GetSubTasks(noteID, task.id)
            stickyLblText = stickyLblText .. " |cff888888(" .. #subs .. ")|r"
        end
        lbl:SetText(stickyLblText)

        -- Tooltip on truncation
        lbl:SetScript("OnEnter", function(self)
            if self:IsTruncated() then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(task.text or "", 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        lbl:SetScript("OnLeave", function() GameTooltip:Hide() end)

        row._cb  = cb
        row._lbl = lbl
        rows[#rows + 1] = row
        -- Hook all children of this row into the focus-hover counter so the
        -- OnUpdate lerp stays active while the mouse is over any task row element.
        HookFocusHover(row, f)
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
-- Swap the texture set on a header button built by HdrBtn.
-- Relies on _n/_h/_p refs stored at build time.
local SN_BTN_PATH = "Interface\\AddOns\\BigNoteBox\\Assets\\Buttons\\"
local function SetHdrBtnTex(btn, texName)
    if not (btn and btn._n) then return end
    btn._n:SetTexture(SN_BTN_PATH .. texName .. "-normal")
    btn._h:SetTexture(SN_BTN_PATH .. texName .. "-hover")
    btn._p:SetTexture(SN_BTN_PATH .. texName .. "-press")
end

local function SN_SetTaskView(noteID, view)
    local f = openFrames[noteID]; if not f then return end
    local showTasks = (view == "tasks") and BNB.Task and BNB.Task.HasTasks(noteID)

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
        SetHdrBtnTex(f._tasksHdrBtn, showTasks and "bt-note" or "bt-tasks")
    end
end

-- Expose so SN.Open and external callers can use it after SN is defined.
-- Forward-declared; assigned after SN table exists below.

-- Register TasksChanged callback once so open stickies re-render on data changes.
local function EnsureStickyTaskCallback()
    if _stickyTaskCallbackRegistered then return end
    if not (BNB.Task and BNB.Task.RegisterCallback) then return end
    _stickyTaskCallbackRegistered = true
    BNB.Task.RegisterCallback("TasksChanged", function(changedNoteID)
        local f = changedNoteID and openFrames[changedNoteID]
        if not f then return end
        if f._taskViewActive then
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
        if BNB.RefreshNoteList then BNB.RefreshNoteList() end
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
    if not f:IsMouseOver() then
        local c = f._cfg
        ApplyBgAlpha(f, c and c.alpha or 0.96, c)
        pcall(function() eb:SetAlpha(c and c.textAlpha or 1.0) end)
    end

    local note = BNB.GetNote(noteID)
    local text = eb:GetText() or ""
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
    local c = f._cfg
    ApplyBgAlpha(f, math.max(0.95, c and c.alpha or 0.95), c)
    pcall(function() eb:SetAlpha(math.max(0.95, c and c.textAlpha or 1.0)) end)
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
    for _, f in pairs(openFrames) do pcall(EndInlineEdit, f) end
end)

-- ── Build a sticky note frame ─────────────────────────────────────────────────
local function CreateStickyFrame(noteID)
    local note = BNB.GetNote(noteID)
    if not note then return nil end

    local f = BNB.CreateBackdropFrame("Frame", nil, UIParent)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:SetResizable(true)
    f:SetResizeBounds(MIN_W, MIN_H, 1200, 800)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self)
        self:StopMovingOrSizing(); SaveGeometry(noteID, self)
    end)
    BNB.SetBackdrop(f, COL_BG[1], COL_BG[2], COL_BG[3], 0.97,
        COL_BORDER[1], COL_BORDER[2], COL_BORDER[3], 1)
    f:SetScript("OnEnter", function(self)
        local c = self._cfg
        ApplyBgAlpha(self, math.max(0.95, c and c.alpha or 0.95), c)
    end)
    f:SetScript("OnLeave", function(self)
        if self._inlineEditing then return end
        local c = self._cfg
        ApplyBgAlpha(self, c and c.alpha or 0.96, c)
    end)

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
    header:SetScript("OnDragStart", function() f:StartMoving() end)
    header:SetScript("OnDragStop",  function()
        f:StopMovingOrSizing(); SaveGeometry(noteID, f)
    end)
    ForwardHover(header, f)
    f._headerBar = header

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
    titleLock:SetTexture("Interface\\AddOns\\BigNoteBox\\Assets\\Actionbar\\ab-lock")
    titleLock:SetAlpha(TITLE_LOCK_ALPHA)
    titleLock:Hide()
    f._titleLock  = titleLock
    f._titleLeft  = titleLeft
    LayoutStickyTitle(f, note)

    -- ── Icon button overlay ───────────────────────────────────────────────────
    -- A container frame that holds all header icon buttons, parented to the header
    -- at OVERLAY frame level so it renders above the title text.
    -- Starts hidden (alpha 0); fades in/out over 0.1 s when the root is hovered.
    local ASSETS = "Interface\\AddOns\\BigNoteBox\\Assets\\Buttons\\"
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

    -- Icon button factory (right-to-left slot numbering, slot 1 = rightmost)
    local function HdrBtn(slot, texName, tip, onClick)
        local btn = CreateFrame("Button", nil, btnOverlay)
        btn:SetSize(BTN_SZ, BTN_SZ)
        -- Position: right-aligned with gap, centred vertically in header.
        -- Single anchor so SetSize is respected (two anchors stretch the button).
        local xOff = -BTN_RIGHT_PAD - (slot - 1) * (BTN_SZ + BTN_GAP)
        local yOff = (HEADER_H - BTN_SZ) / 2
        btn:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", xOff, yOff)
        btn:SetFrameLevel(btnOverlay:GetFrameLevel() + 1)

        -- Suppress WoW's default button flash so our press texture shows cleanly
        btn:SetHighlightTexture("")
        btn:SetPushedTexture("")

        local normalTx = btn:CreateTexture(nil, "ARTWORK")
        normalTx:SetAllPoints()
        normalTx:SetTexture(ASSETS .. texName .. "-normal")

        local hoverTx = btn:CreateTexture(nil, "ARTWORK")
        hoverTx:SetAllPoints()
        hoverTx:SetTexture(ASSETS .. texName .. "-hover")
        hoverTx:Hide()

        local pressTx = btn:CreateTexture(nil, "ARTWORK")
        pressTx:SetAllPoints()
        pressTx:SetTexture(ASSETS .. texName .. "-press")
        pressTx:Hide()

        -- Store refs so textures can be swapped without rebuilding the button
        btn._n = normalTx; btn._h = hoverTx; btn._p = pressTx

        -- Start hidden; will be shown by FadeBtns when root is hovered
        btn:SetAlpha(0)
        table.insert(_hdrBtns, btn)

        btn:SetScript("OnClick", onClick)
        btn:SetScript("OnMouseDown", function()
            pressTx:Show(); normalTx:Hide(); hoverTx:Hide()
        end)
        btn:SetScript("OnMouseUp", function()
            pressTx:Hide(); hoverTx:Show()
        end)
        btn:SetScript("OnEnter", function()
            normalTx:Hide(); hoverTx:Show()
            FadeBtns(1)   -- keep all buttons visible while any button is hovered
            GameTooltip:SetOwner(btn, "ANCHOR_BOTTOM")
            local dynTip = tip
            if btn == f._alarmHdrBtn then
                local n = BNB.GetNote and BNB.GetNote(noteID)
                dynTip = (n and n.alarm) and L["STICKY_EDIT_ALARM_TIP"] or L["STICKY_SET_ALARM_TIP"]
            end
            GameTooltip:AddLine(dynTip, 1, 1, 1); GameTooltip:Show()
            local c = f._cfg
            ApplyBgAlpha(f, math.max(0.95, c and c.alpha or 0.95), c)
        end)
        btn:SetScript("OnLeave", function()
            pressTx:Hide(); hoverTx:Hide(); normalTx:Show()
            GameTooltip:Hide()
        end)
        return btn
    end

    -- slot 1 = close, slot 2 = minimize, slot 3 = settings, slot 4 = edit
    HdrBtn(1, "bt-close", L["STICKY_UNPIN_TIP"], function() SN.Close(noteID) end)

    local minBtn = HdrBtn(2, "bt-minimize", L["STICKY_MINIMIZE_TO_ICON_TIP"], function()
        SN.SetMinimized(noteID, not f._minimized)
    end)
    f._minBtn = minBtn

    HdrBtn(3, "bt-settings", L["STICKY_NOTE_SETTINGS_TIP"], function()
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

    HdrBtn(4, "bt-edit", L["STICKY_OPEN_TO_EDIT_TIP"], function()
        -- Ends (and saves) an inline edit first, so BNB opens on the new text
        EndInlineEdit(f)
        OpenInMainEditor(noteID)
    end)

    -- slot 5 = alarm: opens alarm setter window anchored to this button
    -- Assets: Assets/UI/sn-alarm-normal.tga + sn-alarm-hover.tga
    local alarmHdrBtn = HdrBtn(5, "bt-alarm", L["STICKY_SET_ALARM_TIP"], function()
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
            BNB.AlarmWindow.Open(noteID, alarmHdrBtn, f)
        end
    end)
    f._alarmHdrBtn = alarmHdrBtn

    -- slot 6 = tasks: toggle task view / create first task
    local tasksHdrBtn = HdrBtn(6, "bt-tasks", L["STICKY_CREATE_TASK_TIP"], function()
        local hasTasks = BNB.Task and BNB.Task.HasTasks(noteID)
        if not hasTasks then
            -- No tasks: close ESC menu, open main window, select note, open RefBox, add task
            CloseESCAndDo(function()
                if not BNB.mainFrame then
                    if BNB.CreateMainWindow then BNB.CreateMainWindow() end
                end
                if BNB.mainFrame then
                    BNB.mainFrame:Show()
                    if BNB.RefreshNoteList then BNB.RefreshNoteList() end
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
        local c = f._cfg
        ApplyBgAlpha(f, math.max(0.95, c and c.alpha or 0.95), c)
    end)
    f._tasksHdrBtn = tasksHdrBtn
    -- OnEnter/OnLeave on the root are unreliable when the frame is fully covered
    -- by child frames (front, header, body) — the cursor may never "touch" the
    -- root's own hit rect, so Leave events can be swallowed.  Polling each frame
    -- is the standard WoW pattern for this; the IsMouseOver call is near-free.
    local _btnsShown  = false
    local _focusLerp  = 1.0   -- 1.0 = full header visible, 0.0 = fully hidden
    local _focusTarget = 1.0  -- target for the lerp
    local FOCUS_SPEED  = 6.0  -- units per second (lower = slower)
    local _lastTime    = 0
    -- Counter incremented by HookFocusHover on task row children so that
    -- IsMouseOver gaps between rows don't falsely signal "not hovered".
    f._focusHovered = 0

    f:HookScript("OnUpdate", function(self, elapsed)
        -- Inline editing counts as hovered: buttons and header stay visible
        local over = f._inlineEditing or f:IsMouseOver() or (f._focusHovered and f._focusHovered > 0)
        local cfg  = f._cfg
        local focusMode = cfg and cfg.focusMode

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

            -- Animate border alpha
            local borderA = _focusLerp
            pcall(function()
                local br, bg2, bb = BorderRGB(cfg)
                local effectiveBorder = cfg.borderName or (BNB.GetNote(f._noteID) and BNB.GetNote(f._noteID).borderOverride)
                local hasBorder = effectiveBorder and effectiveBorder ~= "" and effectiveBorder ~= "None"
                if hasBorder then
                    f:SetBackdropBorderColor(br, bg2, bb, _focusLerp)
                end
            end)
        end

        -- ── Resize handle ─────────────────────────────────────────────────────
        local rh = f._resizeHandle
        if rh then
            local shouldShow = (over or rh._sizing) and not f._minimized
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
        front, (BigNoteBoxDB and BigNoteBoxDB.fontSize) or 13)
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
    local richScroll = CreateFrame("ScrollFrame", nil, front, "ScrollFrameTemplate")
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
                local bs = rn.fontSize or (BigNoteBoxDB and BigNoteBoxDB.fontSize) or 12
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

    -- ── Task scroll frame ─────────────────────────────────────────────────────
    -- Sibling to _bodyScroll and _richScroll. Shown only when task view is active.
    -- Anchored identically to _bodyScroll but bottom leaves room for the footer.
    local taskScroll = CreateFrame("ScrollFrame", nil, front, "ScrollFrameTemplate")
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
    local openInTasks = initView == "tasks" and BNB.Task and BNB.Task.HasTasks(noteID)

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
    if CountOpen() >= (BigNoteBoxDB and BigNoteBoxDB.stickyMaxCount or MAX_NOTES) then
        BNB:Print(string.format(L["STICKY_MAX"], BigNoteBoxDB and BigNoteBoxDB.stickyMaxCount or MAX_NOTES)); return
    end
    local f = CreateStickyFrame(noteID)
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
    local db2 = DB()
    if db2 and db2.postits and db2.postits[noteID] then
        db2.postits[noteID].shown = false
    end
    FadeFrame(f, f:GetAlpha(), 0, FLIP_TIME, function() f:Hide() end)
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
end

-- Toggle between HideAll and ShowAll based on current stickiesHidden flag.
function SN.ToggleHidden()
    local db = BigNoteBoxDB
    if db and db.stickiesHidden then
        SN.ShowAll()
    else
        SN.HideAll()
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
        local bs = note.fontSize or (BigNoteBoxDB and BigNoteBoxDB.fontSize) or 12
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
        if note and note.source == "target" then
            SetStickyNoteIcon(f._badgeTex, note)
            if f._miniTile then SetStickyNoteIcon(f._miniTile._iconTex, note) end
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
                local bs  = rn.fontSize or (BigNoteBoxDB and BigNoteBoxDB.fontSize) or 12
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
    ApplyIconBorder(f._iconFrame, noteBorder3, borderScale3, borderOffset3, borderBright3)
    ApplyIconBorder(f._miniTile,  noteBorder3, borderScale3, borderOffset3, borderBright3)
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
end

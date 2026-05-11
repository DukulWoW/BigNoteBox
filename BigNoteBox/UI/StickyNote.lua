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
    rec.shown     = frame:IsShown() and true or false
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
    { key = "none",         label = "None" },
    { key = "bg-stone",     label = "Stone",          tile = true,
      path = "Interface\\AddOns\\BigNoteBox\\Assets\\UI\\ui-bg-stone.tga" },
    { key = "bgtexture-01", label = "Old white used paper",
      path = "Interface\\AddOns\\BigNoteBox\\Assets\\Backgrounds\\bgtexture-01.tga" },
    { key = "bgtexture-02", label = "Damaged Stone",  tile = true,
      path = "Interface\\AddOns\\BigNoteBox\\Assets\\Backgrounds\\bgtexture-02.tga" },
    { key = "bgtexture-03", label = "Black Marble",   tile = true,
      path = "Interface\\AddOns\\BigNoteBox\\Assets\\Backgrounds\\bgtexture-03.tga" },
    { key = "bgtexture-04", label = "Golden paper",
      path = "Interface\\AddOns\\BigNoteBox\\Assets\\Backgrounds\\bgtexture-04.tga" },
    { key = "bgtexture-05", label = "Old Dutch paper",
      path = "Interface\\AddOns\\BigNoteBox\\Assets\\Backgrounds\\bgtexture-05.tga" },
    { key = "bgtexture-06", label = "Parchment",      tile = true,
      path = "Interface\\AddOns\\BigNoteBox\\Assets\\Backgrounds\\bgtexture-06.tga" },
    { key = "bgtexture-08", label = "Creased paper",  tile = true,
      path = "Interface\\AddOns\\BigNoteBox\\Assets\\Backgrounds\\bgtexture-08.tga" },
    { key = "bgtexture-12", label = "Dark marble",
      path = "Interface\\AddOns\\BigNoteBox\\Assets\\Backgrounds\\bgtexture-12.tga" },
    { key = "bgtexture-16", label = "Sandstone",
      path = "Interface\\AddOns\\BigNoteBox\\Assets\\Backgrounds\\bgtexture-16.tga" },
    { key = "bgtexture-17", label = "Worn leather",
      path = "Interface\\AddOns\\BigNoteBox\\Assets\\Backgrounds\\bgtexture-17.tga" },
    { key = "bgtexture-19", label = "Dark granite",   tile = true,
      path = "Interface\\AddOns\\BigNoteBox\\Assets\\Backgrounds\\bgtexture-19.tga" },
    { key = "bgtexture-20", label = "Dark stone",
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
        if fid and BNB.GetFontDef then path = BNB.GetFontDef(fid).regular
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
        local iconPath = (note and note.icon and note.icon ~= "") and note.icon
                         or "Interface\\Icons\\INV_Misc_Note_06"
        frame._miniTile._iconTex:SetTexture(iconPath)
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
        local c = root._cfg
        ApplyBgAlpha(root, c and c.alpha or 0.96, c)
        -- Restore text alpha to its configured value
        if root._bodyEb then
            pcall(function() root._bodyEb:SetAlpha(c and c.textAlpha or 1.0) end)
        end
    end)
end

-- ── Alpha crossfade helper ────────────────────────────────────────────────────
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

-- ── Settings face ─────────────────────────────────────────────────────────────
-- Lives INSIDE the note frame, covering the same area as the front face.
-- Styled to match the config window: COL_HEADER title bar, COL_BG background,
-- gold title, "< Back" button.
-- The note root frame already has RegisterForDrag, so dragging still works.
-- Opening/closing crossfades front↔settings in-place (no size change).
-- ── Detached sticky note settings window ──────────────────────────────────────
-- A standalone ButtonFrameTemplate window (same look as the main BNB window)
-- that opens with a LibAnimate transition when the user clicks "=" on a sticky.
-- The sticky note fades/zooms out, this window fades/zooms in at the same spot.

local SETTINGS_W = 264   -- matches NoteConfig NCW
local SETTINGS_TITLE_H = 60
local SETTINGS_TAB_BAR_H = 28
-- Content starts just below the tab button bottoms (~y=-45 from frame top) + small pad
local SETTINGS_TAB_CONTENT_Y = 62
local SETTINGS_PAD = 12  -- matches NoteConfig PAD
local SETTINGS_CW = 224  -- matches NoteConfig CW_SCROLL (NCW - PAD - 28)

local _stickySettingsFrame = nil   -- single reusable settings window
local _stickySettingsNoteID = nil  -- noteID it's currently editing

local function GetLibAnimate()
    return LibStub and LibStub("LibAnimate", true)
end

local function GetBorderList()
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local seen = { ["Default"] = true, ["None"] = true }
    local list = { "None", "Default" }
    if LSM then
        for _, v in ipairs(LSM:List("border")) do
            if not seen[v] then seen[v] = true; list[#list+1] = v end
        end
    end
    return list
end

local function OpenColorPicker(r, g, b, onDone)
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            swatchFunc = function() local nr,ng,nb = ColorPickerFrame:GetColorRGB(); onDone(nr,ng,nb) end,
            cancelFunc = function() end, hasOpacity = false, r = r, g = g, b = b,
        })
    else
        ColorPickerFrame.func       = function() local nr,ng,nb = ColorPickerFrame:GetColorRGB(); onDone(nr,ng,nb) end
        ColorPickerFrame.cancelFunc = function() end
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame:SetColorRGB(r, g, b); ShowUIPanel(ColorPickerFrame)
    end
end

-- Close the detached settings window and restore the sticky note
local function CloseStickySettings()
    local noteID = _stickySettingsNoteID
    local f      = _stickySettingsFrame
    if not f or not f:IsShown() then return end

    local stickyFrame = noteID and openFrames[noteID]
    local LA = GetLibAnimate()

    -- Apply config before restoring the sticky
    if stickyFrame and noteID then ApplyConfig(stickyFrame, noteID) end

    if LA then
        LA:Animate(f, "fadeOut", {
            duration = 0.2,
            onFinished = function()
                f:Hide()
                if stickyFrame then stickyFrame:SetAlpha(1.0) end
            end,
        })
    else
        f:Hide()
        if stickyFrame then stickyFrame:SetAlpha(1.0) end
    end
end

local SK_SS_TITLE_H   = 28
local SK_SS_CONTENT_Y = 58   -- SK_SS_TITLE_H(28) + SK_TAB_H(24) + 6px gap

local function BuildStickySettingsWindow()
    if _stickySettingsFrame then return _stickySettingsFrame end

    local skinMode = BigNoteBoxDB and BigNoteBoxDB.skinMode
    local f
    local tabContentY  -- used by MakeScrollPanel / MakePlainPanel below

    if skinMode then
        f = BNB.CreateSkinFrame(UIParent, false, "BigNoteBoxStickySettingsFrame", false)
        _G["BigNoteBoxStickySettingsFrame"] = f
        f:SetSize(SETTINGS_W, 640)
        f:SetFrameStrata("DIALOG")
        f:SetToplevel(true); f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self) self:StartMoving() end)
        f:SetScript("OnDragStop",  function(self)
            self:StopMovingOrSizing()
            -- Settings detaches freely when dragged — sticky stays where it is.
        end)

        local titleBar = BNB.CreateSkinStrip(f, true, false)
        titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
        titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
        titleBar:SetHeight(SK_SS_TITLE_H)
        titleBar:EnableMouse(true)
        titleBar:RegisterForDrag("LeftButton")
        titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
        titleBar:SetScript("OnDragStop",  function()
            f:StopMovingOrSizing()
        end)

        local titleLbl = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        titleLbl:SetPoint("CENTER", titleBar, "CENTER", -12, 0)
        titleLbl:SetTextColor(1, 0.82, 0)
        titleLbl:SetText("Sticky Note Settings")
        f._titleLbl = titleLbl

        local closeBtn = BNB.CreateSkinCloseButton(titleBar, function() CloseStickySettings() end)
        closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -3, 0)

        f:SetScript("OnShow", function()
            if BNB.ApplyMainWindowSkin then BNB.ApplyMainWindowSkin() end
        end)
        tabContentY = SK_SS_CONTENT_Y
    else
        f = CreateFrame("Frame", "BigNoteBoxStickySettingsFrame", UIParent, "ButtonFrameTemplate")
        f:SetSize(SETTINGS_W, 640)
        f:SetFrameStrata("DIALOG")
        f:SetToplevel(true); f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self)
            self:StartMoving()
        end)
        f:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            -- Settings detaches freely when dragged — sticky stays where it is.
            -- The anchor to the sticky is broken by StartMoving(); that is intentional.
        end)

        ButtonFrameTemplate_HidePortrait(f)
        ButtonFrameTemplate_HideButtonBar(f)
        if f.Inset then f.Inset:Hide() end
        f:SetAlpha(0.95)
        f:SetTitle("Sticky Note Settings")
        if f.CloseButton then
            f.CloseButton:SetScript("OnClick", function() CloseStickySettings() end)
        end
        tabContentY = SETTINGS_TAB_CONTENT_Y
    end
    tinsert(UISpecialFrames, "BigNoteBoxStickySettingsFrame")

    -- ── Tab buttons ───────────────────────────────────────────────────────────
    local sTabBtns   = {}
    local sTabPanels = {}
    local TAB_LABELS = { "General", "Appearance", "Situation" }

    local function SelectStickyTab(idx)
        for i = 1, 3 do
            if sTabBtns[i] and not skinMode then
                if i == idx then PanelTemplates_SelectTab(sTabBtns[i])
                else             PanelTemplates_DeselectTab(sTabBtns[i]) end
            end
            if sTabPanels[i] then
                if i == idx then sTabPanels[i]:Show()
                else             sTabPanels[i]:Hide() end
            end
        end
        f._activeTab = idx
    end

    if skinMode then
        local tabCtrl = BNB.CreateSkinTabs(f, TAB_LABELS, function(idx)
            SelectStickyTab(idx)
        end)
        tabCtrl.frame:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, -SK_SS_TITLE_H)
        tabCtrl.frame:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -SK_SS_TITLE_H)
        f._skinTabCtrl = tabCtrl
    else
        local tpl = (C_XMLUtil and C_XMLUtil.GetTemplateInfo
            and C_XMLUtil.GetTemplateInfo("PanelTopTabButtonTemplate"))
            and "PanelTopTabButtonTemplate"
            or  "PanelTabButtonTemplate"

        local lastBtn = nil
        for i, label in ipairs(TAB_LABELS) do
            local btn = CreateFrame("Button", "BigNoteBoxStickySettingsTab"..i, f, tpl)
            btn:SetText(label)
            pcall(function()
                if tpl == "PanelTopTabButtonTemplate" then
                    PanelTemplates_TabResize(btn, 15, nil, 70)
                else
                    PanelTemplates_TabResize(btn, 0)
                end
            end)
            btn:SetID(i)
            if lastBtn then btn:SetPoint("LEFT", lastBtn, "RIGHT", 5, 0)
            else             btn:SetPoint("TOPLEFT", f, "TOPLEFT", 7, -25) end
            btn:SetScript("OnClick", function(self) SelectStickyTab(self:GetID()) end)
            sTabBtns[i] = btn
            lastBtn = btn
        end
        PanelTemplates_SetNumTabs(f, 3)
        f.numTabs = 3
    end

    -- ── Two scroll panels (one per tab) ───────────────────────────────────────
    local function MakeScrollPanel()
        local sf = CreateFrame("ScrollFrame", nil, f, "ScrollFrameTemplate")
        local bar = sf.ScrollBar
        if bar then bar:SetAlpha(0) end
        sf:SetPoint("TOPLEFT",     f, "TOPLEFT",      SETTINGS_PAD, -tabContentY)
        sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -24, 4)

        local ct = CreateFrame("Frame", nil, sf)
        ct:SetWidth(SETTINGS_CW)
        ct:SetHeight(1)
        sf:SetScrollChild(ct)

        local function ApplyScrollbar()
            local sfH = sf:GetHeight()
            if sfH < 4 then return end
            local ctH = ct._contentH or 1
            ct:SetHeight(math.max(ctH, sfH))
            if ctH <= sfH + 2 then
                if bar then bar:SetAlpha(0) end
                ct:SetWidth(SETTINGS_CW + 20)   -- use full width when no bar
            else
                if bar then bar:SetAlpha(1) end
                ct:SetWidth(SETTINGS_CW)
            end
        end
        sf:SetScript("OnSizeChanged", function() ApplyScrollbar() end)
        sf:HookScript("OnShow", function() C_Timer.After(0.05, ApplyScrollbar) end)
        sf._applyScrollbar = ApplyScrollbar

        return sf, ct
    end

    -- Plain (non-scrolling) panel — used for Situation tab which has
    -- anchor-relative content that doesn't need a scroll child.
    local function MakePlainPanel()
        local p = CreateFrame("Frame", nil, f)
        p:SetPoint("TOPLEFT",     f, "TOPLEFT",      SETTINGS_PAD, -tabContentY)
        p:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -SETTINGS_PAD, 4)
        p:Hide()
        -- ct and sf are the same frame for a plain panel
        return p, p
    end

    local sf1, ct1 = MakeScrollPanel()
    local sf2, ct2 = MakeScrollPanel()
    local sf3, ct3 = MakePlainPanel()
    sTabPanels[1] = sf1
    sTabPanels[2] = sf2
    sTabPanels[3] = sf3

    f._sTabBtns   = sTabBtns
    f._sTabPanels = sTabPanels
    f._selectTab  = SelectStickyTab
    f._ct1 = ct1   -- General
    f._ct2 = ct2   -- Appearance
    f._ct3 = ct3   -- Situation

    f:Hide()
    _stickySettingsFrame = f
    return f
end

-- Populate settings content for a specific noteID
-- Destroys and recreates content children each time (simple, no stale state)
local function PopulateStickySettings(noteID)
    local f   = _stickySettingsFrame
    local ct1 = f._ct1   -- General tab content
    local ct2 = f._ct2   -- Appearance tab content
    local ct3 = f._ct3   -- Situation tab content
    local sf1 = f._sTabPanels[1]
    local sf2 = f._sTabPanels[2]
    local sf3 = f._sTabPanels[3]

    -- Destroy old content children in all panels
    for _, ct in ipairs({ct1, ct2, ct3}) do
        for _, child in ipairs({ct:GetChildren()}) do child:Hide(); child:SetParent(nil) end
        for _, region in ipairs({ct:GetRegions()}) do region:Hide(); region:SetParent(nil) end
    end

    local stickyFrame = openFrames[noteID]
    local cfg = GetCfg(noteID)

    -- ── Shared layout helpers (take ct as param) ──────────────────────────────
    local function Sec(ct, txt)
        local y = ct._y or -8
        local l = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        l:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        l:SetTextColor(1, 0.82, 0, 1); l:SetText(txt)
        ct._y = y - 22
    end

    local function SubLbl(ct, txt)
        local y = ct._y or -8
        local l = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        l:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        l:SetTextColor(0.60, 0.60, 0.60); l:SetText(txt)
        ct._y = y - 16
    end

    local function Hdr(ct, txt)
        local y = ct._y or -8
        local l = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        l:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        l:SetTextColor(0.75, 0.75, 0.75); l:SetText(txt)
        ct._y = y - 18
    end

    local function Rule(ct)
        local y = ct._y or -8
        local t = ct:CreateTexture(nil, "ARTWORK")
        t:SetHeight(1)
        t:SetPoint("TOPLEFT",  ct, "TOPLEFT",  0, y)
        t:SetPoint("TOPRIGHT", ct, "TOPRIGHT", 0, y)
        if skinMode and BNB.GetSkinPreset then
            local p = BNB.GetSkinPreset()
            local br, bg_, bb = BNB.SkinBorderOf(p)
            t:SetColorTexture(br, bg_, bb, 0.9)
            BNB.RegisterSkinRule(t, 0.9)
        else
            t:SetColorTexture(0.25, 0.25, 0.28, 1)
        end
        ct._y = y - 10
    end

    local function MakeSlider(ct, label, minV, maxV, initV, onChange)
        local y = ct._y or -8
        local sl = BNB.CreateSlider(ct, label, minV, maxV, initV, nil,
            function(v) onChange(v) end)
        sl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        -- Pull right edge in so the MinimalSlider's value label (rendered
        -- outside the slider frame to the right) doesn't clip the scrollbar.
        sl:SetWidth(SETTINGS_CW - 30)
        sl:EnableMouseWheel(false)
        ct._y = y - 44
        return sl
    end

    local function ColorBtn(ct, r, g, b, labelTxt, onPick)
        local y = ct._y or -8
        local sw = CreateFrame("Button", nil, ct)
        sw:SetSize(26, 26)
        sw:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        local tx = sw:CreateTexture(nil, "ARTWORK"); tx:SetAllPoints()
        tx:SetColorTexture(r, g, b)
        local hi = sw:CreateTexture(nil, "HIGHLIGHT"); hi:SetAllPoints()
        hi:SetColorTexture(1, 1, 1, 0.25)
        local bdr = BNB.CreateBackdropFrame("Frame", nil, sw)
        bdr:SetAllPoints(); bdr:SetFrameLevel(sw:GetFrameLevel() - 1)
        BNB.SetBackdrop(bdr, 0,0,0,0, 0.45, 0.45, 0.48, 1)
        bdr:EnableMouse(false)
        local ll = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        ll:SetPoint("LEFT", sw, "RIGHT", 6, 0)
        ll:SetTextColor(0.78, 0.78, 0.78); ll:SetText(labelTxt)
        sw._tx = tx
        local cR, cG, cB = r, g, b
        sw:SetScript("OnClick", function()
            local oR, oG, oB = cR, cG, cB
            OpenColorPicker(cR, cG, cB, function(nr, ng, nb)
                cR, cG, cB = nr, ng, nb
                sw._tx:SetColorTexture(nr, ng, nb)
                onPick(nr, ng, nb)
            end)
        end)
        ct._y = y - 34
        return sw
    end

    local function ColorGrid(ct, swatchOnPick)
        ct._y = BNB.BuildColorGrid(ct, ct._y or -8, SETTINGS_CW, swatchOnPick)
    end

    local function FinalisePanel(ct, sf)
        local contentH = math.abs(ct._y or -8) + 12
        ct._contentH = contentH
        ct:SetHeight(math.max(contentH, sf:GetHeight()))
        C_Timer.After(0.05, function()
            if sf._applyScrollbar then sf._applyScrollbar() end
        end)
    end

    -- ══════════════════════════════════════════════════════════════════════════
    -- TAB 1 — GENERAL
    -- ══════════════════════════════════════════════════════════════════════════
    ct1._y = -8

    -- ── Focus mode toggle ─────────────────────────────────────────────────────
    -- Hides title, icon and border (fade in on hover). Compact content padding.
    -- Rich notes render as plain text. Task view uses compact row spacing.
    do
        local focusChk = CreateFrame("CheckButton", nil, ct1, "UICheckButtonTemplate")
        focusChk:SetSize(24, 24)
        focusChk:SetPoint("TOPLEFT", ct1, "TOPLEFT", -4, ct1._y)
        focusChk:SetChecked(cfg.focusMode == true)
        focusChk:SetScript("OnClick", function(self)
            cfg.focusMode = self:GetChecked() and true or nil
            SaveCfg(noteID, cfg)
            if stickyFrame then
                ApplyConfig(stickyFrame, noteID)
            end
        end)
        local focusLbl = ct1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        focusLbl:SetPoint("LEFT", focusChk, "RIGHT", 4, 0)
        focusLbl:SetText("Focus mode")
        focusChk:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Focus mode", 1, 1, 1)
            GameTooltip:AddLine("Hides the title, icon and border. They reappear on hover. Reduces content padding. Forces plain text for rich notes. Task view uses compact row spacing.", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        focusChk:SetScript("OnLeave", function() GameTooltip:Hide() end)
        ct1._y = ct1._y - 30
    end

    -- ── "Show as plain text" toggle (rich notes only) ─────────────────────────
    -- Hidden entirely for plain notes. When on, the sticky renders raw text
    -- instead of the SimpleHTML view, and text color/style controls become active.
    local note         = BNB.GetNote(noteID)
    local noteIsRich   = BNB.AdvancedMode and BNB.AdvancedMode.IsRich(note)
    local richPlainChk, richPlainChkLbl

    if noteIsRich then
        richPlainChk = CreateFrame("CheckButton", nil, ct1, "UICheckButtonTemplate")
        richPlainChk:SetSize(24, 24)
        richPlainChk:SetPoint("TOPLEFT", ct1, "TOPLEFT", -4, ct1._y)
        richPlainChk:SetChecked(cfg.richPlainText == true)

        richPlainChkLbl = ct1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        richPlainChkLbl:SetPoint("LEFT", richPlainChk, "RIGHT", 2, 0)
        richPlainChkLbl:SetText("Show rich note as plain text")
        richPlainChkLbl:SetTextColor(0.9, 0.9, 0.9)

        ct1._y = ct1._y - 30
        Rule(ct1)
        ct1._y = ct1._y - 4
    end

    -- ── Text color ────────────────────────────────────────────────────────────
    -- Greyed out when the note is rich AND "show as plain text" is off,
    -- because the color has no effect on SimpleHTML rendering in that state.
    Sec(ct1, "Text color")

    local textColorWidgets = {}  -- collect for alpha/mouse toggling
    local plainOnlyWidgets = {}  -- font, font-size, text-style, text-opacity: inactive for rich notes

    local tcBtn = ColorBtn(ct1, cfg.textR or 0.88, cfg.textG or 0.88, cfg.textB or 0.88,
        "Click to pick color", function(r, g, b)
            cfg.textR, cfg.textG, cfg.textB = r, g, b
            SaveCfg(noteID, cfg)
            if stickyFrame and stickyFrame._bodyEb then
                pcall(function() stickyFrame._bodyEb:SetTextColor(r, g, b) end)
            end
        end)
    textColorWidgets[#textColorWidgets+1] = tcBtn

    SubLbl(ct1, "Quick pick:")
    -- Snapshot children before ColorGrid so we can collect only what it adds
    local beforeChildren = {}
    for _, c in ipairs({ct1:GetChildren()}) do beforeChildren[c] = true end

    ColorGrid(ct1, function(r, g, b)
        cfg.textR, cfg.textG, cfg.textB = r, g, b
        SaveCfg(noteID, cfg)
        if stickyFrame and stickyFrame._bodyEb then
            pcall(function() stickyFrame._bodyEb:SetTextColor(r, g, b) end)
        end
    end)

    -- Collect everything ColorGrid added into textColorWidgets
    for _, c in ipairs({ct1:GetChildren()}) do
        if not beforeChildren[c] then
            textColorWidgets[#textColorWidgets + 1] = c
        end
    end

    -- Shared greying helper: dims controls that have no effect on a rich note
    -- rendered as SimpleHTML. Covers text color, font, font-size, text-style,
    -- and text-opacity. Called at build time and when the plain-text checkbox toggles.
    local function SyncPlainOnlyControls()
        local isPlain = (not noteIsRich) or (cfg.richPlainText == true)
        local a = isPlain and 1.0 or 0.4
        for _, w in ipairs(textColorWidgets) do
            pcall(function()
                w:SetAlpha(a)
                if w.EnableMouse then w:EnableMouse(isPlain) end
            end)
        end
        for _, w in ipairs(plainOnlyWidgets) do
            pcall(function()
                w:SetAlpha(a)
                if w.EnableMouse then w:EnableMouse(isPlain) end
            end)
        end
    end

    -- Wire the richPlainText checkbox now that SyncPlainOnlyControls is defined
    if richPlainChk then
        richPlainChk:SetScript("OnClick", function(self)
            cfg.richPlainText = self:GetChecked() and true or nil
            SaveCfg(noteID, cfg)
            SyncPlainOnlyControls()
            -- Re-render the sticky with the new mode
            if BNB.Sticky and BNB.Sticky.RefreshNote then
                BNB.Sticky.RefreshNote(noteID)
            end
        end)
        richPlainChk:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Show rich note as plain text", 1, 1, 1)
            GameTooltip:AddLine("Renders the note body as plain text instead of formatted rich text. Useful for copying or editing the raw markup.", 0.78, 0.78, 0.78, true)
            GameTooltip:Show()
        end)
        richPlainChk:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    Rule(ct1)
    Sec(ct1, "Font")

    -- Font card picker — 2-column × 3-row grid layout
    -- Card dimensions: full height for readability, half width minus gap
    local PH_FONT  = 38   -- card height
    local PG_FONT  = 4    -- vertical gap between rows
    local COL_GAP  = 4    -- horizontal gap between columns
    local CARD_W   = math.floor((SETTINGS_CW - COL_GAP) / 2)
    local fontPickerBtns = {}

    local function HLStickyFonts()
        local cur = cfg.fontID
        for _, e in ipairs(fontPickerBtns) do
            local sel = (e.id == cur)
            if e.btn.SetBackdropColor then
                if sel then e.btn:SetBackdropColor(0.12,0.18,0.12,0.95); e.btn:SetBackdropBorderColor(0.4,0.8,0.4,1)
                else        e.btn:SetBackdropColor(0.06,0.06,0.08,0.95); e.btn:SetBackdropBorderColor(0.28,0.28,0.30,1) end
            end
            if e.nameLbl then e.nameLbl:SetTextColor(sel and 1 or 0.85, sel and 0.82 or 0.85, sel and 0 or 0.85, 1) end
        end
    end

    local fonts = BNB.FONTS or {}
    for i, def in ipairs(fonts) do
        local fid  = def.id
        local col  = (i - 1) % 2          -- 0 = left, 1 = right
        local gridRow = math.floor((i - 1) / 2)
        local xOff = col * (CARD_W + COL_GAP)
        local yOff = ct1._y - gridRow * (PH_FONT + PG_FONT)

        local btn = BNB.CreateBackdropFrame("Button", nil, ct1)
        BNB.SetBackdrop(btn, 0.06,0.06,0.08,0.95, 0.28,0.28,0.30,1)
        btn:SetSize(CARD_W, PH_FONT)
        btn:SetPoint("TOPLEFT", ct1, "TOPLEFT", xOff, yOff)
        btn:EnableMouse(true)
        btn:SetScript("OnEnter", function(s)
            if cfg.fontID ~= fid then
                s:SetBackdropColor(0.10,0.12,0.10,0.95); s:SetBackdropBorderColor(0.35,0.55,0.35,1)
            end
        end)
        btn:SetScript("OnLeave", HLStickyFonts)
        btn:SetScript("OnClick", function()
            cfg.fontID = fid; SaveCfg(noteID, cfg)
            if stickyFrame then ApplyConfig(stickyFrame, noteID) end
            HLStickyFonts()
        end)
        local nameLbl = btn:CreateFontString(nil, "OVERLAY")
        nameLbl:SetPoint("TOPLEFT",  btn, "TOPLEFT",  5, -5)
        nameLbl:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -5, -5)
        nameLbl:SetJustifyH("LEFT"); nameLbl:SetHeight(16)
        if def.bold and def.bold ~= "" then pcall(function() nameLbl:SetFont(def.bold, 11, "") end)
        else nameLbl:SetFontObject("GameFontNormal") end
        nameLbl:SetText(def.label)
        local prevLbl = btn:CreateFontString(nil, "OVERLAY")
        prevLbl:SetPoint("BOTTOMLEFT",  btn, "BOTTOMLEFT",  5, 5)
        prevLbl:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -5, 5)
        prevLbl:SetJustifyH("LEFT"); prevLbl:SetHeight(12)
        if def.regular and def.regular ~= "" then pcall(function() prevLbl:SetFont(def.regular, 10, "") end)
        else prevLbl:SetFontObject("GameFontNormalSmall") end
        prevLbl:SetTextColor(0.55, 0.55, 0.55); prevLbl:SetText(def.preview or "")
        fontPickerBtns[#fontPickerBtns+1] = {btn=btn, id=fid, nameLbl=nameLbl, prevLbl=prevLbl, def=def}
        plainOnlyWidgets[#plainOnlyWidgets+1] = btn
    end
    -- Advance _y past the grid (ceil rows, since fonts may be odd count)
    local gridRows = math.ceil(#fonts / 2)
    ct1._y = ct1._y - gridRows * (PH_FONT + PG_FONT) + PG_FONT
    HLStickyFonts()

    local fontSizeSl = MakeSlider(ct1, "Font size", 8, 24,
        cfg.fontSize or (BigNoteBoxDB and BigNoteBoxDB.fontSize) or 13,
        function(v)
            cfg.fontSize = v; SaveCfg(noteID, cfg)
            if stickyFrame and stickyFrame._bodyEb then
                local path = select(1, stickyFrame._bodyEb:GetFont())
                if path then pcall(function() stickyFrame._bodyEb:SetFont(path, v, "") end) end
            end
        end)
    plainOnlyWidgets[#plainOnlyWidgets+1] = fontSizeSl

    Rule(ct1)
    Hdr(ct1, "Text style")

    -- Line height
    local LH_STICKY = {
        {key="1.0",label="1.0 (default)"},{key="1.25",label="1.25"},
        {key="1.5",label="1.5"},{key="1.75",label="1.75"},{key="2.0",label="2.0"},
    }
    local function StickyLHLabel()
        local cur = cfg.lineHeight or "1.0"
        for _,m in ipairs(LH_STICKY) do if m.key==cur then return m.label end end
        return LH_STICKY[1].label
    end
    local function ApplyStickyLH(val)
        cfg.lineHeight = val; SaveCfg(noteID, cfg)
    end

    SubLbl(ct1, "Line height:")
    local useNativeLH = C_XMLUtil and C_XMLUtil.GetTemplateInfo
        and C_XMLUtil.GetTemplateInfo("WowStyle1DropdownTemplate")
    if useNativeLH then
        local lhSDD = CreateFrame("DropdownButton", nil, ct1, "WowStyle1DropdownTemplate")
        lhSDD:SetPoint("TOPLEFT", ct1, "TOPLEFT", 0, ct1._y)
        lhSDD:SetWidth(SETTINGS_CW)
        lhSDD:SetupMenu(function(_, root)
            for _, m in ipairs(LH_STICKY) do
                local key = m.key
                root:CreateRadio(m.label,
                    function() return (cfg.lineHeight or "1.0") == key end,
                    function()
                        lhSDD:GenerateMenu()
                        ApplyStickyLH(key)
                    end)
            end
        end)
        ct1._y = ct1._y - 36
        plainOnlyWidgets[#plainOnlyWidgets+1] = lhSDD
    else
        local lhSBtn = BNB.CreateButton(nil, ct1, StickyLHLabel(), SETTINGS_CW, 22)
        lhSBtn:SetPoint("TOPLEFT", ct1, "TOPLEFT", 0, ct1._y)
        lhSBtn:SetScript("OnClick", function(self)
            local cur = cfg.lineHeight or "1.0"
            local idx = 1
            for i, m in ipairs(LH_STICKY) do if m.key==cur then idx=i;break end end
            idx = (idx % #LH_STICKY) + 1
            ApplyStickyLH(LH_STICKY[idx].key)
            self:SetText(StickyLHLabel())
        end)
        ct1._y = ct1._y - 28
        plainOnlyWidgets[#plainOnlyWidgets+1] = lhSBtn
    end

    -- Text alignment
    SubLbl(ct1, "Text alignment:")
    local ALIGN_OPTIONS = { "Left", "Center", "Right" }
    local ALIGN_MAP     = { Left="LEFT", Center="CENTER", Right="RIGHT" }
    local ALIGN_RMAP    = { LEFT="Left", CENTER="Center", RIGHT="Right" }
    local function GetAlignLabel() return ALIGN_RMAP[cfg.textAlign or "LEFT"] or "Left" end
    local useNativeAlign = useNativeLH
    if useNativeAlign then
        local alignDD = CreateFrame("DropdownButton", nil, ct1, "WowStyle1DropdownTemplate")
        alignDD:SetPoint("TOPLEFT", ct1, "TOPLEFT", 0, ct1._y)
        alignDD:SetWidth(SETTINGS_CW)
        alignDD:SetupMenu(function(_, root)
            for _, opt in ipairs(ALIGN_OPTIONS) do
                local o = opt
                root:CreateRadio(o,
                    function() return GetAlignLabel() == o end,
                    function()
                        cfg.textAlign = ALIGN_MAP[o]; SaveCfg(noteID, cfg)
                        alignDD:GenerateMenu()
                        if stickyFrame and stickyFrame._bodyEb then
                            pcall(function() stickyFrame._bodyEb:SetJustifyH(ALIGN_MAP[o]) end)
                        end
                    end)
            end
        end)
        ct1._y = ct1._y - 36
        plainOnlyWidgets[#plainOnlyWidgets+1] = alignDD
    else
        local alignBtn = BNB.CreateButton(nil, ct1, GetAlignLabel(), SETTINGS_CW, 22)
        alignBtn:SetPoint("TOPLEFT", ct1, "TOPLEFT", 0, ct1._y)
        alignBtn:SetScript("OnClick", function(self)
            local cur = GetAlignLabel()
            local idx = 1
            for i, o in ipairs(ALIGN_OPTIONS) do if o == cur then idx = i; break end end
            idx = (idx % #ALIGN_OPTIONS) + 1
            local opt = ALIGN_OPTIONS[idx]
            cfg.textAlign = ALIGN_MAP[opt]; SaveCfg(noteID, cfg)
            self:SetText(opt)
            if stickyFrame and stickyFrame._bodyEb then
                pcall(function() stickyFrame._bodyEb:SetJustifyH(ALIGN_MAP[opt]) end)
            end
        end)
        ct1._y = ct1._y - 28
        plainOnlyWidgets[#plainOnlyWidgets+1] = alignBtn
    end

    -- Font outline
    SubLbl(ct1, "Font outline:")
    local function GetOutlineLabel() return cfg.fontOutline or "None" end
    local useNativeOutline = useNativeLH
    if useNativeOutline then
        local outlineDD = CreateFrame("DropdownButton", nil, ct1, "WowStyle1DropdownTemplate")
        outlineDD:SetPoint("TOPLEFT", ct1, "TOPLEFT", 0, ct1._y)
        outlineDD:SetWidth(SETTINGS_CW)
        outlineDD:SetupMenu(function(_, root)
            for _, opt in ipairs(OUTLINE_OPTIONS) do
                local o = opt
                root:CreateRadio(o,
                    function() return GetOutlineLabel() == o end,
                    function()
                        cfg.fontOutline = o; SaveCfg(noteID, cfg)
                        outlineDD:GenerateMenu()
                        if stickyFrame then ApplyOutlineToEditBox(stickyFrame._bodyEb, o) end
                    end)
            end
        end)
        ct1._y = ct1._y - 36
        plainOnlyWidgets[#plainOnlyWidgets+1] = outlineDD
    else
        local outlineBtn = BNB.CreateButton(nil, ct1, GetOutlineLabel(), SETTINGS_CW, 22)
        outlineBtn:SetPoint("TOPLEFT", ct1, "TOPLEFT", 0, ct1._y)
        outlineBtn:SetScript("OnClick", function(self)
            local cur = GetOutlineLabel()
            local idx = 1
            for i, o in ipairs(OUTLINE_OPTIONS) do if o == cur then idx = i; break end end
            idx = (idx % #OUTLINE_OPTIONS) + 1
            local opt = OUTLINE_OPTIONS[idx]
            cfg.fontOutline = opt; SaveCfg(noteID, cfg)
            self:SetText(opt)
            if stickyFrame then ApplyOutlineToEditBox(stickyFrame._bodyEb, opt) end
        end)
        ct1._y = ct1._y - 28
        plainOnlyWidgets[#plainOnlyWidgets+1] = outlineBtn
    end

    FinalisePanel(ct1, sf1)

    -- ══════════════════════════════════════════════════════════════════════════
    -- TAB 2 — APPEARANCE
    -- ══════════════════════════════════════════════════════════════════════════
    ct2._y = -8

    -- ── Randomize colors ─────────────────────────────────────────────────────
    -- Picks a random background from a curated palette of warm/cool note colors,
    -- then picks a contrasting text color (light on dark bg, dark on light bg).
    local BG_PALETTE = {
        {0.96, 0.91, 0.68},  -- parchment yellow
        {0.72, 0.85, 0.72},  -- sage green
        {0.70, 0.82, 0.92},  -- sky blue
        {0.90, 0.75, 0.82},  -- dusty rose
        {0.82, 0.78, 0.92},  -- lavender
        {0.92, 0.78, 0.68},  -- terracotta
        {0.68, 0.82, 0.85},  -- seafoam
        {0.95, 0.88, 0.75},  -- warm cream
        {0.75, 0.88, 0.95},  -- ice blue
        {0.88, 0.95, 0.78},  -- lime cream
        {0.20, 0.22, 0.28},  -- dark slate
        {0.14, 0.20, 0.14},  -- dark forest
        {0.18, 0.14, 0.22},  -- dark purple
        {0.22, 0.16, 0.12},  -- dark espresso
    }

    local randBtn = BNB.CreateButton(nil, ct2,
        "Randomize Sticky Note Colors", SETTINGS_CW, 26)
    randBtn:SetPoint("TOPLEFT", ct2, "TOPLEFT", 0, ct2._y)
    randBtn:SetScript("OnClick", function()
        local bg = BG_PALETTE[math.random(#BG_PALETTE)]
        local br, bg2, bb = bg[1], bg[2], bg[3]
        -- Luminance check: pick contrasting text
        local lum = 0.299 * br + 0.587 * bg2 + 0.114 * bb
        local tr, tg, tb
        if lum > 0.5 then
            -- Light bg: dark warm text
            tr = math.random(5, 25) / 100
            tg = math.random(5, 20) / 100
            tb = math.random(5, 15) / 100
        else
            -- Dark bg: light warm text
            tr = math.random(75, 95) / 100
            tg = math.random(70, 90) / 100
            tb = math.random(60, 80) / 100
        end
        cfg.bgR, cfg.bgG, cfg.bgB = br, bg2, bb
        cfg.textR, cfg.textG, cfg.textB = tr, tg, tb
        SaveCfg(noteID, cfg)
        if stickyFrame then
            ApplyConfig(stickyFrame, noteID)
            if stickyFrame._bodyEb then
                pcall(function() stickyFrame._bodyEb:SetTextColor(tr, tg, tb) end)
            end
        end
        -- Repopulate so the color swatches update to reflect new values
        PopulateStickySettings(noteID)
        if f._selectTab then f._selectTab(2) end  -- stay on Appearance tab
    end)
    ct2._y = ct2._y - 32

    Rule(ct2)
    Sec(ct2, "Background")
    local bgSwatch = ColorBtn(ct2, cfg.bgR, cfg.bgG, cfg.bgB, "Click to pick color", function(r,g,b)
        cfg.bgR, cfg.bgG, cfg.bgB = r, g, b
        SaveCfg(noteID, cfg)
        if stickyFrame then ApplyConfig(stickyFrame, noteID) end
    end)
    SubLbl(ct2, "Quick pick:")
    ColorGrid(ct2, function(r,g,b)
        cfg.bgR, cfg.bgG, cfg.bgB = r, g, b
        SaveCfg(noteID, cfg)
        if stickyFrame then ApplyConfig(stickyFrame, noteID) end
        if bgSwatch and bgSwatch._tx then bgSwatch._tx:SetColorTexture(r, g, b) end
    end)

    -- ── Background texture picker ─────────────────────────────────────────────
    -- Forward-declared so the dropdown/button closure can reference it before
    -- the slider is built (same Lua 5.1 upvalue pattern as SyncBorderSliders).
    local SyncColorizeSlider

    SubLbl(ct2, "Background texture:")
    local curTexKey   = cfg.bgTexture or "none"
    local curTexLabel = BgTextureLabel(curTexKey)

    local useNativeTexDrop = C_XMLUtil and C_XMLUtil.GetTemplateInfo
        and C_XMLUtil.GetTemplateInfo("WowStyle1DropdownTemplate")
    if useNativeTexDrop then
        local texDrop = CreateFrame("DropdownButton", nil, ct2, "WowStyle1DropdownTemplate")
        texDrop:SetPoint("TOPLEFT", ct2, "TOPLEFT", 0, ct2._y)
        texDrop:SetWidth(SETTINGS_CW)
        texDrop:SetupMenu(function(_, root)
            for _, t in ipairs(BG_TEXTURES) do
                local entry = t
                root:CreateRadio(entry.label,
                    function() return curTexKey == entry.key end,
                    function()
                        curTexKey   = entry.key
                        curTexLabel = entry.label
                        cfg.bgTexture = curTexKey
                        SaveCfg(noteID, cfg)
                        texDrop:GenerateMenu()
                        if stickyFrame then ApplyConfig(stickyFrame, noteID) end
                        SyncColorizeSlider(curTexKey)
                    end)
            end
        end)
        ct2._y = ct2._y - 36
    else
        -- Fallback: cycle button
        local texBtn = BNB.CreateButton(nil, ct2, curTexLabel, SETTINGS_CW, 22)
        texBtn:SetPoint("TOPLEFT", ct2, "TOPLEFT", 0, ct2._y)
        texBtn:SetScript("OnClick", function(self)
            local idx = 1
            for i, t in ipairs(BG_TEXTURES) do
                if t.key == curTexKey then idx = i; break end
            end
            idx = (idx % #BG_TEXTURES) + 1
            curTexKey   = BG_TEXTURES[idx].key
            curTexLabel = BG_TEXTURES[idx].label
            self:SetText(curTexLabel)
            cfg.bgTexture = curTexKey
            SaveCfg(noteID, cfg)
            if stickyFrame then ApplyConfig(stickyFrame, noteID) end
            SyncColorizeSlider(curTexKey)
        end)
        ct2._y = ct2._y - 28
    end

    -- "Colorize texture %" — lerps the backdrop tint between raw paper (0%, white
    -- tint) and the full chosen colour (100%). Greyed out when texture is "None".
    local slColorize = MakeSlider(ct2, "Colorize texture %", 0, 100,
        math.floor((cfg.bgColorOpacity or 1.0) * 100),
        function(v)
            cfg.bgColorOpacity = v / 100
            SaveCfg(noteID, cfg)
            if stickyFrame then ApplyConfig(stickyFrame, noteID) end
        end)

    SyncColorizeSlider = function(texKey)
        local disabled = (not texKey or texKey == "none")
        pcall(function() slColorize:SetAlpha(disabled and 0.4 or 1.0) end)
        if slColorize.SetEnabled then
            pcall(function() slColorize:SetEnabled(not disabled) end)
        end
    end
    SyncColorizeSlider(curTexKey)

    Rule(ct2)
    Sec(ct2, "Opacity")
    local textOpacitySl = MakeSlider(ct2, "Text opacity %", 10, 100,
        math.floor((cfg.textAlpha or 1.0) * 100),
        function(v)
            cfg.textAlpha = v/100; SaveCfg(noteID, cfg)
            if stickyFrame and stickyFrame._bodyEb then
                pcall(function() stickyFrame._bodyEb:SetAlpha(cfg.textAlpha) end)
            end
        end)
    plainOnlyWidgets[#plainOnlyWidgets+1] = textOpacitySl
    MakeSlider(ct2, "Background opacity %", 0, 100,
        math.floor((cfg.alpha or 0.96) * 100),
        function(v)
            cfg.alpha = v/100; SaveCfg(noteID, cfg)
            if stickyFrame then ApplyBgAlpha(stickyFrame, cfg.alpha) end
        end)

    Rule(ct2)
    Sec(ct2, "Border")
    -- Forward declaration so the dropdown/button closures below can reference it
    -- before the function body is assigned (Lua 5.1 upvalue capture fix).
    local SyncBorderSliders
    local useNativeDrop = C_XMLUtil and C_XMLUtil.GetTemplateInfo
        and C_XMLUtil.GetTemplateInfo("WowStyle1DropdownTemplate")
    if useNativeDrop then
        local curBorder = cfg.borderName or "None"
        local bdd = CreateFrame("DropdownButton", nil, ct2, "WowStyle1DropdownTemplate")
        bdd:SetPoint("TOPLEFT", ct2, "TOPLEFT", 0, ct2._y)
        bdd:SetWidth(SETTINGS_CW)
        bdd:SetupMenu(function(_, root)
            for _, name in ipairs(GetBorderList()) do
                local n = name
                root:CreateRadio(n,
                    function() return curBorder == n end,
                    function()
                        curBorder = n
                        cfg.borderName = n
                        SaveCfg(noteID, cfg)
                        bdd:GenerateMenu()
                        if stickyFrame then ApplyConfig(stickyFrame, noteID) end
                        SyncBorderSliders(n)
                    end)
            end
        end)
        ct2._y = ct2._y - 36
    else
        local curBorder = cfg.borderName or "None"
        local bBtn = BNB.CreateButton(nil, ct2, curBorder, SETTINGS_CW, 22)
        bBtn:SetPoint("TOPLEFT", ct2, "TOPLEFT", 0, ct2._y)
        bBtn:SetScript("OnClick", function(self)
            local borders = GetBorderList()
            local idx2 = 1
            for i2, v2 in ipairs(borders) do if v2 == curBorder then idx2 = i2; break end end
            idx2 = (idx2 % #borders) + 1
            curBorder = borders[idx2]
            self:SetText(curBorder)
            cfg.borderName = curBorder
            SaveCfg(noteID, cfg)
            if stickyFrame then ApplyConfig(stickyFrame, noteID) end
            SyncBorderSliders(curBorder)
        end)
        ct2._y = ct2._y - 28
    end

    -- Border Thickness slider
    local slThickness = MakeSlider(ct2, "Border thickness %", 1, 200, cfg.borderScale or 100,
        function(v)
            cfg.borderScale = math.floor(v)
            SaveCfg(noteID, cfg)
            if stickyFrame then ApplyConfig(stickyFrame, noteID) end
        end)

    -- Border Offset slider
    local slOffset = MakeSlider(ct2, "Border offset px", 0, 12, cfg.borderOffset or 2,
        function(v)
            cfg.borderOffset = math.floor(v)
            SaveCfg(noteID, cfg)
            if stickyFrame then ApplyConfig(stickyFrame, noteID) end
        end)

    -- Border Brightness slider
    local slBrightness = MakeSlider(ct2, "Border brightness %", 10, 500, cfg.borderBrightness or 100,
        function(v)
            cfg.borderBrightness = math.floor(v)
            SaveCfg(noteID, cfg)
            if stickyFrame then ApplyConfig(stickyFrame, noteID) end
        end)

    -- Grey out the three sliders when border is "None" (they have no effect).
    -- Assigned here (after sliders exist) but captured by the closures above
    -- via the forward declaration at the top of the Border section.
    SyncBorderSliders = function(borderName)
        local disabled = (not borderName or borderName == "None")
        local a = disabled and 0.35 or 1.0
        for _, sl in ipairs({ slThickness, slOffset, slBrightness }) do
            if sl then
                sl:SetAlpha(a)
                sl:EnableMouse(not disabled)
                sl:EnableMouseWheel(not disabled)
            end
        end
    end
    SyncBorderSliders(cfg.borderName)

    FinalisePanel(ct2, sf2)

    -- Apply greying to all plain-only controls now that both tabs are fully built.
    -- (Must run after tab 2 so textOpacitySl is in plainOnlyWidgets.)
    SyncPlainOnlyControls()

    -- ══════════════════════════════════════════════════════════════════════════
    -- TAB 3 — SITUATION
    -- Mirror of NoteConfig TAB 3. Reads/writes the same note fields.
    -- Cross-sync: any save here calls BNB.SyncNoteConfig(noteID) so the
    -- NoteConfig Situation tab (if open for the same note) refreshes too.
    -- ══════════════════════════════════════════════════════════════════════════
    ct3._y = -8

    local SIT_PAD = 0   -- content already offset by scroll panel SETTINGS_PAD
    local SIT_CW  = SETTINGS_CW

    -- ── Layout helpers (local to Situation tab) ───────────────────────────────
    local function SitHdr(txt)
        local y = ct3._y
        local l = ct3:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        l:SetPoint("TOPLEFT", ct3, "TOPLEFT", SIT_PAD, y)
        l:SetTextColor(1, 0.82, 0, 1); l:SetText(txt)
        ct3._y = y - 20
    end
    local function SitRule()
        local y = ct3._y
        local t = ct3:CreateTexture(nil, "ARTWORK")
        t:SetHeight(1)
        t:SetPoint("TOPLEFT",  ct3, "TOPLEFT",  SIT_PAD, y)
        t:SetPoint("TOPRIGHT", ct3, "TOPRIGHT", 0, y)
        if skinMode and BNB.GetSkinPreset then
            local p = BNB.GetSkinPreset()
            local br, bg_, bb = BNB.SkinBorderOf(p)
            t:SetColorTexture(br, bg_, bb, 0.8)
            BNB.RegisterSkinRule(t, 0.8)
        else
            t:SetColorTexture(0.28, 0.28, 0.30, 0.8)
        end
        ct3._y = y - 8
    end

    -- Forward-declare so closures below can capture it before assignment
    local SitSelectType
    local SitHideAC
    local SitRefreshCurBind
    local SitRefreshWaypointDisplay

    -- ── Header ────────────────────────────────────────────────────────────────
    SitHdr("Contextual Binding")
    local sitDesc = ct3:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sitDesc:SetPoint("TOPLEFT",  ct3, "TOPLEFT",  SIT_PAD, ct3._y)
    sitDesc:SetPoint("TOPRIGHT", ct3, "TOPRIGHT", 0, ct3._y)
    sitDesc:SetTextColor(0.60, 0.60, 0.60)
    sitDesc:SetText("This note will surface when you enter\nthe matching zone, instance, or area.")
    sitDesc:SetJustifyH("LEFT"); sitDesc:SetWordWrap(true)
    ct3._y = ct3._y - 36
    SitRule()

    -- ── Helpers ───────────────────────────────────────────────────────────────
    local function SitSave(fields)
        BNB.UpdateNote(noteID, fields)
        if BNB.RefreshNoteList then BNB.RefreshNoteList() end
        if BNB.Sticky and BNB.Sticky.RefreshNote then BNB.Sticky.RefreshNote(noteID) end
        -- Cross-sync: refresh NoteConfig Situation tab if open for same note
        if BNB.SyncNoteConfig then BNB.SyncNoteConfig(noteID) end
    end

    -- ── Bind-type dropdown ────────────────────────────────────────────────────
    local SIT_TYPES       = { "none", "zone", "subzone", "instance", "player" }
    local SIT_TYPE_LABELS = { "None (global)", "Zone", "Sub-zone", "Instance", "Player" }
    local sitSelType      = "none"

    local function SitGetTypeLabel(t)
        for i, k in ipairs(SIT_TYPES) do if k == t then return SIT_TYPE_LABELS[i] end end
        return SIT_TYPE_LABELS[1]
    end

    local sitTypeDropdown
    local sitTypeCycleBtn

    local function SitSetTypeText(label)
        if sitTypeDropdown and sitTypeDropdown.Text then sitTypeDropdown.Text:SetText(label) end
        if sitTypeCycleBtn then sitTypeCycleBtn:SetText(label) end
    end

    local useNativeSit3 = C_XMLUtil and C_XMLUtil.GetTemplateInfo
        and C_XMLUtil.GetTemplateInfo("WowStyle1DropdownTemplate")

    if useNativeSit3 then
        sitTypeDropdown = CreateFrame("DropdownButton", "BNBStickySetSituTypeDD", ct3,
            "WowStyle1DropdownTemplate")
        sitTypeDropdown:SetPoint("TOPLEFT",  ct3, "TOPLEFT",  SIT_PAD, ct3._y)
        sitTypeDropdown:SetPoint("TOPRIGHT", ct3, "TOPRIGHT", 0, ct3._y)
        sitTypeDropdown:SetHeight(24)
        local function RebuildSitTypeMenu()
            sitTypeDropdown:SetupMenu(function(_, root)
                for i, label in ipairs(SIT_TYPE_LABELS) do
                    local key = SIT_TYPES[i]
                    root:CreateRadio(label,
                        function() return sitSelType == key end,
                        function()
                            sitSelType = key
                            sitTypeDropdown:GenerateMenu()
                            SitSelectType(key)
                        end)
                end
            end)
        end
        RebuildSitTypeMenu()
        ct3._sitRebuildTypeMenu = RebuildSitTypeMenu
    else
        sitTypeCycleBtn = BNB.CreateButton(nil, ct3, SitGetTypeLabel(sitSelType), SIT_CW, 24)
        sitTypeCycleBtn:SetPoint("TOPLEFT", ct3, "TOPLEFT", SIT_PAD, ct3._y)
        sitTypeCycleBtn:SetScript("OnClick", function(self)
            local idx = 1
            for i, k in ipairs(SIT_TYPES) do if k == sitSelType then idx = i; break end end
            idx = (idx % #SIT_TYPES) + 1
            sitSelType = SIT_TYPES[idx]
            self:SetText(SIT_TYPE_LABELS[idx])
            SitSelectType(sitSelType)
        end)
    end
    ct3._y = ct3._y - 30

    -- ── Value row ─────────────────────────────────────────────────────────────
    local sitValueRow = CreateFrame("Frame", nil, ct3)
    sitValueRow:SetPoint("TOPLEFT",  ct3, "TOPLEFT",  SIT_PAD, ct3._y)
    sitValueRow:SetPoint("TOPRIGHT", ct3, "TOPRIGHT", 0, ct3._y)
    sitValueRow:SetHeight(28); sitValueRow:Hide()

    local sitValueLbl = sitValueRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sitValueLbl:SetPoint("LEFT", sitValueRow, "LEFT", 0, 0)
    sitValueLbl:SetWidth(65); sitValueLbl:SetJustifyH("LEFT")
    sitValueLbl:SetTextColor(0.78, 0.78, 0.78); sitValueLbl:SetText("Value:")

    local sitValueEb = CreateFrame("EditBox", nil, sitValueRow,
        "BackdropTemplate")
    BNB.EnsureBackdrop(sitValueEb)
    sitValueEb:SetPoint("LEFT",  sitValueLbl, "RIGHT", 6, 0)
    sitValueEb:SetPoint("RIGHT", sitValueRow, "RIGHT", -26, 0)
    sitValueEb:SetHeight(20); sitValueEb:SetFontObject("GameFontNormal")
    sitValueEb:SetAutoFocus(false); sitValueEb:SetMaxLetters(128)
    sitValueEb:SetTextInsets(4, 4, 0, 0); sitValueEb:SetTextColor(1, 1, 1)
    BNB.SetBackdropDark(sitValueEb)
    sitValueEb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local ASSETS3 = "Interface\\AddOns\\BigNoteBox\\Assets\\"
    local sitBrowseBtn = CreateFrame("Button", nil, sitValueRow)
    sitBrowseBtn:SetSize(20, 20)
    sitBrowseBtn:SetPoint("RIGHT", sitValueRow, "RIGHT", 0, 0)
    local sitBrowseTx = sitBrowseBtn:CreateTexture(nil, "ARTWORK")
    sitBrowseTx:SetAllPoints(); sitBrowseTx:SetTexture(ASSETS3 .. "Overlay\\ov-situation")
    sitBrowseBtn:SetScript("OnEnter", function(self)
        self:SetAlpha(1.0)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Browse zones and instances", 1, 1, 1)
        GameTooltip:AddLine("Click to open the zone browser", 0.78, 0.78, 0.78)
        GameTooltip:Show()
    end)
    sitBrowseBtn:SetScript("OnLeave", function(self)
        self:SetAlpha(0.7); GameTooltip:Hide()
    end)
    sitBrowseBtn:SetAlpha(0.7); sitBrowseBtn:Hide()

    -- ── Autocomplete ──────────────────────────────────────────────────────────
    local sitAcFrame = BNB.CreateBackdropFrame("Frame", nil, ct3)
    BNB.SetBackdrop(sitAcFrame, 0.08, 0.08, 0.10, 0.97, 0.35, 0.35, 0.38, 1)
    sitAcFrame:SetPoint("TOPLEFT",  sitValueRow, "BOTTOMLEFT",  0, -2)
    sitAcFrame:SetPoint("TOPRIGHT", sitValueRow, "BOTTOMRIGHT", 0, -2)
    sitAcFrame:SetFrameLevel(ct3:GetFrameLevel() + 30)
    sitAcFrame:Hide()

    local _sitAcRows  = {}
    local _sitAcTimer = nil

    SitHideAC = function()
        sitAcFrame:Hide()
        if _sitAcTimer then _sitAcTimer:Cancel(); _sitAcTimer = nil end
    end

    local function SitShowAC(matches)
        if #matches == 0 then SitHideAC(); return end
        local ROW_H_AC = 22
        local maxRows  = math.min(#matches, 7)
        sitAcFrame:SetHeight(maxRows * ROW_H_AC + 4)
        for i = 1, maxRows do
            if not _sitAcRows[i] then
                local row = CreateFrame("Button", nil, sitAcFrame)
                row:SetHeight(ROW_H_AC)
                row:SetPoint("TOPLEFT",  sitAcFrame, "TOPLEFT",  4, -2 - (i-1)*ROW_H_AC)
                row:SetPoint("TOPRIGHT", sitAcFrame, "TOPRIGHT", -4, -2 - (i-1)*ROW_H_AC)
                local hi = row:CreateTexture(nil, "HIGHLIGHT")
                hi:SetAllPoints(); hi:SetColorTexture(1, 1, 1, 0.08)
                local nameLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                nameLbl:SetPoint("LEFT",  row, "LEFT",  4, 0)
                nameLbl:SetPoint("RIGHT", row, "RIGHT", -80, 0)
                nameLbl:SetJustifyH("LEFT"); nameLbl:SetMaxLines(1)
                nameLbl:SetTextColor(1, 1, 1)
                row._nameLbl = nameLbl
                local contLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                contLbl:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                contLbl:SetWidth(76); contLbl:SetJustifyH("RIGHT"); contLbl:SetMaxLines(1)
                contLbl:SetTextColor(0.50, 0.50, 0.50)
                row._contLbl = contLbl
                _sitAcRows[i] = row
            end
            local row = _sitAcRows[i]; local m = matches[i]
            row._nameLbl:SetText(m.name); row._contLbl:SetText(m.continent or "")
            row:SetPoint("TOPLEFT",  sitAcFrame, "TOPLEFT",  4, -2 - (i-1)*ROW_H_AC)
            row:SetPoint("TOPRIGHT", sitAcFrame, "TOPRIGHT", -4, -2 - (i-1)*ROW_H_AC)
            local capName = m.name
            row:SetScript("OnClick", function() sitValueEb:SetText(capName); SitHideAC(); sitValueEb:SetFocus() end)
            row:Show()
        end
        for i = maxRows + 1, #_sitAcRows do _sitAcRows[i]:Hide() end
        sitAcFrame:Show()
    end

    sitValueEb:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local text = self:GetText() or ""
        if #text < 2 then SitHideAC(); return end
        if BNB.ZonePicker and BNB.ZonePicker.IsShown and BNB.ZonePicker.IsShown() then
            BNB.ZonePicker.Close()
        end
        if _sitAcTimer then _sitAcTimer:Cancel() end
        _sitAcTimer = C_Timer.NewTimer(0.15, function()
            if BNB.ZonePicker and BNB.ZonePicker.GetMatches then
                local matches = BNB.ZonePicker.GetMatches(text, sitSelType, 7)
                SitShowAC(matches)
            end
        end)
    end)
    sitValueEb:HookScript("OnEditFocusLost", function()
        C_Timer.After(0.2, function()
            if not sitAcFrame:IsMouseOver() then SitHideAC() end
        end)
    end)

    sitBrowseBtn:SetScript("OnClick", function()
        SitHideAC()
        if BNB.ZonePicker then
            if BNB.ZonePicker.IsShown and BNB.ZonePicker.IsShown() then
                BNB.ZonePicker.Close()
            else
                BNB.ZonePicker.Open(sitValueRow, function(name, kind)
                    sitValueEb:SetText(name)
                end, sitSelType)
            end
        end
    end)

    -- ── Use Current / Apply / Clear ───────────────────────────────────────────
    local sitUseCurrentBtn = BNB.CreateButton(nil, ct3, "Use Current", 90, 20)
    sitUseCurrentBtn:SetPoint("TOPLEFT", sitValueRow, "BOTTOMLEFT", 0, -4)
    sitUseCurrentBtn:Hide()

    local sitSaveCtxBtn = BNB.CreateButton(nil, ct3, "Apply", 60, 22)
    sitSaveCtxBtn:SetPoint("TOPLEFT", sitUseCurrentBtn, "TOPRIGHT", 8, 0)
    sitSaveCtxBtn:Hide()

    local sitClearCtxBtn = BNB.CreateButton(nil, ct3, "Clear", 52, 22)
    sitClearCtxBtn:SetPoint("TOPLEFT", sitSaveCtxBtn, "TOPRIGHT", 6, 0)
    sitClearCtxBtn:Hide()

    -- ── Current binding display ───────────────────────────────────────────────
    local sitCurBindValue = ct3:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge3")
    sitCurBindValue:SetPoint("BOTTOMLEFT",  ct3, "BOTTOMLEFT",  SIT_PAD, SIT_PAD + 6)
    sitCurBindValue:SetPoint("BOTTOMRIGHT", ct3, "BOTTOMRIGHT", 0, SIT_PAD + 6)
    sitCurBindValue:SetJustifyH("CENTER"); sitCurBindValue:SetWordWrap(false)
    sitCurBindValue:SetMaxLines(1); sitCurBindValue:SetTextColor(1, 1, 1); sitCurBindValue:SetText("")

    local sitCurBindHeader = ct3:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sitCurBindHeader:SetPoint("BOTTOMLEFT",  sitCurBindValue, "TOPLEFT",  0, 4)
    sitCurBindHeader:SetPoint("BOTTOMRIGHT", sitCurBindValue, "TOPRIGHT", 0, 4)
    sitCurBindHeader:SetJustifyH("CENTER"); sitCurBindHeader:SetWordWrap(false)
    sitCurBindHeader:SetMaxLines(1); sitCurBindHeader:SetTextColor(0.55, 0.55, 0.55); sitCurBindHeader:SetText("")

    -- ── Display mode dropdown ─────────────────────────────────────────────────
    local SIT_DISPLAY_MODES  = { "popup", "sticky", "both" }
    local SIT_DISPLAY_LABELS = { "Show popup notification", "Show as sticky note", "Both -- popup and sticky" }
    local sitSelDisplay = "popup"

    local SIT_LEAVE_MODES  = { "keep", "bt-minimize", "hide" }
    local SIT_LEAVE_LABELS = { "Keep open", "Minimize", "Hide" }
    local sitSelLeave = "keep"

    local sitDispDiv = ct3:CreateTexture(nil, "ARTWORK")
    sitDispDiv:SetHeight(1)
    sitDispDiv:SetPoint("TOPLEFT",  sitUseCurrentBtn, "BOTTOMLEFT",   0, -26)
    sitDispDiv:SetPoint("TOPRIGHT", ct3,              "TOPRIGHT",     0, 0)
    if skinMode and BNB.GetSkinPreset then
        local p = BNB.GetSkinPreset()
        local br, bg_, bb = BNB.SkinBorderOf(p)
        sitDispDiv:SetColorTexture(br, bg_, bb, 0.8)
        BNB.RegisterSkinRule(sitDispDiv, 0.8)
    else
        sitDispDiv:SetColorTexture(0.28, 0.28, 0.30, 0.8)
    end
    sitDispDiv:Hide()

    local sitDispLabel = ct3:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sitDispLabel:SetPoint("TOPLEFT", sitDispDiv, "BOTTOMLEFT", 0, -6)
    sitDispLabel:SetText("When triggered, show as:")
    sitDispLabel:SetTextColor(0.78, 0.78, 0.78); sitDispLabel:Hide()

    local function SitGetDispLabel(m)
        for i, k in ipairs(SIT_DISPLAY_MODES) do if k == m then return SIT_DISPLAY_LABELS[i] end end
        return SIT_DISPLAY_LABELS[1]
    end
    local function SitSetDispText(label)
        if sitDispDropdown and sitDispDropdown.Text then sitDispDropdown.Text:SetText(label) end
        if sitDispCycleBtn then sitDispCycleBtn:SetText(label) end
    end
    local function SitOnDispChanged(mode)
        sitSelDisplay = mode
        if mode == "sticky" or mode == "both" then
            SitSave({ contextDisplay = mode })
        else
            BNB.UpdateNote(noteID, { _clear = {"contextDisplay"} })
            if BNB.RefreshNoteList then BNB.RefreshNoteList() end
            if BNB.SyncNoteConfig  then BNB.SyncNoteConfig(noteID) end
        end
    end

    local useNativeDisp3 = useNativeSit3
    local sitDispDropdown
    local sitDispCycleBtn

    if useNativeDisp3 then
        sitDispDropdown = CreateFrame("DropdownButton", "BNBStickySetDispDD", ct3,
            "WowStyle1DropdownTemplate")
        sitDispDropdown:SetPoint("TOPLEFT",  sitDispLabel, "BOTTOMLEFT",  0, -4)
        sitDispDropdown:SetPoint("TOPRIGHT", ct3,          "TOPRIGHT",    0, 0)
        sitDispDropdown:SetHeight(24)
        local function RebuildDispMenu3()
            sitDispDropdown:SetupMenu(function(_, root)
                for i, label in ipairs(SIT_DISPLAY_LABELS) do
                    local key = SIT_DISPLAY_MODES[i]
                    root:CreateRadio(label,
                        function() return sitSelDisplay == key end,
                        function()
                            sitSelDisplay = key
                            sitDispDropdown:GenerateMenu()
                            SitOnDispChanged(key)
                        end)
                end
            end)
        end
        RebuildDispMenu3()
        sitDispDropdown:Hide()
        ct3._sitRebuildDispMenu = RebuildDispMenu3
    else
        sitDispCycleBtn = BNB.CreateButton(nil, ct3, SitGetDispLabel(sitSelDisplay), SIT_CW, 24)
        sitDispCycleBtn:SetPoint("TOPLEFT", sitDispLabel, "BOTTOMLEFT", 0, -4)
        sitDispCycleBtn:SetScript("OnClick", function(self)
            local idx = 1
            for i, k in ipairs(SIT_DISPLAY_MODES) do if k == sitSelDisplay then idx = i; break end end
            idx = (idx % #SIT_DISPLAY_MODES) + 1
            sitSelDisplay = SIT_DISPLAY_MODES[idx]
            self:SetText(SIT_DISPLAY_LABELS[idx])
            SitOnDispChanged(sitSelDisplay)
        end)
        sitDispCycleBtn:Hide()
    end

    -- ── Leave action dropdown ─────────────────────────────────────────────────
    local function SitGetLeaveLabel(m)
        for i, k in ipairs(SIT_LEAVE_MODES) do if k == m then return SIT_LEAVE_LABELS[i] end end
        return SIT_LEAVE_LABELS[1]
    end
    local function SitSetLeaveText(label)
        if sitLeaveDropdown and sitLeaveDropdown.Text then sitLeaveDropdown.Text:SetText(label) end
        if sitLeaveCycleBtn then sitLeaveCycleBtn:SetText(label) end
    end
    local function SitOnLeaveChanged(mode)
        sitSelLeave = mode
        if mode == "keep" then
            BNB.UpdateNote(noteID, { _clear = {"contextLeave"} })
        else
            SitSave({ contextLeave = mode })
            return  -- SitSave already calls SyncNoteConfig
        end
        if BNB.RefreshNoteList then BNB.RefreshNoteList() end
        if BNB.SyncNoteConfig  then BNB.SyncNoteConfig(noteID) end
    end

    local sitLeaveDiv = ct3:CreateTexture(nil, "ARTWORK")
    sitLeaveDiv:SetHeight(1)
    sitLeaveDiv:SetPoint("TOPLEFT",  sitDispDiv, "TOPLEFT",  0, -52)
    sitLeaveDiv:SetPoint("TOPRIGHT", ct3,        "TOPRIGHT", 0, 0)
    if skinMode and BNB.GetSkinPreset then
        local p = BNB.GetSkinPreset()
        local br, bg_, bb = BNB.SkinBorderOf(p)
        sitLeaveDiv:SetColorTexture(br, bg_, bb, 0.8)
        BNB.RegisterSkinRule(sitLeaveDiv, 0.8)
    else
        sitLeaveDiv:SetColorTexture(0.28, 0.28, 0.30, 0.8)
    end
    sitLeaveDiv:Hide()

    local sitLeaveLabel = ct3:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sitLeaveLabel:SetPoint("TOPLEFT", sitLeaveDiv, "BOTTOMLEFT", 0, -6)
    sitLeaveLabel:SetText("When you leave the area:")
    sitLeaveLabel:SetTextColor(0.78, 0.78, 0.78); sitLeaveLabel:Hide()

    local useNativeLeave3 = useNativeDisp3
    local sitLeaveDropdown
    local sitLeaveCycleBtn

    if useNativeLeave3 then
        sitLeaveDropdown = CreateFrame("DropdownButton", "BNBStickySetLeaveDD", ct3,
            "WowStyle1DropdownTemplate")
        sitLeaveDropdown:SetPoint("TOPLEFT",  sitLeaveLabel, "BOTTOMLEFT",  0, -4)
        sitLeaveDropdown:SetPoint("TOPRIGHT", ct3,           "TOPRIGHT",    0, 0)
        sitLeaveDropdown:SetHeight(24)
        local function RebuildLeaveMenu3()
            sitLeaveDropdown:SetupMenu(function(_, root)
                for i, label in ipairs(SIT_LEAVE_LABELS) do
                    local key = SIT_LEAVE_MODES[i]
                    root:CreateRadio(label,
                        function() return sitSelLeave == key end,
                        function()
                            sitSelLeave = key
                            sitLeaveDropdown:GenerateMenu()
                            SitOnLeaveChanged(key)
                        end)
                end
            end)
        end
        RebuildLeaveMenu3()
        sitLeaveDropdown:Hide()
        ct3._sitRebuildLeaveMenu = RebuildLeaveMenu3
    else
        sitLeaveCycleBtn = BNB.CreateButton(nil, ct3, SitGetLeaveLabel(sitSelLeave), SIT_CW, 24)
        sitLeaveCycleBtn:SetPoint("TOPLEFT", sitLeaveLabel, "BOTTOMLEFT", 0, -4)
        sitLeaveCycleBtn:SetScript("OnClick", function(self)
            local idx = 1
            for i, k in ipairs(SIT_LEAVE_MODES) do if k == sitSelLeave then idx = i; break end end
            idx = (idx % #SIT_LEAVE_MODES) + 1
            sitSelLeave = SIT_LEAVE_MODES[idx]
            self:SetText(SIT_LEAVE_LABELS[idx])
            SitOnLeaveChanged(sitSelLeave)
        end)
        sitLeaveCycleBtn:Hide()
    end

    local function SitShowDispControls(show)
        if show then
            sitDispDiv:Show(); sitDispLabel:Show()
            if sitDispDropdown  then sitDispDropdown:Show()  end
            if sitDispCycleBtn  then sitDispCycleBtn:Show()  end
            sitLeaveDiv:Show(); sitLeaveLabel:Show()
            if sitLeaveDropdown then sitLeaveDropdown:Show() end
            if sitLeaveCycleBtn then sitLeaveCycleBtn:Show() end
        else
            sitDispDiv:Hide(); sitDispLabel:Hide()
            if sitDispDropdown  then sitDispDropdown:Hide()  end
            if sitDispCycleBtn  then sitDispCycleBtn:Hide()  end
            sitLeaveDiv:Hide(); sitLeaveLabel:Hide()
            if sitLeaveDropdown then sitLeaveDropdown:Hide() end
            if sitLeaveCycleBtn then sitLeaveCycleBtn:Hide() end
        end
    end

    -- ── Refresh current-binding label ─────────────────────────────────────────
    local SIT_KIND_LABELS = { zone="Zone", subzone="Sub-zone", instance="Instance", player="Player" }
    local SIT_BIND_MAX_W  = SETTINGS_CW - SIT_PAD * 2
    local SIT_BIND_DEF_SZ = 20
    local SIT_BIND_MIN_SZ = 11

    SitRefreshCurBind = function()
        local n3  = BNB.GetNote(noteID)
        local ctx = n3 and n3.context
        if ctx and ctx ~= "" then
            local kind, value
            if BNB.DecodeContext then kind, value = BNB.DecodeContext(ctx) end
            local kindLabel = SIT_KIND_LABELS[kind] or kind or "?"
            sitCurBindHeader:SetText("Currently bound to " .. kindLabel .. ":")
            sitCurBindValue:SetText(value or "?")
            local path = sitCurBindValue:GetFont()
            if path then
                pcall(function() sitCurBindValue:SetFont(path, SIT_BIND_DEF_SZ, "") end)
                local sw = sitCurBindValue:GetStringWidth() or 0
                if sw > SIT_BIND_MAX_W then
                    local sz = math.max(SIT_BIND_MIN_SZ, math.floor(SIT_BIND_DEF_SZ * SIT_BIND_MAX_W / sw))
                    pcall(function() sitCurBindValue:SetFont(path, sz, "") end)
                end
            end
        else
            sitCurBindHeader:SetText("|cff666666No binding|r")
            local path = sitCurBindValue:GetFont()
            if path then pcall(function() sitCurBindValue:SetFont(path, SIT_BIND_DEF_SZ, "") end) end
            sitCurBindValue:SetText("|cff666666Note is global.|r")
        end
    end

    -- ── SelectType ────────────────────────────────────────────────────────────
    SitSelectType = function(t)
        sitSelType = t
        local needsValue = (t ~= "none")
        sitValueRow:SetShown(needsValue)
        sitUseCurrentBtn:SetShown(needsValue)
        sitSaveCtxBtn:SetShown(needsValue)
        sitClearCtxBtn:SetShown(true)
        SitShowDispControls(needsValue)
        local canBrowse = (t == "zone" or t == "instance")
        sitBrowseBtn:SetShown(needsValue and canBrowse)
        SitHideAC()
        if BNB.ZonePicker and BNB.ZonePicker.Close then BNB.ZonePicker.Close() end
        if t == "zone"     then sitValueLbl:SetText("Zone:")
        elseif t == "subzone"  then sitValueLbl:SetText("Sub-zone:")
        elseif t == "instance" then sitValueLbl:SetText("Instance:")
        elseif t == "player"   then sitValueLbl:SetText("Player:")
        end
    end

    -- ── Use Current ───────────────────────────────────────────────────────────
    sitUseCurrentBtn:SetScript("OnClick", function()
        local val = ""
        if sitSelType == "zone" then
            val = GetZoneText() or ""
        elseif sitSelType == "subzone" then
            val = GetSubZoneText and GetSubZoneText() or ""
        elseif sitSelType == "instance" then
            val = (GetInstanceInfo and select(1, GetInstanceInfo())) or GetRealZoneText() or ""
        elseif sitSelType == "player" then
            val = UnitName("target") or ""
        end
        if sitValueEb then sitValueEb:SetText(val) end
    end)

    -- ── Apply ─────────────────────────────────────────────────────────────────
    sitSaveCtxBtn:SetScript("OnClick", function()
        local val = sitValueEb and sitValueEb:GetText() or ""
        val = val:match("^%s*(.-)%s*$") or ""
        if sitSelType == "none" or val == "" then
            BNB.UpdateNote(noteID, { _clear = {"context"} })
        else
            BNB.UpdateNote(noteID, { context = sitSelType .. ":" .. val })
        end
        SitRefreshCurBind()
        if BNB.RefreshNoteList     then BNB.RefreshNoteList()     end
        if BNB.CheckContextualNotes then BNB.CheckContextualNotes() end
        if BNB.SyncNoteConfig      then BNB.SyncNoteConfig(noteID) end
        BNB:Print("Context binding saved.")
    end)

    -- ── Clear ─────────────────────────────────────────────────────────────────
    sitClearCtxBtn:SetScript("OnClick", function()
        BNB.UpdateNote(noteID, { _clear = {"context", "contextDisplay", "contextLeave"} })
        if sitValueEb then sitValueEb:SetText("") end
        sitSelType = "none"; sitSelDisplay = "popup"; sitSelLeave = "keep"
        SitSetTypeText(SIT_TYPE_LABELS[1])
        SitSetDispText(SitGetDispLabel("popup"))
        SitSetLeaveText(SitGetLeaveLabel("keep"))
        if sitTypeDropdown  and sitTypeDropdown.GenerateMenu  then sitTypeDropdown:GenerateMenu()  end
        if sitDispDropdown  and sitDispDropdown.GenerateMenu  then sitDispDropdown:GenerateMenu()  end
        if sitLeaveDropdown and sitLeaveDropdown.GenerateMenu then sitLeaveDropdown:GenerateMenu() end
        SitSelectType("none")
        sitClearCtxBtn:Hide()
        SitRefreshCurBind()
        -- Remove any active waypoint for this note
        local uid = BNB._autoWaypoints and BNB._autoWaypoints[noteID]
        if uid then
            if TomTom and TomTom.RemoveWaypoint and type(uid) == "table" then
                pcall(function() TomTom:RemoveWaypoint(uid) end)
            elseif uid == true and C_Map and C_Map.ClearUserWaypoint then
                pcall(function() C_Map.ClearUserWaypoint() end)
            end
            BNB._autoWaypoints[noteID] = nil
        end
        if BNB.RefreshNoteList     then BNB.RefreshNoteList()     end
        if BNB.CheckContextualNotes then BNB.CheckContextualNotes() end
        if BNB.SyncNoteConfig      then BNB.SyncNoteConfig(noteID) end
    end)

    -- ── Waypoint section ──────────────────────────────────────────────────────
    local function SitHasWPAddon()   return TomTom and TomTom.AddWaypoint end
    local function SitHasRetailPin() return C_Map and C_Map.SetUserWaypoint end
    local function SitWPAvailable()  return SitHasWPAddon() or SitHasRetailPin() end

    local sitWpDiv = ct3:CreateTexture(nil, "ARTWORK")
    sitWpDiv:SetHeight(1)
    sitWpDiv:SetPoint("TOPLEFT",  sitLeaveDiv, "TOPLEFT",  0, -90)
    sitWpDiv:SetPoint("TOPRIGHT", ct3,         "TOPRIGHT", 0, 0)
    if skinMode and BNB.GetSkinPreset then
        local p = BNB.GetSkinPreset()
        local br, bg_, bb = BNB.SkinBorderOf(p)
        sitWpDiv:SetColorTexture(br, bg_, bb, 0.8)
        BNB.RegisterSkinRule(sitWpDiv, 0.8)
    else
        sitWpDiv:SetColorTexture(0.28, 0.28, 0.30, 0.8)
    end
    sitWpDiv:Hide()

    local sitWpHdr = ct3:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sitWpHdr:SetPoint("TOPLEFT", sitWpDiv, "BOTTOMLEFT", 0, -6)
    sitWpHdr:SetTextColor(1, 0.82, 0, 1); sitWpHdr:SetText("Waypoint"); sitWpHdr:Hide()

    local sitWpStatusTag = ct3:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sitWpStatusTag:SetPoint("LEFT", sitWpHdr, "RIGHT", 6, 0); sitWpStatusTag:Hide()

    local function SitRefreshWPStatusTag()
        if SitHasWPAddon() then
            sitWpStatusTag:SetText(SitHasRetailPin() and "(Enhanced)" or "(Addon installed)")
            sitWpStatusTag:SetTextColor(0.4, 1, 0.4)
        elseif SitHasRetailPin() then
            sitWpStatusTag:SetText("(Basic)"); sitWpStatusTag:SetTextColor(0.85, 0.70, 0.2)
        else
            sitWpStatusTag:SetText("(Addon required)"); sitWpStatusTag:SetTextColor(0.85, 0.30, 0.25)
        end
    end

    local sitWpInfoLbl = ct3:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sitWpInfoLbl:SetPoint("LEFT", sitWpStatusTag, "RIGHT", 4, 0)
    sitWpInfoLbl:SetText("|cff88bbff?|r"); sitWpInfoLbl:Hide()

    -- Waypoint info popup (reuse same popup anchor pattern as NoteConfig)
    local sitWpInfoPopup = nil
    local function SitShowWPInfoPopup()
        if sitWpInfoPopup then
            if sitWpInfoPopup:IsShown() then sitWpInfoPopup:Hide(); return end
        end
        if not sitWpInfoPopup then
            local fp = BNB.CreateBackdropFrame("Frame", "BNBStickyWaypointInfoPopup", UIParent)
            fp:SetSize(310, 230); fp:SetFrameStrata("DIALOG"); fp:SetClampedToScreen(true)
            fp:EnableMouse(true); fp:SetMovable(true)
            fp:RegisterForDrag("LeftButton")
            fp:SetScript("OnDragStart", fp.StartMoving); fp:SetScript("OnDragStop", fp.StopMovingOrSizing)
            BNB.SetBackdrop(fp, 0.08, 0.08, 0.11, 0.96, 0.35, 0.35, 0.38, 1)
            local ptitle = fp:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            ptitle:SetPoint("TOPLEFT", fp, "TOPLEFT", 14, -12)
            ptitle:SetTextColor(1, 0.82, 0); ptitle:SetText("Waypoint Support")
            local pclose = CreateFrame("Button", nil, fp); pclose:SetSize(20, 20)
            pclose:SetPoint("TOPRIGHT", fp, "TOPRIGHT", -6, -6)
            local pcloseLbl = pclose:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            pcloseLbl:SetAllPoints(); pcloseLbl:SetText("|cffaaaaaa×|r")
            pclose:SetScript("OnClick", function() fp:Hide() end)
            pclose:SetScript("OnEnter", function() pcloseLbl:SetText("|cffff4444×|r") end)
            pclose:SetScript("OnLeave", function() pcloseLbl:SetText("|cffaaaaaa×|r") end)
            fp._statusLbl = fp:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fp._statusLbl:SetPoint("TOPLEFT", ptitle, "BOTTOMLEFT", 0, -10)
            fp._statusLbl:SetWidth(280); fp._statusLbl:SetJustifyH("LEFT")
            fp._descLbl = fp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fp._descLbl:SetPoint("TOPLEFT", fp._statusLbl, "BOTTOMLEFT", 0, -6)
            fp._descLbl:SetWidth(280); fp._descLbl:SetJustifyH("LEFT"); fp._descLbl:SetWordWrap(true)
            fp._descLbl:SetTextColor(0.78, 0.78, 0.78)
            local linksHdr = fp:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            linksHdr:SetPoint("TOPLEFT", fp._descLbl, "BOTTOMLEFT", 0, -14)
            linksHdr:SetText("Recommended addons:"); linksHdr:SetTextColor(1, 1, 1)
            local wpuiBtn = BNB.CreateButton(nil, fp, "WaypointUI (CurseForge)", 200, 22)
            wpuiBtn:SetPoint("TOPLEFT", linksHdr, "BOTTOMLEFT", 0, -6)
            wpuiBtn:SetScript("OnClick", function()
                BNB:Print("Get WaypointUI: |cffffff00https://www.curseforge.com/wow/addons/waypointui|r")
            end)
            local ttBtn2 = BNB.CreateButton(nil, fp, "TomTom (CurseForge)", 200, 22)
            ttBtn2:SetPoint("TOPLEFT", wpuiBtn, "BOTTOMLEFT", 0, -4)
            ttBtn2:SetScript("OnClick", function()
                BNB:Print("Get TomTom: |cffffff00https://www.curseforge.com/wow/addons/tomtom|r")
            end)
            sitWpInfoPopup = fp
        end
        local fp = sitWpInfoPopup
        if SitHasWPAddon() then
            fp._statusLbl:SetText("|cff66ff66Waypoint addon detected.|r")
            fp._descLbl:SetText("Full waypoint support is available.")
        elseif SitHasRetailPin() then
            fp._statusLbl:SetText("|cffffaa00Using built-in map pin (basic).|r")
            fp._descLbl:SetText("Install an addon below for the full experience.")
        else
            fp._statusLbl:SetText("|cffff5555No waypoint support detected.|r")
            fp._descLbl:SetText("Install one of the addons below to enable waypoints.")
        end
        fp:ClearAllPoints()
        if _stickySettingsFrame then
            fp:SetPoint("TOPLEFT", _stickySettingsFrame, "TOPRIGHT", 4, 0)
        else
            fp:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
        end
        fp:Show()
    end

    local sitWpInfoHit = CreateFrame("Button", nil, ct3)
    sitWpInfoHit:SetPoint("LEFT",  sitWpStatusTag, "LEFT",  -2, 0)
    sitWpInfoHit:SetPoint("RIGHT", sitWpInfoLbl,   "RIGHT",  4, 0)
    sitWpInfoHit:SetHeight(18); sitWpInfoHit:Hide()
    sitWpInfoHit:SetScript("OnClick", SitShowWPInfoPopup)
    sitWpInfoHit:SetScript("OnEnter", function(self)
        sitWpInfoLbl:SetText("|cffbbddff?|r")
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Click for waypoint addon info", 0.55, 0.85, 1); GameTooltip:Show()
    end)
    sitWpInfoHit:SetScript("OnLeave", function()
        sitWpInfoLbl:SetText("|cff88bbff?|r"); GameTooltip:Hide()
    end)

    local sitWpDesc = ct3:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sitWpDesc:SetPoint("TOPLEFT",  sitWpHdr,  "BOTTOMLEFT",  0, -4)
    sitWpDesc:SetPoint("TOPRIGHT", ct3,       "TOPRIGHT",    0, 0)
    sitWpDesc:SetJustifyH("LEFT"); sitWpDesc:SetWordWrap(true)
    sitWpDesc:SetTextColor(0.60, 0.60, 0.60)
    sitWpDesc:SetText("Pin your current map position to this note.\nUse Navigate to send it to TomTom or the map.")
    sitWpDesc:Hide()

    local SIT_BTN_W = 72; local SIT_BTN_H = 22; local SIT_BTN_GAP = 6
    local sitWpPinBtn   = BNB.CreateButton(nil, ct3, "Pin Here", SIT_BTN_W, SIT_BTN_H)
    sitWpPinBtn:SetPoint("TOPLEFT", sitWpDesc, "BOTTOMLEFT", 0, -6); sitWpPinBtn:Hide()
    local sitWpNavBtn   = BNB.CreateButton(nil, ct3, "Navigate", SIT_BTN_W, SIT_BTN_H)
    sitWpNavBtn:SetPoint("LEFT", sitWpPinBtn, "RIGHT", SIT_BTN_GAP, 0); sitWpNavBtn:Hide()
    local sitWpClearBtn = BNB.CreateButton(nil, ct3, "Clear WP",  SIT_BTN_W, SIT_BTN_H)
    sitWpClearBtn:SetPoint("TOPLEFT", sitWpPinBtn, "BOTTOMLEFT", 0, -SIT_BTN_GAP); sitWpClearBtn:Hide()
    local sitWpManualBtn = BNB.CreateButton(nil, ct3, "Manual", SIT_BTN_W, SIT_BTN_H)
    sitWpManualBtn:SetPoint("LEFT", sitWpClearBtn, "RIGHT", SIT_BTN_GAP, 0); sitWpManualBtn:Hide()

    -- Manual coord row
    local sitWpManualRow = CreateFrame("Frame", nil, ct3)
    sitWpManualRow:SetHeight(22)
    sitWpManualRow:SetPoint("TOPLEFT",  sitWpClearBtn, "BOTTOMLEFT", 0, -6)
    sitWpManualRow:SetPoint("TOPRIGHT", ct3,           "TOPRIGHT",   0, 0)
    sitWpManualRow:Hide()

    local sitWpXLbl = sitWpManualRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sitWpXLbl:SetPoint("LEFT", sitWpManualRow, "LEFT", 0, 0)
    sitWpXLbl:SetText("X:"); sitWpXLbl:SetTextColor(0.78, 0.78, 0.78); sitWpXLbl:SetWidth(14)
    local sitWpXEb = CreateFrame("EditBox", nil, sitWpManualRow, "BackdropTemplate")
    BNB.EnsureBackdrop(sitWpXEb); BNB.SetBackdropDark(sitWpXEb)
    sitWpXEb:SetPoint("LEFT", sitWpXLbl, "RIGHT", 2, 0); sitWpXEb:SetSize(52, 20)
    sitWpXEb:SetFontObject("GameFontNormalSmall"); sitWpXEb:SetAutoFocus(false)
    sitWpXEb:SetMaxLetters(8); sitWpXEb:SetNumeric(false); sitWpXEb:SetTextInsets(3,3,0,0)
    local sitWpYLbl = sitWpManualRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sitWpYLbl:SetPoint("LEFT", sitWpXEb, "RIGHT", 6, 0)
    sitWpYLbl:SetText("Y:"); sitWpYLbl:SetTextColor(0.78, 0.78, 0.78); sitWpYLbl:SetWidth(14)
    local sitWpYEb = CreateFrame("EditBox", nil, sitWpManualRow, "BackdropTemplate")
    BNB.EnsureBackdrop(sitWpYEb); BNB.SetBackdropDark(sitWpYEb)
    sitWpYEb:SetPoint("LEFT", sitWpYLbl, "RIGHT", 2, 0); sitWpYEb:SetSize(52, 20)
    sitWpYEb:SetFontObject("GameFontNormalSmall"); sitWpYEb:SetAutoFocus(false)
    sitWpYEb:SetMaxLetters(8); sitWpYEb:SetNumeric(false); sitWpYEb:SetTextInsets(3,3,0,0)
    local sitWpSaveManualBtn = BNB.CreateButton(nil, sitWpManualRow, "Set", 38, 20)
    sitWpSaveManualBtn:SetPoint("LEFT", sitWpYEb, "RIGHT", 4, 0)

    -- WP status label
    local sitWpStatusLbl = ct3:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sitWpStatusLbl:SetPoint("BOTTOMLEFT",  sitCurBindHeader, "TOPLEFT",  0, 6)
    sitWpStatusLbl:SetPoint("BOTTOMRIGHT", sitCurBindHeader, "TOPRIGHT", 0, 6)
    sitWpStatusLbl:SetJustifyH("CENTER"); sitWpStatusLbl:SetTextColor(0.55, 0.85, 1, 1)
    sitWpStatusLbl:SetText(""); sitWpStatusLbl:Hide()

    SitRefreshWaypointDisplay = function()
        local n3  = BNB.GetNote(noteID)
        local wp  = n3 and n3.waypoint
        if wp and wp.x and wp.y then
            local title = wp.title or wp.label or ""
            local coordStr = string.format("%.1f, %.1f", wp.x, wp.y)
            sitWpStatusLbl:SetText("Waypoint:\n" .. (title ~= "" and title .. "\n" or "") .. coordStr)
            sitWpStatusLbl:Show()
        else
            sitWpStatusLbl:SetText(""); sitWpStatusLbl:Hide()
        end
    end

    -- WP leave checkbox
    local sitWpLeaveChk = CreateFrame("CheckButton", nil, ct3, "UICheckButtonTemplate")
    sitWpLeaveChk:SetSize(24, 24)
    sitWpLeaveChk:SetPoint("TOPLEFT", sitWpClearBtn, "BOTTOMLEFT", -4, -8); sitWpLeaveChk:Hide()
    local sitWpLeaveChkLbl = sitWpLeaveChk:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sitWpLeaveChkLbl:SetPoint("LEFT", sitWpLeaveChk, "RIGHT", 2, 0)
    sitWpLeaveChkLbl:SetText("Remove waypoint on zone leave")
    sitWpLeaveChkLbl:SetTextColor(0.78, 0.78, 0.78)
    sitWpLeaveChk:SetScript("OnClick", function(self)
        if self:GetChecked() then
            BNB.UpdateNote(noteID, {wpClearOnLeave = true})
        else
            BNB.UpdateNote(noteID, {_clear = {"wpClearOnLeave"}})
        end
        if BNB.SyncNoteConfig then BNB.SyncNoteConfig(noteID) end
    end)
    sitWpLeaveChk:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("When you leave the zone, automatically remove the waypoint.", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    sitWpLeaveChk:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- ShowDispControls extended with waypoint section (mirrors NoteConfig pattern)
    local _sitOrigShowDisp = SitShowDispControls
    SitShowDispControls = function(show)
        _sitOrigShowDisp(show)
        if show then
            sitWpDiv:Show(); sitWpHdr:Show(); sitWpDesc:Show()
            sitWpStatusTag:Show(); sitWpInfoLbl:Show(); sitWpInfoHit:Show()
            SitRefreshWPStatusTag()
            sitWpPinBtn:Show(); sitWpNavBtn:Show()
            sitWpClearBtn:Show(); sitWpManualBtn:Show()
            sitWpLeaveChk:Show()
            local n3 = BNB.GetNote(noteID)
            sitWpLeaveChk:SetChecked(n3 and n3.wpClearOnLeave == true)
            local avail = SitWPAvailable()
            sitWpPinBtn:SetEnabled(avail); sitWpNavBtn:SetEnabled(avail)
            sitWpClearBtn:SetEnabled(avail); sitWpManualBtn:SetEnabled(avail)
            sitWpLeaveChk:SetEnabled(avail)
            if avail then
                sitWpDesc:SetText("Pin your current map position to this note.\nUse Navigate to send it to TomTom or the map.")
                sitWpDesc:SetTextColor(0.60, 0.60, 0.60)
            else
                sitWpDesc:SetText("Install a waypoint addon to enable this feature.")
                sitWpDesc:SetTextColor(0.65, 0.40, 0.35)
            end
        else
            sitWpDiv:Hide(); sitWpHdr:Hide(); sitWpDesc:Hide()
            sitWpStatusTag:Hide(); sitWpInfoLbl:Hide(); sitWpInfoHit:Hide()
            sitWpPinBtn:Hide(); sitWpNavBtn:Hide()
            sitWpClearBtn:Hide(); sitWpManualBtn:Hide()
            sitWpManualRow:Hide(); sitWpLeaveChk:Hide()
        end
    end

    -- Manual coord commit
    local function SitCommitManualCoords()
        local n3 = BNB.GetNote(noteID); if not n3 then return end
        local xs = sitWpXEb:GetText():match("^%s*(.-)%s*$") or ""
        local ys = sitWpYEb:GetText():match("^%s*(.-)%s*$") or ""
        local x, y = tonumber(xs), tonumber(ys)
        if not x or not y then BNB:Print("|cffff6666Invalid coordinates.|r"); return end
        x = math.max(0, math.min(100, x)); y = math.max(0, math.min(100, y))
        local zone  = GetRealZoneText() or GetZoneText() or ""
        local title = (n3.title and n3.title ~= "") and n3.title or zone
        local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        local existWP = n3.waypoint
        BNB.UpdateNote(noteID, { waypoint = {
            mapID = mapID or (existWP and existWP.mapID),
            x = x, y = y, label = zone, title = title,
        }})
        SitRefreshWaypointDisplay(); sitWpManualRow:Hide()
        BNB:Print(string.format("Waypoint set manually: %s (%.1f, %.1f)", title, x, y))
        if BNB.SyncNoteConfig then BNB.SyncNoteConfig(noteID) end
    end

    sitWpManualBtn:SetScript("OnClick", function()
        if sitWpManualRow:IsShown() then sitWpManualRow:Hide(); return end
        local n3 = BNB.GetNote(noteID); local wp = n3 and n3.waypoint
        if wp and wp.x then sitWpXEb:SetText(string.format("%.1f", wp.x)) end
        if wp and wp.y then sitWpYEb:SetText(string.format("%.1f", wp.y)) end
        sitWpManualRow:Show(); sitWpXEb:SetFocus()
    end)
    sitWpManualBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Enter coordinates manually", 1, 1, 1); GameTooltip:Show()
    end)
    sitWpManualBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    sitWpSaveManualBtn:SetScript("OnClick", SitCommitManualCoords)
    sitWpXEb:SetScript("OnEnterPressed", function() sitWpYEb:SetFocus() end)
    sitWpYEb:SetScript("OnEnterPressed", SitCommitManualCoords)
    sitWpXEb:SetScript("OnEscapePressed", function() sitWpManualRow:Hide() end)
    sitWpYEb:SetScript("OnEscapePressed", function() sitWpManualRow:Hide() end)

    sitWpPinBtn:SetScript("OnClick", function()
        local n3 = BNB.GetNote(noteID); if not n3 then return end
        local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        if not mapID then BNB:Print("|cffff6666Cannot get map position.|r"); return end
        local pos = C_Map and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
        if not pos then BNB:Print("|cffff6666Cannot get map position.|r"); return end
        local px, py = pos:GetXY()
        local x = math.floor(px * 1000 + 0.5) / 10
        local y = math.floor(py * 1000 + 0.5) / 10
        local zone  = GetRealZoneText() or GetZoneText() or ""
        local title = (n3.title and n3.title ~= "") and n3.title or zone
        BNB.UpdateNote(noteID, { waypoint = { mapID=mapID, x=x, y=y, label=zone, title=title } })
        SitRefreshWaypointDisplay()
        BNB:Print(string.format("Waypoint pinned: %s %.1f, %.1f", title, x, y))
        if BNB.SyncNoteConfig then BNB.SyncNoteConfig(noteID) end
    end)
    sitWpPinBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Pin current location", 1, 1, 1)
        GameTooltip:AddLine("Saves your current map coordinates to this note.", 0.78, 0.78, 0.78, true)
        GameTooltip:Show()
    end)
    sitWpPinBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    sitWpNavBtn:SetScript("OnClick", function()
        local n3 = BNB.GetNote(noteID); if not n3 then return end
        local wp = n3.waypoint
        if not (wp and wp.x and wp.y and wp.mapID) then
            BNB:Print("|cffff6666No waypoint set on this note.|r"); return
        end
        local wpTitle = wp.title or wp.label or "BigNoteBox"
        local handled = false
        if TomTom and TomTom.AddWaypoint then
            pcall(function() TomTom:AddWaypoint(wp.mapID, wp.x/100, wp.y/100, {title=wpTitle, from="BigNoteBox"}) end)
            handled = true
            BNB:Print(string.format("TomTom waypoint: %s (%.1f, %.1f)", wpTitle, wp.x, wp.y))
        end
        if not handled and C_Map and C_Map.SetUserWaypoint then
            local ok = pcall(function()
                local pt = UiMapPoint.CreateFromCoordinates(wp.mapID, wp.x/100, wp.y/100)
                C_Map.SetUserWaypoint(pt)
                if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
                    C_SuperTrack.SetSuperTrackedUserWaypoint(true)
                end
            end)
            if ok then
                handled = true
                BNB:Print(string.format("Map pin set: %s (%.1f, %.1f)", wpTitle, wp.x, wp.y))
            end
        end
        if not handled then
            local wayStr = string.format("/way %s %.1f %.1f %s",
                wp.label or GetRealZoneText() or "", wp.x, wp.y, wpTitle)
            BNB:Print("|cffff6666No waypoint addon detected.|r Copy: |cffffff00" .. wayStr .. "|r")
        end
    end)
    sitWpNavBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Navigate to waypoint", 1, 1, 1)
        GameTooltip:AddLine("Send the stored waypoint to your map or waypoint addon.", 0.78, 0.78, 0.78, true)
        GameTooltip:Show()
    end)
    sitWpNavBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    sitWpClearBtn:SetScript("OnClick", function()
        BNB.UpdateNote(noteID, { _clear = {"waypoint"} })
        SitRefreshWaypointDisplay()
        if BNB.SyncNoteConfig then BNB.SyncNoteConfig(noteID) end
    end)
    sitWpClearBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Remove waypoint from this note", 1, 1, 1); GameTooltip:Show()
    end)
    sitWpClearBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- ── Load current note binding (_loadCtx equivalent) ───────────────────────
    local function SitLoadCtx()
        local n3  = BNB.GetNote(noteID)
        local ctx = n3 and n3.context
        local cd  = n3 and n3.contextDisplay
        if cd == "sticky" or cd == "both" then sitSelDisplay = cd else sitSelDisplay = "popup" end
        SitSetDispText(SitGetDispLabel(sitSelDisplay))
        if sitDispDropdown and sitDispDropdown.GenerateMenu then sitDispDropdown:GenerateMenu() end
        local lv = n3 and n3.contextLeave
        sitSelLeave = (lv == "bt-minimize" or lv == "hide") and lv or "keep"
        SitSetLeaveText(SitGetLeaveLabel(sitSelLeave))
        if sitLeaveDropdown and sitLeaveDropdown.GenerateMenu then sitLeaveDropdown:GenerateMenu() end

        if ctx and ctx ~= "" then
            local kind, value
            if BNB.DecodeContext then kind, value = BNB.DecodeContext(ctx) end
            if kind then
                local dropLabel = SIT_TYPE_LABELS[1]
                for i, k in ipairs(SIT_TYPES) do if k == kind then dropLabel = SIT_TYPE_LABELS[i]; break end end
                sitSelType = kind
                SitSetTypeText(dropLabel)
                if sitTypeDropdown and sitTypeDropdown.GenerateMenu then sitTypeDropdown:GenerateMenu() end
                SitSelectType(kind)
                if sitValueEb then sitValueEb:SetText(value or "") end
                sitClearCtxBtn:Show()
            else
                sitSelType = "none"
                SitSetTypeText(SIT_TYPE_LABELS[1])
                if sitTypeDropdown and sitTypeDropdown.GenerateMenu then sitTypeDropdown:GenerateMenu() end
                SitSelectType("none"); sitClearCtxBtn:Hide()
            end
        else
            sitSelType = "none"
            SitSetTypeText(SIT_TYPE_LABELS[1])
            if sitTypeDropdown and sitTypeDropdown.GenerateMenu then sitTypeDropdown:GenerateMenu() end
            SitSelectType("none"); sitClearCtxBtn:Hide()
        end
        SitRefreshCurBind()
        SitRefreshWaypointDisplay()
        local n3b = BNB.GetNote(noteID)
        sitWpLeaveChk:SetChecked(n3b and n3b.wpClearOnLeave == true)
    end

    -- Expose so OpenStickySettings can refresh the Situation tab when the
    -- settings window is already open (cross-sync from NoteConfig saves).
    f._loadSituation = SitLoadCtx

    SitLoadCtx()
    FinalisePanel(ct3, sf3)
    local note = BNB.GetNote(noteID)
    local noteName = (note and note.title ~= "") and note.title or L["UNTITLED"]
    if f._titleLbl then
        f._titleLbl:SetText("Settings: " .. noteName)
    elseif f.SetTitle then
        f:SetTitle("Settings: " .. noteName)
    end
end

-- Open the detached settings window for a sticky note
local function OpenStickySettings(stickyFrame, noteID)
    if not stickyFrame or not noteID then return end

    -- Close alarm window if it's open (mutual exclusion for same note)
    if BNB.AlarmWindow and BNB.AlarmWindow.IsOpen and BNB.AlarmWindow.IsOpen() then
        BNB.AlarmWindow.Close()
    end

    local f = BuildStickySettingsWindow()
    _stickySettingsNoteID = noteID

    -- Populate content
    PopulateStickySettings(noteID)

    -- Select remembered tab (or default to General)
    if f._selectTab then f._selectTab(f._activeTab or 1) end

    -- ── Anchor settings window to the sticky ─────────────────────────────────
    -- Anchoring to stickyFrame means WoW moves settings for free when the sticky
    -- is dragged — exactly like Config anchors to BNB.mainFrame.
    -- Dragging the settings window calls StartMoving() which breaks the anchor;
    -- after that it floats freely (detached), and the sticky stays put.
    -- Rule: open to the right of the sticky if it fits, otherwise to the left.
    local scrW = UIParent:GetWidth()
    local sCX  = stickyFrame:GetCenter()
    local sW   = stickyFrame:GetWidth()
    local placeRight = ((sCX or 0) + (sW or 0) / 2 + 8 + SETTINGS_W) <= scrW

    f:ClearAllPoints()
    if placeRight then
        f:SetPoint("LEFT", stickyFrame, "RIGHT", 8, 0)
    else
        f:SetPoint("RIGHT", stickyFrame, "LEFT", -8, 0)
    end

    -- Sticky stays at normal alpha — we want to see our changes live
    stickyFrame:SetAlpha(1.0)

    -- Show settings with fade-in
    local LA = GetLibAnimate()
    f:SetAlpha(0.95)
    f:Show()
    if LA then
        LA:Animate(f, "fadeIn", {
            duration = 0.25,
            onFinished = function() f:SetAlpha(0.95) end,
        })
    end
end

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
    iconTex:SetTexture((note.icon and note.icon ~= "") and note.icon
                       or "Interface\\Icons\\INV_Misc_Note_06")
    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    tile._iconTex = iconTex   -- stored so ApplyConfig can refresh it on icon change

    -- Hover alpha
    tile:SetScript("OnEnter", function()
        local c = frame._cfg
        ApplyBgAlpha(frame, math.max(0.95, c and c.alpha or 0.95), c)
        GameTooltip:SetOwner(tile, "ANCHOR_RIGHT")
        GameTooltip:AddLine(note.title ~= "" and note.title or L["UNTITLED"], 1, 0.82, 0)
        GameTooltip:AddLine("Left click to restore sticky note",  0.6, 0.6, 0.6)
        GameTooltip:AddLine("Right click to close sticky note",   0.6, 0.6, 0.6)
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
                    root:CreateButton("|cffff9900Dismiss Alarm|r", function()
                        if BNB.Alarm and BNB.Alarm.Dismiss then
                            BNB.Alarm.Dismiss(noteID)
                        end
                    end)
                    root:CreateDivider()
                    root:CreateButton("Close Sticky", function()
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
    iconTex:SetTexture(note.icon)
    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Left-click: toggle minimize (both when normal and when minimized)
    -- Right-click: close the sticky note entirely (only when minimized —
    --   when the note is open the X button in the header is used instead)
    iconFrame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    iconFrame:SetScript("OnClick", function(self, btn)
        if btn == "RightButton" and f._minimized then
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
                GameTooltip:AddLine(collapsed[task.id] and "Expand sub-tasks" or "Collapse sub-tasks", 1, 1, 1)
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
                GameTooltip:AddLine("Click to edit task.", 0.8, 0.8, 0.8)
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
                GameTooltip:AddLine("Situation: " .. task.situation, 1, 1, 1)
                GameTooltip:AddLine("Click to edit task.", 0.8, 0.8, 0.8)
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
    pcall(function() local f,s,fl = titleLbl:GetFont(); if f then titleLbl:SetFont(f, 16, fl or "") end end)
    local tc = note.titleColor
    if tc then titleLbl:SetTextColor(tc.r, tc.g, tc.b, 1)
    else        titleLbl:SetTextColor(unpack(COL_GOLD)) end
    titleLbl:SetText(note.title ~= "" and note.title or L["UNTITLED"])
    f._titleLbl = titleLbl

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
    -- We do NOT use FadeTo/OnUpdate on buttons: SetScript("OnUpdate") on a
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
                dynTip = (n and n.alarm) and "Edit alarm" or "Set alarm for this note"
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

    local minBtn = HdrBtn(2, "bt-minimize", "Minimize to icon", function()
        SN.SetMinimized(noteID, not f._minimized)
    end)
    f._minBtn = minBtn

    HdrBtn(3, "bt-settings", "Note Settings", function()
        if f._minimized then SN.SetMinimized(noteID, false); return end
        if _stickySettingsFrame and _stickySettingsFrame:IsShown()
           and _stickySettingsNoteID == noteID then
            CloseStickySettings()
        else
            OpenStickySettings(f, noteID)
        end
    end)

    HdrBtn(4, "bt-edit", "Open in BigNoteBox to edit", function()
        if InCombatLockdown() then BNB:Print(L["STICKY_COMBAT"]); return end
        if not BNB.mainFrame then
            if BNB.CreateMainWindow then BNB.CreateMainWindow() end
        end
        if BNB.mainFrame then
            BNB.mainFrame:Show()
            if BNB.RefreshNoteList then BNB.RefreshNoteList() end
            if BNB.SelectNote      then BNB.SelectNote(noteID) end
        end
    end)

    -- slot 5 = alarm: opens alarm setter window anchored to this button
    -- Assets: Assets/UI/sn-alarm-normal.tga + sn-alarm-hover.tga
    local alarmHdrBtn = HdrBtn(5, "bt-alarm", "Set alarm for this note", function()
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
    local tasksHdrBtn = HdrBtn(6, "bt-tasks", "Create Task", function()
        local hasTasks = BNB.Task and BNB.Task.HasTasks(noteID)
        if not hasTasks then
            -- No tasks: open main window, select note, open RefBox, add task
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
                -- Defer long enough for RefBox to open and RenderTaskPanel to
                -- complete before we try to focus the new task's editbox.
                C_Timer.After(0.2, function()
                    if BNB.FocusTaskEditBox then BNB.FocusTaskEditBox(taskID) end
                end)
            end
        else
            -- Has tasks: toggle between task view and note view
            local newView = f._taskViewActive and "note" or "tasks"
            SN_SetTaskView(noteID, newView)
        end
    end)
    tasksHdrBtn:SetScript("OnEnter", function(self)
        local hasTasks = BNB.Task and BNB.Task.HasTasks(noteID)
        local tip
        if not hasTasks then
            tip = "Create Task"
        elseif f._taskViewActive then
            tip = "Show Note"
        else
            tip = "Show Tasks"
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
        local over = f:IsMouseOver() or (f._focusHovered and f._focusHovered > 0)
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
    -- doesn't auto-scroll to the cursor position (which ends up mid-note)
    bodyEb:SetScript("OnCursorChanged", nil)
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
        GameTooltip:AddLine("Global task reset", 1, 1, 1)
        if rt == "daily" then
            GameTooltip:AddLine("All tasks in this note reset daily.", 0.78, 0.78, 0.78, true)
        elseif rt == "weekly" then
            GameTooltip:AddLine("All tasks in this note reset weekly.", 0.78, 0.78, 0.78, true)
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
        GameTooltip:AddLine("Global task situation", 1, 1, 1)
        if sit and sit ~= "" then
            GameTooltip:AddLine("Tasks are bound to: " .. sit, 0.78, 0.78, 0.78, true)
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
        if _stickySettingsFrame and _stickySettingsFrame:IsShown()
           and _stickySettingsNoteID == noteID then
            _stickySettingsFrame:Hide()
        end
        if f._frontFace    then f._frontFace:Hide() end

        -- Hide resize handle while minimized
        if f._resizeHandle then f._resizeHandle:Hide() end

        -- Position tile at the TOPRIGHT of the note (where the minimize button was)
        local tile = f._miniTile
        if tile then
            local right = f:GetRight()
            local top   = f:GetTop()
            local s     = f:GetEffectiveScale()
            local us    = UIParent:GetEffectiveScale()
            if right and top then
                tile:ClearAllPoints()
                tile:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT",
                    (right * s) / us, (top * s) / us)
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

        -- Place note so its top-right corner aligns with the tile's top-left
        -- (note "drops down" from the icon)
        local tile = f._miniTile
        if tile then
            local s   = UIParent:GetEffectiveScale()
            local ts  = tile:GetEffectiveScale()
            local tl  = tile:GetLeft()
            local tt  = tile:GetTop()
            if tl and tt then
                f:ClearAllPoints()
                f:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT",
                    (tl * ts) / s,
                    (tt * ts) / s)
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
    local f = openFrames[noteID]; return f and (f:IsShown() or f._minimized) or false
end

function SN.Open(noteID)
    if InCombatLockdown() then BNB:Print(L["STICKY_COMBAT"]); return end
    if not BNB.GetNote(noteID) then return end
    if openFrames[noteID] then
        local f = openFrames[noteID]
        if f._minimized then SN.SetMinimized(noteID, false)
        else f:Show(); f:Raise() end
        SaveGeometry(noteID, f); return
    end
    if CountOpen() >= (BigNoteBoxDB and BigNoteBoxDB.stickyMaxCount or MAX_NOTES) then
        BNB:Print(string.format(L["STICKY_MAX"], BigNoteBoxDB and BigNoteBoxDB.stickyMaxCount or MAX_NOTES)); return
    end
    local f = CreateStickyFrame(noteID)
    if not f then return end
    openFrames[noteID] = f
    -- Entrance fade — use LibAnimate if available, fall back to FadeTo.
    -- Frame alpha ends at 1.0; background opacity is set via backdrop in ApplyConfig.
    f:SetAlpha(0); f:Show()
    local LA = GetLibAnimate()
    if LA then
        LA:Animate(f, "fadeIn", {
            duration    = FLIP_TIME,
            onFinished  = function() f:SetAlpha(1.0) end,
        })
    else
        FadeTo(f, 0, 1.0, FLIP_TIME)
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
    -- Clear per-note task collapse state
    _stickyCollapsed[noteID] = nil
    -- Dismiss alarm if it is active (fired but not yet dismissed) when sticky closes.
    -- Uses IsAlarmActive rather than IsGlowing so it works regardless of glow timing.
    if BNB.Alarm and BNB.Alarm.IsAlarmActive and BNB.Alarm.IsAlarmActive(noteID) then
        BNB.Alarm.Dismiss(noteID)
    end
    -- Close detached settings window if open for this note
    if _stickySettingsFrame and _stickySettingsFrame:IsShown()
       and _stickySettingsNoteID == noteID then
        _stickySettingsFrame:Hide()
    end
    if f._miniTile then
        f._miniTile:Hide()
        if BNB.Alarm and BNB.Alarm.UnregisterGlowTarget then
            BNB.Alarm.UnregisterGlowTarget(noteID, f._miniTile)
        end
    end
    SaveGeometry(noteID, f)
    -- Exit fade — use LibAnimate if available, otherwise hide immediately
    local LA = GetLibAnimate()
    if LA then
        openFrames[noteID] = nil   -- remove from open set immediately so
                                   -- re-open during fade doesn't conflict
        local db2 = DB()
        if db2 and db2.postits and db2.postits[noteID] then
            db2.postits[noteID].shown = false
        end
        LA:Animate(f, "fadeOut", {
            duration   = FLIP_TIME,
            onFinished = function() f:Hide() end,
        })
    else
        f:Hide(); openFrames[noteID] = nil
        local db2 = DB()
        if db2 and db2.postits and db2.postits[noteID] then
            db2.postits[noteID].shown = false
        end
    end
end

function SN.CloseAll()
    for id in pairs(openFrames) do SN.Close(id) end
end

-- Hide all open sticky frames and tiles without closing them.
-- Positions and content are preserved; stickies reappear on ShowAll().
-- Sets BigNoteBoxDB.stickiesHidden = true (transient; cleared on login unless
-- stickiesHiddenPersist is enabled in Config > Features > Sticky Notes).
function SN.HideAll()
    local db = BigNoteBoxDB
    if db then db.stickiesHidden = true end
    for _, f in pairs(openFrames) do
        f:Hide()
        if f._miniTile then f._miniTile:Hide() end
    end
end

-- Restore all open sticky frames and tiles that were hidden by HideAll().
function SN.ShowAll()
    local db = BigNoteBoxDB
    if db then db.stickiesHidden = false end
    for _, f in pairs(openFrames) do
        if f._minimized then
            -- Minimized stickies show only as tile
            if f._miniTile then f._miniTile:Show() end
        else
            f:Show()
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
    if SN.IsOpen(noteID) then SN.Close(noteID) else SN.Open(noteID) end
end

-- Close the sticky settings panel (called by ESC handler in MainWindow)
function SN.CloseSettings()
    CloseStickySettings()
end

-- Re-render the task view for a sticky (called when spacing setting changes).
function SN.RefreshTaskView(noteID)
    local f = openFrames[noteID]
    if f and f._taskViewActive then
        RenderStickyTasks(noteID)
    end
end

-- Refresh the Situation tab of the sticky settings window if it is currently
-- open for the given noteID. Called by NoteConfig whenever it saves a
-- situation-related field so both windows stay in sync.
function SN.RefreshSettingsSituation(noteID)
    if not _stickySettingsFrame or not _stickySettingsFrame:IsShown() then return end
    if _stickySettingsNoteID ~= noteID then return end
    if _stickySettingsFrame._loadSituation then
        _stickySettingsFrame._loadSituation()
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
    local titleLeft = BuildIconBadge(f, noteID, note)
    if f._titleLbl then
        f._titleLbl:ClearAllPoints()
        f._titleLbl:SetPoint("LEFT",  f._headerBar, "LEFT",  titleLeft, 0)
        f._titleLbl:SetPoint("RIGHT", f._headerBar, "RIGHT", -PAD,      0)
    end
    if f._bodyEb then
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
                SN.Open(noteID)
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

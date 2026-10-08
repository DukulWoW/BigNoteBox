-- BigNoteBox UI/WysiwygBar.lua - Editor WYSIWYG formatting toolbar
-- Split out of NoteEditor.lua (ALL-65.10); built by BNB.BuildNoteEditor.
-- Loads after NoteEditor.lua: the undo timer tables are shared through BNB._EditorKit.

local BNB = BigNoteBox
local L   = BNB.L

local WYSIWYG_H   = 28   -- height of the WYSIWYG formatting toolbar

local K = BNB._EditorKit
local _undoTimers, _undoForced = K.undoTimers, K.undoForced

--------------------------------------------------------------------------------
-- WYSIWYG FORMATTING TOOLBAR
-- Sits between the timestamp strip and the body scroll frame.
-- Toggle via BigNoteBoxDB.wysiwygBarVisible (persisted).
--
-- Left  (left-anchored):  Undo | Redo | divider | FontType | Dec | Inc | FontSize | Bullet | Timestamp
-- Right (right-anchored): Restore | History | divider | CopyMove | Waypoint
--
-- BNB._editorWysiwygBar   — the bar frame (shown/hidden on toggle)
-- BNB._refreshUndoButtons — public function, refreshes undo/redo btn states
-- BNB._refreshWysiwygFont — public function, refreshes font controls on note switch
--------------------------------------------------------------------------------
local ASSETS_WY = "Interface\\AddOns\\BigNoteBox\\Assets\\Toolbar\\"

-- Font size preset list shown in the size dropdown quick-pick.
-- +/- buttons step 1pt at a time regardless of this list.
local WY_SIZE_PRESETS = { 8, 9, 10, 11, 12, 13, 14, 16, 18, 20, 24, 28, 32 }

-- The main editor's context. Focus mode passes its own (ALL-163): body() =
-- its edit box, timers() = its undo timer tables, markDirty(), applyFont(note)
-- = re-apply font and size to its body, writingOnly = the left side only,
-- ownMenus = BNB.ContextMenu for the pickers (Blizzard menus sit under
-- UIParent, which Focus mode hides).
local MAIN_CTX = {
    body      = function() return BNB._editorBody end,
    timers    = function() return _undoTimers, _undoForced end,
    markDirty = function() BNB.MarkDirty() end,
}

-- Every bar's refreshers: the main editor's and Focus mode's show the same
-- note, so the public refresh calls reach both
local _undoRefreshers, _fontRefreshers = {}, {}
BNB._refreshUndoButtons = function() for _, fn in ipairs(_undoRefreshers) do fn() end end
BNB._refreshWysiwygFont = function() for _, fn in ipairs(_fontRefreshers) do fn() end end

local function BuildWysiwygBar(parent, tsStrip, ctx)
    local db = BigNoteBoxDB
    local main = ctx == nil
    ctx = ctx or MAIN_CTX
    local function Body() return ctx.body() end

    -- A picker menu (font, size, timestamp): Blizzard's dropdown in the main
    -- editor, BNB.ContextMenu in Focus mode (ctx.ownMenus), whose radios close
    -- on click, so there is nothing to regenerate
    local function OpenPicker(dd, owner, fill)
        if ctx.ownMenus then
            BNB.ContextMenu.Open(owner, fill)
        else
            dd:SetupMenu(function(_, root) fill(root) end)
            dd:OpenMenu()
        end
    end
    local function Regen(dd) if not ctx.ownMenus then dd:GenerateMenu() end end

    local bar = CreateFrame("Frame", main and "BigNoteBoxWysiwygBar" or nil, parent)
    bar:SetPoint("TOPLEFT",  tsStrip, "BOTTOMLEFT",  0, -2)
    bar:SetPoint("TOPRIGHT", tsStrip, "BOTTOMRIGHT",  0, -2)
    bar:SetHeight(WYSIWYG_H)

    -- Top and bottom edge lines (BNB.CreateNoteRule: the note list's divider)
    local sepT = BNB.CreateNoteRule(bar)
    sepT:SetPoint("TOPLEFT",  bar, "TOPLEFT",  0, 0)
    sepT:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)

    local sepB = BNB.CreateNoteRule(bar)
    sepB:SetPoint("BOTTOMLEFT",  bar, "BOTTOMLEFT",  0, 0)
    sepB:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)

    -- ── Shared helpers ────────────────────────────────────────────────────────

    -- Divider — consistent size/color used everywhere in this bar
    local function MakeDiv(anchorFrame, anchorPoint)
        local d = bar:CreateTexture(nil, "ARTWORK")
        d:SetSize(1, 16)
        d:SetPoint("LEFT", anchorFrame, anchorPoint or "RIGHT", 6, 0)
        if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset then
            local p = BNB.GetSkinPreset()
            local br, bg_, bb = BNB.SkinRuleOf(p)
            d:SetColorTexture(br, bg_, bb, 0.25)
            BNB.RegisterSkinRule(d, 0.25)
        else
            d:SetColorTexture(0.16, 0.16, 0.18, 1)
        end
        return d
    end

    -- Icon button (20x20): the bare icon in both modes (white art, Dukul
    -- 2026-10-08). Normal mode tints it the gold of the old art; skin mode
    -- the preset's accent colour, as the top bar icons (RegisterSkinAccentTex,
    -- follows preset changes), and a press nudges it 1 px down-right.
    -- Hover: ui-hover-64 over the icon, tinted the same (BNB.TintUIIcon).
    local function WyBtn(icon, tip)
        local skin = BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset
        local btn = CreateFrame("Button", nil, bar)
        btn:SetSize(20, 20)
        local tx = btn:CreateTexture(nil, "ARTWORK")
        tx:SetAllPoints()
        tx:SetTexture(ASSETS_WY .. icon)
        BNB.TintUIIcon(tx)
        BNB.AddUIIconHover(btn, tx)
        if skin then
            btn:SetScript("OnMouseDown", function(self)
                if not self:IsEnabled() then return end
                tx:ClearAllPoints()
                tx:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
                tx:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, -1)
            end)
            btn:SetScript("OnMouseUp", function()
                tx:ClearAllPoints(); tx:SetAllPoints()
            end)
        end
        btn._tx = tx
        btn.SetIconEnabled = function(self, en)
            self:SetEnabled(en)
            self:SetAlpha(en and 1.0 or 0.30)
            pcall(function() tx:SetDesaturated(not en) end)
        end
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(tip, 1, 1, 1)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        btn:SetIconEnabled(false)
        return btn
    end

    -- Skin mode look of the font / size picker boxes: the skin dropdown of
    -- BNB.SkinDropdown (skin text button box + square skin "down" icon button
    -- at its right end, white label), drawn under the click button with the
    -- mouse off and fed its hover / press. Call after the button's own
    -- SetScripts (hooks). Normal mode: nothing changes.
    local function SkinPickerBox(bg, btn, arrowTex, label)
        if not (BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset) then return end
        local w, h = bg:GetWidth(), bg:GetHeight()
        BNB.SetBackdrop(bg, 0, 0, 0, 0, 0, 0, 0, 0)
        arrowTex:Hide()
        local vis = BNB.CreateSkinButton(nil, bg, "", w, h)
        vis:SetAllPoints(bg)
        vis:EnableMouse(false)
        vis:SetFrameLevel(bg:GetFrameLevel() + 1)
        btn:SetFrameLevel(bg:GetFrameLevel() + 3)
        local arrow = BNB.CreateIconButton(vis, h, "down", { skin = true })
        arrow:SetPoint("RIGHT", vis, "RIGHT", 0, 0)
        arrow:EnableMouse(false)
        label:SetParent(btn)
        label:SetPoint("RIGHT", bg, "RIGHT", -h, 0)
        BNB.SetTextWhite(label)
        local function Pass(f, script)
            local fn = f:GetScript(script)
            if fn then pcall(fn, f) end
        end
        btn:HookScript("OnEnter", function() vis:LockHighlight(); Pass(arrow, "OnEnter") end)
        btn:HookScript("OnLeave", function()
            vis:UnlockHighlight(); Pass(vis, "OnMouseUp"); Pass(arrow, "OnLeave")
        end)
        btn:HookScript("OnMouseDown", function() Pass(vis, "OnMouseDown"); Pass(arrow, "OnMouseDown") end)
        btn:HookScript("OnMouseUp", function() Pass(vis, "OnMouseUp"); Pass(arrow, "OnMouseUp") end)
    end

    -- ── LEFT SIDE ─────────────────────────────────────────────────────────────

    -- Undo / Redo
    local undoBtn = WyBtn("tb-undo", L["NE_TB_UNDO"])
    undoBtn:SetPoint("LEFT", bar, "LEFT", 6, 0)

    local redoBtn = WyBtn("tb-redo", L["NE_TB_REDO"])
    redoBtn:SetPoint("LEFT", undoBtn, "RIGHT", 4, 0)

    -- Wire undo
    undoBtn:SetScript("OnClick", function()
        local id = BNB._currentNoteID
        if not id or BNB._editorLocked then return end
        local eb = Body(); if not eb then return end
        local ut, uf = ctx.timers()
        if ut[id] then ut[id]:Cancel(); ut[id] = nil end
        if uf[id] then uf[id]:Cancel(); uf[id] = nil end
        BNB._undoActive = true
        local text, cursor = BNB.UndoStep(id)
        if text then
            eb:SetText(text)
            C_Timer.After(0, function() eb:SetCursorPosition(cursor or 0) end)
            ctx.markDirty()
        end
        BNB._undoActive = false
        if BNB._refreshUndoButtons then BNB._refreshUndoButtons() end
    end)

    -- Wire redo
    redoBtn:SetScript("OnClick", function()
        local id = BNB._currentNoteID
        if not id or BNB._editorLocked then return end
        local eb = Body(); if not eb then return end
        local ut, uf = ctx.timers()
        if ut[id] then ut[id]:Cancel(); ut[id] = nil end
        if uf[id] then uf[id]:Cancel(); uf[id] = nil end
        BNB._undoActive = true
        local text, cursor = BNB.RedoStep(id)
        if text then
            eb:SetText(text)
            C_Timer.After(0, function() eb:SetCursorPosition(cursor or 0) end)
            ctx.markDirty()
        end
        BNB._undoActive = false
        if BNB._refreshUndoButtons then BNB._refreshUndoButtons() end
    end)

    _undoRefreshers[#_undoRefreshers + 1] = function()
        local id     = BNB._currentNoteID
        local locked = BNB._editorLocked
        undoBtn:SetIconEnabled(not locked and BNB.UndoCanUndo(id))
        redoBtn:SetIconEnabled(not locked and BNB.UndoCanRedo(id))
    end

    -- Divider: undo/redo | font controls
    local divFont = MakeDiv(redoBtn)

    -- ── Font type dropdown ────────────────────────────────────────────────────
    -- Truncated label button that opens a WowStyle1 menu listing all fonts.
    -- Width chosen to fit truncated font names (~90px) without crowding.
    local FONT_DD_W = 90
    local FONT_BTN_H = 20

    local fontDDBg = BNB.CreateBackdropFrame("Frame", nil, bar)
    fontDDBg:SetSize(FONT_DD_W, FONT_BTN_H)
    fontDDBg:SetPoint("LEFT", divFont, "RIGHT", 6, 0)
    local function ApplyFontDDBgSkin()
        local p  = BNB.GetSkinPreset and BNB.GetSkinPreset()
        if not p then return end
        local r, g, b = BNB.SkinButtonOf(p)
        local br, bg_, bb = BNB.SkinBorderOf(p)
        BNB.SetBackdrop(fontDDBg, r, g, b, 0.92, br, bg_, bb, 1)
    end
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset then
        ApplyFontDDBgSkin()
        BNB.RegisterSkinBackdrop(ApplyFontDDBgSkin)
    else
        BNB.SetBackdrop(fontDDBg, 0.08, 0.08, 0.10, 0.90, 0.28, 0.28, 0.30, 1)
    end

    local fontDDLabel = fontDDBg:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    fontDDLabel:SetPoint("LEFT",  fontDDBg, "LEFT",  5, 0)
    fontDDLabel:SetPoint("RIGHT", fontDDBg, "RIGHT", -14, 0)
    fontDDLabel:SetJustifyH("LEFT")
    fontDDLabel:SetMaxLines(1)
    fontDDLabel:SetTextColor(0.85, 0.85, 0.85)

    local fontDDArrow = fontDDBg:CreateTexture(nil, "ARTWORK")
    fontDDArrow:SetSize(10, 10)
    fontDDArrow:SetPoint("RIGHT", fontDDBg, "RIGHT", -3, 0)
    fontDDArrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")

    local fontDDBtn = CreateFrame("Button", nil, fontDDBg)
    fontDDBtn:SetAllPoints()

    -- Helper: get current note's effective font label
    local function GetCurrentFontLabel()
        local note = BNB._currentNoteID and BNB.GetNote(BNB._currentNoteID)
        local fid  = note and BNB.ResolveFontID and BNB.ResolveFontID(note.fontOverride)
        if fid and BNB.GetFontDef then
            local def = BNB.GetFontDef(fid)
            if def then return def.label end
        end
        -- Fall back to the global font actually drawn under the active set (ALL-14)
        local globalID = BNB.GetEffectiveFontID and BNB.GetEffectiveFontID() or "notoserif"
        if BNB.GetFontDef then
            local def = BNB.GetFontDef(globalID)
            if def then return def.label end
        end
        return L["NE_FONT_DEFAULT"]
    end

    local function RefreshFontDDLabel()
        local lbl = GetCurrentFontLabel()
        -- Truncate to fit; approximate 7px per character at small font
        if #lbl > 12 then lbl = lbl:sub(1, 11) .. "..." end
        fontDDLabel:SetText(lbl)
    end

    local function ApplyFontOverride(fontID)
        local id = BNB._currentNoteID; if not id then return end
        if fontID == nil then
            BNB.UpdateNote(id, {_clear = {"fontOverride"}})
        else
            BNB.UpdateNote(id, {fontOverride = fontID})
        end
        if BNB.SyncNoteConfig then BNB.SyncNoteConfig(id) end
        if ctx.applyFont then ctx.applyFont(BNB.GetNote(id)) end
        -- Apply to editor body live
        local eb = BNB._editorBody; if not eb then return end
        local note = BNB.GetNote(id); if not note then return end
        local sz = (note.fontSize) or (BigNoteBoxDB and BigNoteBoxDB.fontSize) or BNB.DEFAULTS.fontSize
        local def = fontID and BNB.ResolveFontDef and BNB.ResolveFontDef(fontID)
        if def then
            pcall(function() eb:SetFont(def.regular, BNB.FontPx(def.regular, sz), "") end)
        elseif BNB.ApplyFont then
            BNB.ApplyFont()
        end
        RefreshFontDDLabel()
    end

    -- Open font picker menu

    local _fontMenuDD  -- reusable invisible DropdownButton
    fontDDBtn:SetScript("OnClick", function()
        if not _fontMenuDD then
            _fontMenuDD = CreateFrame("DropdownButton", main and "BNBWysiFontDD" or nil, UIParent,
                "WowStyle1DropdownTemplate")
            _fontMenuDD:SetSize(1, 1); _fontMenuDD:SetAlpha(0)
            _fontMenuDD:SetToplevel(true)
            BNB.SkinDropdownMenu(_fontMenuDD)
        end
        _fontMenuDD:ClearAllPoints()
        _fontMenuDD:SetPoint("TOPLEFT", fontDDBg, "BOTTOMLEFT", 0, 0)
        OpenPicker(_fontMenuDD, fontDDBg, function(root)
            -- "Default" entry clears per-note override
            -- An override that cannot be drawn under the active font set
            -- (ALL-14) shows as Default, which is what the note displays.
            local curID = (function()
                local n = BNB._currentNoteID and BNB.GetNote(BNB._currentNoteID)
                return n and BNB.ResolveFontID(n.fontOverride)
            end)()
            root:CreateRadio(L["NE_FONT_DEFAULT_GLOBAL"],
                function() return curID == nil end,
                function() ApplyFontOverride(nil); Regen(_fontMenuDD) end)
            -- Bundled fonts (non-LSM) of the active set, plus WoW Default on Latin
            for _, def in ipairs(BNB.FONTS or {}) do
                if not def._isLSM and BNB.ResolveFontID(def.id) == def.id then
                    local fid = def.id; local lbl = def.label
                    root:CreateRadio(lbl,
                        function() return curID == fid end,
                        function() ApplyFontOverride(fid); Regen(_fontMenuDD) end)
                end
            end
            -- LSM fonts: only shown when db.lsmFonts is on and entries exist
            local db = BigNoteBoxDB
            if db and db.lsmFonts then
                local hasLSM = false
                for _, def in ipairs(BNB.FONTS or {}) do
                    if def._isLSM then hasLSM = true; break end
                end
                if hasLSM then
                    root:CreateDivider()
                    for _, def in ipairs(BNB.FONTS or {}) do
                        if def._isLSM then
                            local fid = def.id; local lbl = def.label
                            root:CreateRadio(lbl,
                                function() return curID == fid end,
                                function() ApplyFontOverride(fid); Regen(_fontMenuDD) end)
                        end
                    end
                end
            end
        end)
    end)
    fontDDBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(fontDDBg, "ANCHOR_TOP")
        GameTooltip:AddLine(L["NE_FONT_TYPE_TIP_TITLE"], 1, 1, 1)
        GameTooltip:AddLine(L["NE_FONT_TYPE_TIP_BODY"], 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    fontDDBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    SkinPickerBox(fontDDBg, fontDDBtn, fontDDArrow, fontDDLabel)

    -- ── Font size: decrease / increase / dropdown ─────────────────────────────
    local decBtn = WyBtn("tb-decreasesize", L["CFG_EXPORT_DECREASE_FONT"])
    decBtn:SetPoint("LEFT", fontDDBg, "RIGHT", 4, 0)
    decBtn:SetIconEnabled(true)

    local incBtn = WyBtn("tb-increasesize", L["CFG_EXPORT_INCREASE_FONT"])
    incBtn:SetPoint("LEFT", decBtn, "RIGHT", 2, 0)
    incBtn:SetIconEnabled(true)

    -- Size display button — shows current pt value, opens preset quick-pick menu
    -- Skin mode: room for the square arrow button beside "12pt"
    local SIZE_BTN_W = (BigNoteBoxDB and BigNoteBoxDB.skinMode) and 52 or 38
    local sizeBg = BNB.CreateBackdropFrame("Frame", nil, bar)
    sizeBg:SetSize(SIZE_BTN_W, FONT_BTN_H)
    sizeBg:SetPoint("LEFT", incBtn, "RIGHT", 4, 0)
    local function ApplySizeBgSkin()
        local p  = BNB.GetSkinPreset and BNB.GetSkinPreset()
        if not p then return end
        local r, g, b = BNB.SkinButtonOf(p)
        local br, bg_, bb = BNB.SkinBorderOf(p)
        BNB.SetBackdrop(sizeBg, r, g, b, 0.92, br, bg_, bb, 1)
    end
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset then
        ApplySizeBgSkin()
        BNB.RegisterSkinBackdrop(ApplySizeBgSkin)
    else
        BNB.SetBackdrop(sizeBg, 0.08, 0.08, 0.10, 0.90, 0.28, 0.28, 0.30, 1)
    end

    local sizeLbl = sizeBg:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    sizeLbl:SetPoint("LEFT",  sizeBg, "LEFT",  4, 0)
    sizeLbl:SetPoint("RIGHT", sizeBg, "RIGHT", -3, 0)
    sizeLbl:SetJustifyH("CENTER")
    sizeLbl:SetTextColor(0.85, 0.85, 0.85)

    local sizeArrow = sizeBg:CreateTexture(nil, "ARTWORK")
    sizeArrow:SetSize(8, 8)
    sizeArrow:SetPoint("RIGHT", sizeBg, "RIGHT", -2, 0)
    sizeArrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")

    local sizeDDBtn = CreateFrame("Button", nil, sizeBg)
    sizeDDBtn:SetAllPoints()

    local function GetCurrentFontSize()
        local note = BNB._currentNoteID and BNB.GetNote(BNB._currentNoteID)
        return (note and note.fontSize) or (BigNoteBoxDB and BigNoteBoxDB.fontSize) or BNB.DEFAULTS.fontSize
    end

    local function RefreshSizeLbl()
        sizeLbl:SetText(GetCurrentFontSize() .. "pt")
    end

    local function ApplyFontSize(sz)
        sz = math.max(8, math.min(32, math.floor(sz)))
        local id = BNB._currentNoteID; if not id then return end
        BNB.UpdateNote(id, {fontSize = sz})
        if BNB.SyncNoteConfig  then BNB.SyncNoteConfig(id) end
        if ctx.applyFont then ctx.applyFont(BNB.GetNote(id)) end
        local eb = BNB._editorBody
        if eb then
            local path = select(1, eb:GetFont())
            if path then pcall(function() eb:SetFont(path, BNB.FontPx(path, sz), "") end) end
        end
        RefreshSizeLbl()
    end

    decBtn:SetScript("OnClick", function()
        ApplyFontSize(GetCurrentFontSize() - 1)
    end)
    incBtn:SetScript("OnClick", function()
        ApplyFontSize(GetCurrentFontSize() + 1)
    end)

    local _sizeMenuDD
    sizeDDBtn:SetScript("OnClick", function()
        if not _sizeMenuDD then
            _sizeMenuDD = CreateFrame("DropdownButton", main and "BNBWysiSizeDD" or nil, UIParent,
                "WowStyle1DropdownTemplate")
            _sizeMenuDD:SetSize(1, 1); _sizeMenuDD:SetAlpha(0)
            _sizeMenuDD:SetToplevel(true)
            BNB.SkinDropdownMenu(_sizeMenuDD)
        end
        _sizeMenuDD:ClearAllPoints()
        _sizeMenuDD:SetPoint("TOPLEFT", sizeBg, "BOTTOMLEFT", 0, 0)
        OpenPicker(_sizeMenuDD, sizeBg, function(root)
            local curSz = GetCurrentFontSize()
            for _, sz in ipairs(WY_SIZE_PRESETS) do
                local s = sz
                root:CreateRadio(string.format(L["NE_FONT_SIZE_PT_FMT"], s),
                    function() return curSz == s end,
                    function() ApplyFontSize(s); Regen(_sizeMenuDD) end)
            end
        end)
    end)
    sizeDDBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(sizeBg, "ANCHOR_TOP")
        GameTooltip:AddLine(L["NE_FONT_SIZE_TIP_TITLE"], 1, 1, 1)
        GameTooltip:AddLine(L["NE_FONT_SIZE_TIP_BODY"], 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    sizeDDBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    SkinPickerBox(sizeBg, sizeDDBtn, sizeArrow, sizeLbl)

    -- tb-bulletlist: insert "  · " at the start of the cursor's current line
    local bulletBtn = WyBtn("tb-bulletlist", L["NE_INSERT_BULLET_TIP"])
    bulletBtn:SetPoint("LEFT", sizeBg, "RIGHT", 6, 0)
    bulletBtn:SetIconEnabled(true)
    bulletBtn:SetScript("OnClick", function()
        local eb = Body()
        if not eb or BNB._editorLocked then return end
        local id = BNB._currentNoteID; if not id then return end
        local text   = eb:GetText() or ""
        local cursor = eb:GetCursorPosition() or 0
        -- Find the byte index of the start of the current line
        local lineStart = 0
        for i = cursor, 1, -1 do
            if text:sub(i, i) == "\n" then
                lineStart = i  -- insert after this \n
                break
            end
        end
        local BULLET = "  - "  -- two spaces + hyphen + space
        local newText   = text:sub(1, lineStart) .. BULLET .. text:sub(lineStart + 1)
        local newCursor = cursor + #BULLET
        -- Seed snap with pre-bullet state if not yet initialised (note never typed in).
        if not BNB._undoSnap[id] then
            BNB._undoSnap[id]  = { text = text, cursor = cursor }
            BNB._undoStack[id] = {}
            BNB._redoStack[id] = {}
        end
        -- Suppress OnTextChanged undo push during SetText, then push manually.
        BNB._undoActive = true
        eb:SetText(newText)
        BNB._undoActive = false
        -- UndoPush: snap=old→pushed onto stack, snap updated to newText. Undo recovers old.
        BNB.UndoPush(id, newText, newCursor)
        if BNB._refreshUndoButtons then BNB._refreshUndoButtons() end
        -- The button click took keyboard focus from the body; give it back.
        C_Timer.After(0, function() eb:SetFocus(); eb:SetCursorPosition(newCursor) end)
        ctx.markDirty()
    end)

    -- tb-timestamp: menu to insert the date, the time, or both at the cursor,
    -- in the Appearance timestamp format (ALL-66). One undo step, like the bullet.
    local function InsertAtCursor(snippet)
        local eb = Body()
        if not eb or BNB._editorLocked or not eb:IsVisible() then return end
        local id = BNB._currentNoteID; if not id then return end
        local text   = eb:GetText() or ""
        local cursor = eb:GetCursorPosition() or 0
        local newText   = text:sub(1, cursor) .. snippet .. text:sub(cursor + 1)
        local newCursor = cursor + #snippet
        if not BNB._undoSnap[id] then
            BNB._undoSnap[id]  = { text = text, cursor = cursor }
            BNB._undoStack[id] = {}
            BNB._redoStack[id] = {}
        end
        BNB._undoActive = true
        eb:SetText(newText)
        BNB._undoActive = false
        BNB.UndoPush(id, newText, newCursor)
        if BNB._refreshUndoButtons then BNB._refreshUndoButtons() end
        C_Timer.After(0, function() eb:SetFocus(); eb:SetCursorPosition(newCursor) end)
        ctx.markDirty()
    end

    local stampBtn = WyBtn("tb-timestamp", L["NE_INSERT_TIMESTAMP_TIP"])
    stampBtn:SetPoint("LEFT", bulletBtn, "RIGHT", 4, 0)
    stampBtn:SetIconEnabled(true)
    local _stampMenuDD
    stampBtn:SetScript("OnClick", function(self)
        if not (Body() and BNB._currentNoteID) or BNB._editorLocked then return end
        if not _stampMenuDD then
            _stampMenuDD = CreateFrame("DropdownButton", main and "BNBWysiStampDD" or nil, UIParent,
                "WowStyle1DropdownTemplate")
            _stampMenuDD:SetSize(1, 1); _stampMenuDD:SetAlpha(0)
            _stampMenuDD:SetToplevel(true)
            BNB.SkinDropdownMenu(_stampMenuDD)
        end
        _stampMenuDD:ClearAllPoints()
        _stampMenuDD:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, 0)
        OpenPicker(_stampMenuDD, self, function(root)
            local now = time()
            local d, t = BNB.FmtDate(now), BNB.FmtClock(now)
            local items = {
                { L["INSERT_DATE"],     d },
                { L["INSERT_TIME"],     t },
                { L["INSERT_DATETIME"], d .. " " .. t },
            }
            for _, it in ipairs(items) do
                local value = it[2]
                root:CreateButton(it[1] .. "  |cff888888" .. value .. "|r",
                    function() InsertAtCursor(value) end)
            end
        end)
    end)
    stampBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["NE_INSERT_TIMESTAMP_TIP"], 1, 1, 1)
        GameTooltip:AddLine(L["NE_INSERT_TIMESTAMP_BODY"], 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)

    -- ── RIGHT SIDE (right-anchored) ───────────────────────────────────────────
    -- Anchored from RIGHT inward so they always hug the right edge.
    -- Main editor only: Focus mode has the writing tools alone (ALL-163)
    local cmDiv
    if main then

    -- tb-notemap: waypoint at note creation coords (rightmost)
    local mapBtn = WyBtn("tb-notemap", L["NE_WP_OPEN_TIP_TITLE"])
    mapBtn:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
    mapBtn:SetScript("OnEnter", function(self)
        local note = BNB._currentNoteID and BNB.GetNote(BNB._currentNoteID)
        if not note or not note.coordX then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["NE_WP_OPEN_TIP_TITLE"], 1, 1, 1)
        local zone = note.coordZone or L["CFG_EXPORT_UNKNOWN_AUTHOR"]
        GameTooltip:AddLine(string.format(L["NE_WP_ZONE_COORDS_FMT"], zone, note.coordX, note.coordY), 0.7, 0.7, 0.7)
        if not (TomTom and TomTom.AddWaypoint) then
            GameTooltip:AddLine(L["NE_WP_REPLACES_TIP"], 0.5, 0.5, 0.5)
        end
        GameTooltip:Show()
    end)
    mapBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    mapBtn:SetScript("OnClick", function()
        local note = BNB._currentNoteID and BNB.GetNote(BNB._currentNoteID)
        if not note or not note.coordX or not note.coordMapID then return end
        local mapID = note.coordMapID
        local x, y = note.coordX / 100, note.coordY / 100
        local noteTitle = (note.title and note.title ~= "") and note.title or nil
        local label = note.coordZone
            and string.format("%s (%.2f %.2f)", note.coordZone, note.coordX, note.coordY)
            or  string.format("%.2f %.2f", note.coordX, note.coordY)
        if noteTitle then label = noteTitle .. " - " .. label end
        if TomTom and TomTom.AddWaypoint and TomTom.RemoveWaypoint then
            if BNB._coordWaypoint then
                pcall(function() TomTom:RemoveWaypoint(BNB._coordWaypoint) end)
                BNB._coordWaypoint = nil
            end
            local ok, uid = pcall(function()
                return TomTom:AddWaypoint(mapID, x, y, {
                    title = label, persistent = false, minimap = true, world = true,
                })
            end)
            if ok and uid then BNB._coordWaypoint = uid end
        elseif C_Map and C_Map.SetUserWaypoint then
            local pt = UiMapPoint.CreateFromCoordinates(mapID, x, y)
            pcall(function() C_Map.SetUserWaypoint(pt) end)
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
                pcall(function() C_SuperTrack.SetSuperTrackedUserWaypoint(true) end)
            end
        end
        if OpenWorldMap then pcall(function() OpenWorldMap(mapID) end) end
    end)
    BNB._wysiwygMapBtn = mapBtn

    -- Divider: share | waypoint
    local shareDiv = bar:CreateTexture(nil, "ARTWORK")
    shareDiv:SetSize(1, 16)
    shareDiv:SetPoint("RIGHT", mapBtn, "LEFT", -6, 0)
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset then
        local p = BNB.GetSkinPreset()
        local br, bg_, bb = BNB.SkinRuleOf(p)
        shareDiv:SetColorTexture(br, bg_, bb, 0.40)
        BNB.RegisterSkinRule(shareDiv, 0.40)
    else
        shareDiv:SetColorTexture(0.16, 0.16, 0.18, 1)
    end

    -- tb-share (left of divider)
    local shareBtn = WyBtn("tb-share", L["NE_SHARE_NOTE_TIP"])
    shareBtn:SetPoint("RIGHT", shareDiv, "LEFT", -6, 0)
    shareBtn:SetScript("OnClick", function()
        local id = BNB._currentNoteID
        if id and BNB.OpenShareWindow then BNB.OpenShareWindow(id) end
    end)
    shareBtn:SetIconEnabled(false)
    BNB._wysiwygShareBtn = shareBtn
    -- tb-copymove (left of share button)
    local copyMoveBtn = WyBtn("tb-copymove", L["NE_COPY_MOVE_TIP"])
    copyMoveBtn:SetPoint("RIGHT", shareBtn, "LEFT", -4, 0)
    copyMoveBtn:SetScript("OnClick", function()
        local id = BNB._currentNoteID
        if id and BNB.OpenCopyMovePopup then BNB.OpenCopyMovePopup(id) end
    end)
    BNB._wysiwygCopyMoveBtn = copyMoveBtn

    -- tb-alarm (left of copy/move)
    local alarmBtn = WyBtn("tb-alarm", L["STICKY_SET_ALARM_TIP"])
    alarmBtn:SetPoint("RIGHT", copyMoveBtn, "LEFT", -4, 0)
    alarmBtn:SetScript("OnClick", function()
        local id = BNB._currentNoteID
        if not id then return end
        if BNB.AlarmWindow then
            if BNB.AlarmWindow.IsOpen and BNB.AlarmWindow.IsOpen()
               and BNB.AlarmWindow.GetNoteID and BNB.AlarmWindow.GetNoteID() == id then
                BNB.AlarmWindow.Close()
            else
                if BNB.AlarmWindow.OpenLeftOfMain then
                    BNB.AlarmWindow.OpenLeftOfMain(id)
                end
            end
        end
    end)
    BNB._wysiwygAlarmBtn = alarmBtn

    -- Divider: history | alarm
    cmDiv = bar:CreateTexture(nil, "ARTWORK")
    cmDiv:SetSize(1, 16)
    cmDiv:SetPoint("RIGHT", alarmBtn, "LEFT", -6, 0)
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset then
        local p = BNB.GetSkinPreset()
        local br, bg_, bb = BNB.SkinRuleOf(p)
        cmDiv:SetColorTexture(br, bg_, bb, 0.40)
        BNB.RegisterSkinRule(cmDiv, 0.40)
    else
        cmDiv:SetColorTexture(0.16, 0.16, 0.18, 1)
    end

    -- tb-history (left of divider)
    local histBtn = WyBtn("tb-history", L["HISTORY_VIEW_BTN_TIP"])
    histBtn:SetPoint("RIGHT", cmDiv, "LEFT", -6, 0)
    histBtn:SetScript("OnClick", function()
        local id = BNB._currentNoteID
        if id and BNB.ToggleNoteHistoryPanel then BNB.ToggleNoteHistoryPanel(id) end
    end)
    histBtn:SetIconEnabled(false)
    BNB._wysiwygHistoryBtn = histBtn

    -- tb-restore (left of history)
    local restoreBtn = WyBtn("tb-restore", L["HISTORY_RESTORE_BTN_TIP"])
    restoreBtn:SetPoint("RIGHT", histBtn, "LEFT", -4, 0)
    restoreBtn:SetScript("OnClick", function()
        local id = BNB._currentNoteID; if not id then return end
        if BNB._dirty and BNB.SaveCurrentNote then BNB.SaveCurrentNote() end
        local slots = BNB.HistoryGetSlots(id)
        if slots.manual then
            -- The id is the popup's data (arg 4), as OnAccept / OnCancel read it
            StaticPopup_Show("BNB_HISTORY_OVERRIDE_MANUAL", nil, nil, id)
        else
            BNB.HistoryCreateManual(id)
            BNB:Print(L["HISTORY_MANUAL_SAVED"])
        end
    end)
    BNB._wysiwygRestoreBtn = restoreBtn

    -- Modules off (ALL-343): Alarms off = no alarm button, the divider moves
    -- up to Copy/Move; Note History off = no history / restore buttons and no
    -- divider (nothing left of it)
    function BNB.ApplyWysiwygModuleBtns()
        local alarmsOn, histOn = BNB.AlarmsEnabled(), BNB.HistoryEnabled()
        alarmBtn:SetShown(alarmsOn)
        histBtn:SetShown(histOn); restoreBtn:SetShown(histOn)
        cmDiv:SetShown(histOn)
        cmDiv:ClearAllPoints()
        cmDiv:SetPoint("RIGHT", alarmsOn and alarmBtn or copyMoveBtn, "LEFT", -6, 0)
    end
    BNB.ApplyWysiwygModuleBtns()

    end   -- main (right side)

    -- ── Public refresh callbacks ──────────────────────────────────────────────

    -- BNB._refreshWysiwygFont: called by LoadNoteInEditor and NoteConfig when the note changes
    _fontRefreshers[#_fontRefreshers + 1] = function()
        RefreshFontDDLabel()
        RefreshSizeLbl()
        -- Enable/disable dec/inc at bounds
        local sz = GetCurrentFontSize()
        decBtn:SetIconEnabled(sz > 8)
        incBtn:SetIconEnabled(sz < 32)
        -- Highlight alarm button when current note has an active alarm
        if main and BNB._wysiwygAlarmBtn then
            local id    = BNB._currentNoteID
            local note  = id and BNB.GetNote and BNB.GetNote(id)
            local alarm = note and note.alarm
            local hasAlarm = alarm ~= nil and not alarm.fired
            BNB._wysiwygAlarmBtn:SetIconEnabled(hasAlarm)
        end
    end

    if main then
    -- Copy/move button visibility. Always shown since ALL-265: Note Settings
    -- lost Note visibility, so this and the right-click menu are the ways to
    -- change a note's character, sidebar on or off. Kept as a function: the
    -- sidebar switch and Sidebar.lua still call it.
    function BNB.SyncSidebarWysiwygBtns()
        local enabled = true
        if BNB._wysiwygCopyMoveBtn then BNB._wysiwygCopyMoveBtn:SetShown(enabled) end
        -- The divider follows the Note History module (ALL-343)
        if BNB.ApplyWysiwygModuleBtns then BNB.ApplyWysiwygModuleBtns() end
    end
    BNB.SyncSidebarWysiwygBtns()

    -- StaticPopup for manual restore override warning.
    -- WoW StaticPopup 3-button layout:
    --   button1 = "Override"  -> OnAccept
    --   button2 = "Compare"   -> OnCancel  (middle button)
    --   button3 = "Cancel"    -> OnAlt
    -- OnCancel fires for both the X/ESC dismiss AND button2, so we guard with
    -- a flag to distinguish button2 clicks from ESC/X dismissal.
    if not StaticPopupDialogs["BNB_HISTORY_OVERRIDE_MANUAL"] then
        StaticPopupDialogs["BNB_HISTORY_OVERRIDE_MANUAL"] = {
            text           = L["HISTORY_OVERRIDE_TEXT"],
            button1        = L["HISTORY_OVERRIDE_OVERRIDE"],
            button2        = L["HISTORY_OVERRIDE_COMPARE"],
            button3        = L["HISTORY_OVERRIDE_CANCEL"],
            OnAccept       = function(self, noteID)
                if noteID and BNB.HistoryCreateManual then
                    BNB.HistoryCreateManual(noteID)
                    BNB:Print(L["HISTORY_MANUAL_UPDATED"])
                end
            end,
            OnCancel       = function(self, noteID, reason)
                -- button2 = "Compare" fires OnCancel with reason == "clicked"
                -- ESC / X dismiss fires OnCancel with reason == "override" or nil
                -- We only open compare when the button was explicitly clicked.
                if reason == "clicked" then
                    if noteID then
                        local slots = BNB.HistoryGetSlots(noteID)
                        if slots.manual and BNB.OpenHistoryCompare then
                            BNB.OpenHistoryCompare(noteID, slots.manual)
                        end
                    end
                end
                -- reason nil/other = ESC dismiss, do nothing
            end,
            OnAlt          = function(self, noteID)
                -- button3 = "Cancel" — just dismiss, no action needed
            end,
            timeout        = 0,
            whileDead      = true,
            hideOnEscape   = true,
            preferredIndex = 3,
        }
    end

    end   -- main (sidebar sync, restore popup)

    -- Respect initial visibility setting (Focus mode places its own bar)
    if main and db and db.wysiwygBarVisible == false then
        bar:Hide()
    end

    return bar
end

BNB._BuildWysiwygBar = BuildWysiwygBar

-- BigNoteBox UI/HistoryCompareWindow.lua
--
-- Full-width compare window. Shows current note (left) vs snapshot (right).
-- Each side has a "Make Live" button and an "Export" button (JSON/MD radio).
--
-- When open: ALL other BNB windows are covered by a black semi-transparent
-- overlay and made non-interactive.
-- ESC / X / Cancel / "Make Live" are the only ways to dismiss.
--
-- Public API:
--   BNB.OpenHistoryCompare(noteID, snap)
--   BNB.CloseHistoryCompare()

local BNB = BigNoteBox
local L   = BNB.L

local CMP_W   = 820
local CMP_H   = 640
local TITLE_H = 32
local PAD     = 12
local BTN_H   = 26
local STRIP_H = 48
local HDR_H   = 22
local COL_GAP = 8

local _cmpFrame    = nil
local _noteID      = nil
local _snap        = nil
local _exportFrame = nil
local _overlays    = {}

local function FmtTs(ts)
    if not ts or ts == 0 then return "Unknown" end
    local db    = BigNoteBoxDB
    local use24 = db and db.use24Hour ~= false
    local d = date("%Y-%m-%d", ts)
    local t
    if use24 then
        t = date("%H:%M", ts)
    else
        local h = tonumber(date("%H", ts))
        local ampm = h >= 12 and "pm" or "am"
        h = h % 12; if h == 0 then h = 12 end
        t = h .. ":" .. date("%M", ts) .. " " .. ampm
    end
    return d .. "  " .. t
end

local function MakeOverlay(target)
    if not target then return nil end
    local ov = CreateFrame("Frame", nil, target)
    ov:SetAllPoints()
    ov:SetFrameStrata("FULLSCREEN_DIALOG")
    ov:SetFrameLevel((target:GetFrameLevel() or 0) + 200)
    ov:EnableMouse(true)
    local bg = ov:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.65)
    ov:Hide()
    return ov
end

local function GetOrMakeOverlay(target, key)
    if not _overlays[key] then
        _overlays[key] = MakeOverlay(target)
    end
    return _overlays[key]
end

local function SetWindowsLocked(locked)
    -- Apply black overlay to history windows only.
    -- Main window gets no overlay (per design) — just the click blocker via ESC chain.
    local targets = {
        history = _G["BigNoteBoxHistoryFrame"],
        nhp     = _G["BigNoteBoxNoteHistoryFrame"],
    }
    for key, frame in pairs(targets) do
        if frame then
            local ov = GetOrMakeOverlay(frame, key)
            if ov then
                if locked then ov:Show() else ov:Hide() end
            end
        end
    end
    -- Block interaction on the main window without overlay (alpha stays 1.0)
    local mf = BNB.mainFrame
    if mf then
        if not _overlays["main_blocker"] then
            local bl = CreateFrame("Frame", nil, mf)
            bl:SetAllPoints()
            bl:SetFrameStrata("FULLSCREEN_DIALOG")
            bl:SetFrameLevel((mf:GetFrameLevel() or 0) + 200)
            bl:EnableMouse(true)
            bl:Hide()
            _overlays["main_blocker"] = bl
        end
        if locked then
            _overlays["main_blocker"]:Show()
        else
            _overlays["main_blocker"]:Hide()
        end
    end
end

local SK_EXP_TITLE_H_CMP = 28  -- export popup skin title height

local function OpenExportPopup(noteData, anchorFrame)
    if not _exportFrame then
        local skinMode = BigNoteBoxDB and BigNoteBoxDB.skinMode
        local ef
        if skinMode then
            ef = BNB.CreateSkinFrame(UIParent, false, "BigNoteBoxHistoryExportFrame", false)
            _G["BigNoteBoxHistoryExportFrame"] = ef
            ef:SetSize(280, 156)
            ef:SetFrameStrata("TOOLTIP")
            ef:SetFrameLevel(10)
            ef:SetToplevel(true)
            ef:SetMovable(true); ef:SetClampedToScreen(true)
            ef:EnableMouse(true)
            ef:RegisterForDrag("LeftButton")
            ef:SetScript("OnDragStart", function(s) s:StartMoving() end)
            ef:SetScript("OnDragStop",  function(s) s:StopMovingOrSizing() end)

            local titleBar = BNB.CreateSkinStrip(ef, true, false)
            titleBar:SetPoint("TOPLEFT",  ef, "TOPLEFT",  0, 0)
            titleBar:SetPoint("TOPRIGHT", ef, "TOPRIGHT", 0, 0)
            titleBar:SetHeight(SK_EXP_TITLE_H_CMP)
            titleBar:EnableMouse(true)
            titleBar:RegisterForDrag("LeftButton")
            titleBar:SetScript("OnDragStart", function() ef:StartMoving() end)
            titleBar:SetScript("OnDragStop",  function() ef:StopMovingOrSizing() end)

            local titleLbl = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            titleLbl:SetPoint("CENTER", titleBar, "CENTER", -12, 0)
            titleLbl:SetTextColor(1, 0.82, 0)
            titleLbl:SetText(L["HISTORY_EXPORT_TITLE"])

            local closeBtn = BNB.CreateSkinCloseButton(titleBar, function() ef:Hide() end)
            closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -3, 0)

            ef:SetScript("OnShow", function()
                if BNB.ApplyMainWindowSkin then BNB.ApplyMainWindowSkin() end
            end)
        else

    _exportFrame._noteData = noteData
    _exportFrame._jsonRb:SetChecked(true)
    _exportFrame._mdRb:SetChecked(false)
    _exportFrame:ClearAllPoints()
    if anchorFrame then
        _exportFrame:SetPoint("TOP", anchorFrame, "BOTTOM", 0, -6)
    else
        _exportFrame:SetPoint("CENTER")
    end
    _exportFrame:Show()
    _exportFrame:Raise()
end

        local fmtLbl = ef:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fmtLbl:SetPoint("TOPLEFT", ef, "TOPLEFT", EPAD, ey)
        fmtLbl:SetTextColor(0.6, 0.6, 0.6)
        fmtLbl:SetText(L["HISTORY_EXPORT_FORMAT"])
        ey = ey - 20

        local jsonRb = CreateFrame("CheckButton", nil, ef, "UICheckButtonTemplate")
        jsonRb:SetSize(22, 22)
        jsonRb:SetPoint("TOPLEFT", ef, "TOPLEFT", EPAD - 2, ey + 2)
        jsonRb:SetChecked(true)
        local jsonLbl = ef:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        jsonLbl:SetPoint("LEFT", jsonRb, "RIGHT", 2, 0)
        jsonLbl:SetText(L["HISTORY_EXPORT_JSON"])
        ey = ey - 28

        local mdRb = CreateFrame("CheckButton", nil, ef, "UICheckButtonTemplate")
        mdRb:SetSize(22, 22)
        mdRb:SetPoint("TOPLEFT", ef, "TOPLEFT", EPAD - 2, ey + 2)
        mdRb:SetChecked(false)
        local mdLbl = ef:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        mdLbl:SetPoint("LEFT", mdRb, "RIGHT", 2, 0)
        mdLbl:SetText(L["HISTORY_EXPORT_MARKDOWN"])
        ey = ey - 30

        jsonRb:SetScript("OnClick", function(self)
            self:SetChecked(true); mdRb:SetChecked(false)
        end)
        mdRb:SetScript("OnClick", function(self)
            self:SetChecked(true); jsonRb:SetChecked(false)
        end)

        local copyBtn = BNB.CreateButton(nil, ef, L["HISTORY_EXPORT_COPY"], 160, BTN_H)
        copyBtn:SetPoint("TOPLEFT", ef, "TOPLEFT", EPAD, ey)
        copyBtn:SetScript("OnClick", function()
            local nd  = ef._noteData or {}
            local fmt = ef._mdRb:GetChecked() and "markdown" or "json"
            local text
            if fmt == "json" then
                local function esc(s)
                    return (s or ""):gsub('\\','\\\\'):gsub('"','\\"')
                                    :gsub('\n','\\n'):gsub('\r','\\r')
                                    :gsub('\t','\\t')
                end
                local tagParts = {}
                for _, t in ipairs(nd.tags or {}) do
                    tagParts[#tagParts+1] = '"'..esc(t)..'"'
                end
                text = '{\n'
                    .. '  "title": "'    .. esc(nd.title or "") .. '",\n'
                    .. '  "body": "'     .. esc(nd.body  or "") .. '",\n'
                    .. '  "tags": ['     .. table.concat(tagParts, ", ") .. '],\n'
                    .. '  "timestamp": ' .. (nd.timestamp or nd.updated or 0) .. '\n'
                    .. '}'
            else
                local md = {}
                md[#md+1] = "# " .. (nd.title or "(untitled)")
                if nd.tags and #nd.tags > 0 then
                    md[#md+1] = "*Tags: " .. table.concat(nd.tags, ", ") .. "*"
                end
                md[#md+1] = ""
                md[#md+1] = nd.body or ""
                text = table.concat(md, "\n")
            end
            BNB.ShowClipboardHint(text, copyBtn)
        end)

        ef._jsonRb = jsonRb
        ef._mdRb   = mdRb
        _exportFrame = ef
        ef:Hide()
    end

    _exportFrame._noteData = noteData
    _exportFrame._jsonRb:SetChecked(true)
    _exportFrame._mdRb:SetChecked(false)
    _exportFrame:ClearAllPoints()
    if anchorFrame then
        _exportFrame:SetPoint("TOP", anchorFrame, "BOTTOM", 0, -6)
    else
        _exportFrame:SetPoint("CENTER")
    end
    _exportFrame:Show()
    _exportFrame:Raise()
end

local SK_CMP_TITLE_H = 28

local function BuildPanel(f, isLeft)
    local titleH = f._titleH or TITLE_H
    local panW = math.floor((CMP_W - PAD * 2 - COL_GAP) / 2)
    local panH = CMP_H - titleH - HDR_H - PAD * 2 - STRIP_H

    local pane = CreateFrame("Frame", nil, f)
    pane:SetSize(panW, panH)
    local xOff = isLeft and PAD or (PAD + panW + COL_GAP)
    pane:SetPoint("TOPLEFT", f, "TOPLEFT", xOff, -(titleH + HDR_H + PAD))

    local bodySize = BigNoteBoxDB and BigNoteBoxDB.fontSize or 13
    local sf, eb  = BNB.CreateScrolledEditBox(nil, pane, bodySize)
    sf:SetPoint("TOPLEFT",     pane, "TOPLEFT",     0,   0)
    sf:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -22, BTN_H + 8)
    eb:SetEnabled(false)
    pane._sf = sf; pane._eb = eb

    local makeBtn = BNB.CreateButton(nil, pane, L["HISTORY_COMPARE_MAKE_LIVE"], 90, BTN_H)
    makeBtn:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 0, 0)
    makeBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["HISTORY_COMPARE_MAKE_TIP"], 1, 1, 1)
        GameTooltip:Show()
    end)
    makeBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pane._makeBtn = makeBtn

    local expBtn = BNB.CreateButton(nil, pane, L["HISTORY_COMPARE_EXPORT"], 72, BTN_H)
    expBtn:SetPoint("LEFT", makeBtn, "RIGHT", 6, 0)
    expBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["HISTORY_COMPARE_EXPORT_TIP"], 1, 1, 1)
        GameTooltip:Show()
    end)
    expBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pane._expBtn = expBtn

    return pane
end

local function BuildCompareWindow()
    if _cmpFrame then return _cmpFrame end

    local skinMode = BigNoteBoxDB and BigNoteBoxDB.skinMode
    local titleH   = skinMode and SK_CMP_TITLE_H or TITLE_H
    local f

    if skinMode then
        f = BNB.CreateSkinFrame(UIParent, false, "BigNoteBoxHistoryCompareFrame", false)
        _G["BigNoteBoxHistoryCompareFrame"] = f
        f:SetSize(CMP_W, CMP_H)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetFrameLevel(100)
        f:SetToplevel(true)
        f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self) self:StartMoving() end)
        f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)

        local titleBar = BNB.CreateSkinStrip(f, true, false)
        titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
        titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
        titleBar:SetHeight(SK_CMP_TITLE_H)
        titleBar:EnableMouse(true)
        titleBar:RegisterForDrag("LeftButton")
        titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
        titleBar:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

        local titleLbl = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        titleLbl:SetPoint("CENTER", titleBar, "CENTER", -12, 0)
        titleLbl:SetTextColor(1, 0.82, 0)
        titleLbl:SetText("")
        f._titleLbl = titleLbl

        local closeBtn = BNB.CreateSkinCloseButton(titleBar, function() BNB.CloseHistoryCompare() end)
        closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -3, 0)

        f:SetScript("OnShow", function()
            if BNB.ApplyMainWindowSkin then BNB.ApplyMainWindowSkin() end
        end)
    else
        f = CreateFrame("Frame", "BigNoteBoxHistoryCompareFrame", UIParent,
            "ButtonFrameTemplate")
        f:SetSize(CMP_W, CMP_H)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetFrameLevel(100)
        f:SetToplevel(true)
        f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self) self:StartMoving() end)
        f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
        ButtonFrameTemplate_HidePortrait(f)
        ButtonFrameTemplate_HideButtonBar(f)
        if f.Inset then f.Inset:Hide() end
        if f.CloseButton then
            f.CloseButton:SetScript("OnClick", function() BNB.CloseHistoryCompare() end)
        end
    end
    tinsert(UISpecialFrames, "BigNoteBoxHistoryCompareFrame")
    f._titleH = titleH

    local panW = math.floor((CMP_W - PAD * 2 - COL_GAP) / 2)

    local lHdr = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lHdr:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(titleH + 4))
    lHdr:SetWidth(panW); lHdr:SetJustifyH("LEFT"); lHdr:SetHeight(HDR_H)
    lHdr:SetText(L["HISTORY_COMPARE_CURRENT"])

    local rHdr = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rHdr:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + panW + COL_GAP, -(titleH + 4))
    rHdr:SetWidth(panW); rHdr:SetJustifyH("LEFT"); rHdr:SetHeight(HDR_H)
    rHdr:SetTextColor(0.85, 0.65, 0.20)
    f._rHdr = rHdr

    local cdiv = f:CreateTexture(nil, "ARTWORK")
    cdiv:SetWidth(1)
    cdiv:SetPoint("TOP",    f, "TOP",    0, -(titleH + HDR_H + PAD))
    cdiv:SetPoint("BOTTOM", f, "BOTTOM", 0,  STRIP_H)
    cdiv:SetColorTexture(0.28, 0.28, 0.30, 1)

    local lhdiv = f:CreateTexture(nil, "ARTWORK")
    lhdiv:SetHeight(1)
    lhdiv:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD,        -(titleH + HDR_H + 2))
    lhdiv:SetPoint("TOPRIGHT", f, "TOPLEFT",  PAD + panW, -(titleH + HDR_H + 2))
    lhdiv:SetColorTexture(0.28, 0.28, 0.30, 1)

    local rhdiv = f:CreateTexture(nil, "ARTWORK")
    rhdiv:SetHeight(1)
    rhdiv:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD + panW + COL_GAP, -(titleH + HDR_H + 2))
    rhdiv:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD,                 -(titleH + HDR_H + 2))
    rhdiv:SetColorTexture(0.28, 0.28, 0.30, 1)

    if skinMode then
        local ruleHost = CreateFrame("Frame", nil, f)
        ruleHost:SetHeight(1)
        ruleHost:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  PAD,  STRIP_H - 1)
        ruleHost:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, STRIP_H - 1)
        local rule = BNB.CreateDivider(ruleHost, "HORIZONTAL", 0.25, 0.25, 0.28, 1)
        rule:SetPoint("TOPLEFT",  ruleHost, "TOPLEFT",  0, 0)
        rule:SetPoint("TOPRIGHT", ruleHost, "TOPRIGHT", 0, 0)
    else
        local rule = f:CreateTexture(nil, "ARTWORK")
        rule:SetHeight(1); rule:SetColorTexture(0.25, 0.25, 0.28, 1)
        rule:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  PAD,  STRIP_H - 1)
        rule:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, STRIP_H - 1)
    end

    local cancelBtn = BNB.CreateButton(nil, f, L["HISTORY_COMPARE_CANCEL"], 90, BTN_H)
    cancelBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, (STRIP_H - BTN_H) / 2)
    cancelBtn:SetScript("OnClick", function() BNB.CloseHistoryCompare() end)

    f._leftPane  = BuildPanel(f, true)
    f._rightPane = BuildPanel(f, false)

    f:Hide()
    _cmpFrame = f
    return f
end

function BNB.OpenHistoryCompare(noteID, snap)
    if InCombatLockdown() then return end
    _noteID = noteID; _snap = snap

    local ndb  = BigNoteBoxNotesDB
    local note = ndb and ndb.notes and ndb.notes[noteID]
    if not note then return end

    local f = BuildCompareWindow()

    local title = string.format(L["HISTORY_COMPARE_TITLE"], note.title or "(untitled)")
    if f.SetTitle then
        f:SetTitle(title)
    elseif f._titleLbl then
        f._titleLbl:SetText(title)
    end
    if f._rHdr then
        f._rHdr:SetText(L["HISTORY_COMPARE_SNAPSHOT"] ..
            "  |cff888888(" .. FmtTs(snap.timestamp) .. ")|r")
    end

    local lp = f._leftPane
    lp._eb:SetText(note.body or "")
    C_Timer.After(0, function() if lp._sf then lp._sf:SetVerticalScroll(0) end end)
    lp._makeBtn:SetScript("OnClick", function()
        BNB.CloseHistoryCompare()
        BNB:Print(L["HISTORY_KEPT_CURRENT"])
    end)
    lp._expBtn:SetScript("OnClick", function()
        OpenExportPopup(note, lp._expBtn)
    end)

    local rp = f._rightPane
    rp._eb:SetText(snap.body or "")
    C_Timer.After(0, function() if rp._sf then rp._sf:SetVerticalScroll(0) end end)
    rp._makeBtn:SetScript("OnClick", function()
        BNB.HistoryRestoreNote(noteID, snap, true)
        BNB.CloseHistoryCompare()
        BNB:Print(L["HISTORY_RESTORED"])
    end)
    rp._expBtn:SetScript("OnClick", function()
        OpenExportPopup(snap, rp._expBtn)
    end)

    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:Show(); f:Raise()
    SetWindowsLocked(true)
end

function BNB.CloseHistoryCompare()
    if _exportFrame and _exportFrame:IsShown() then _exportFrame:Hide() end
    if _cmpFrame then _cmpFrame:Hide() end
    _noteID = nil; _snap = nil
    SetWindowsLocked(false)
end

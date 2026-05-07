-- BigNoteBox UI/SendToChat.lua — Send note lines to a chat channel
--
-- ButtonFrameTemplate dialog styled to match the main window.
-- Features:
--   • WowStyle1DropdownTemplate channel picker
--   • Channel entries colored to match WoW chat colors
--   • Whisper target field (shown only for Whisper)
--   • Line-by-line toggle (empty lines always skipped)
--   • Scrolled preview showing exactly what will be sent, with line numbers
--     and word-wrap. Lines over 255 chars shown as split sub-lines.
--   • "Send Directly" — sends via SendChatMessage / BCB.SendDirect
--   • "Send to BCB"   — opens BCB multiline box with the text pre-filled
--   • Esc closes the dialog
--   • Lines over 255 chars split at word boundaries, never silently truncated
--   • Spam-warning confirm when > 3 lines would be sent
--
-- Public API:
--   BNB.OpenSendToChat(noteID)
--   BNB.CloseSendToChat()

local BNB = BigNoteBox
local L   = BNB.L

-- ── Constants ──────────────────────────────────────────────────────────────────
local DLG_W             = 340
local DLG_H             = 500
local PAD               = 12
local TITLE_H           = 60
local WOW_MSG_LIMIT     = 255
local CONFIRM_THRESHOLD = 3

-- ── Channel definitions ────────────────────────────────────────────────────────
local CHANNELS = {
    { type = "SAY",     label = "Say",     r = 1.00, g = 1.00, b = 1.00 },
    { type = "YELL",    label = "Yell",    r = 1.00, g = 0.25, b = 0.25 },
    { type = "PARTY",   label = "Party",   r = 0.67, g = 0.67, b = 1.00 },
    { type = "RAID",    label = "Raid",    r = 1.00, g = 0.50, b = 0.00 },
    { type = "GUILD",   label = "Guild",   r = 0.25, g = 1.00, b = 0.25 },
    { type = "OFFICER", label = "Officer", r = 0.25, g = 0.75, b = 0.75 },
    { type = "WHISPER", label = "Whisper", r = 0.85, g = 0.50, b = 1.00, needsTarget = true },
}

local function ChanColor(ch)
    return string.format("|cff%02x%02x%02x",
        math.floor(ch.r * 255), math.floor(ch.g * 255), math.floor(ch.b * 255))
end

-- ── State ──────────────────────────────────────────────────────────────────────
local dlgFrame     = nil
local confirmFrame = nil
local _noteID      = nil
local _selChannel  = 1
local _lineByLine  = true

-- ── Core helpers ───────────────────────────────────────────────────────────────
local SafeSend = C_ChatInfo.SendChatMessage

-- Returns only non-empty trimmed lines. Empty lines always skipped.
local function GetLines(body, lineByLine)
    if not body or body == "" then return {} end
    if not lineByLine then
        local t = body:match("^%s*(.-)%s*$")
        return t ~= "" and { t } or {}
    end
    local lines = {}
    for line in (body .. "\n"):gmatch("([^\n]*)\n") do
        local t = line:match("^%s*(.-)%s*$")
        if t ~= "" then lines[#lines + 1] = t end
    end
    return lines
end

local function TotalChars(lines)
    local n = 0; for _, l in ipairs(lines) do n = n + #l end; return n
end

-- Split one string into ≤255-byte chunks at word boundaries.
local function SplitLine(str)
    if #str <= WOW_MSG_LIMIT then return { str } end
    local chunks, pos = {}, 1
    while pos <= #str do
        local remaining = str:sub(pos)
        if #remaining <= WOW_MSG_LIMIT then chunks[#chunks + 1] = remaining; break end
        local chunk = str:sub(pos, pos + WOW_MSG_LIMIT - 1)
        local cutAt = chunk:match("^.*()%s")
        if cutAt and cutAt > 1 then
            chunks[#chunks + 1] = str:sub(pos, pos + cutAt - 2)
            pos = pos + cutAt
        else
            chunks[#chunks + 1] = chunk
            pos = pos + WOW_MSG_LIMIT
        end
    end
    return chunks
end

local function DoSend(lines, chanType, target)
    local bcb   = BNB.hasBCB and BigChatBox and BigChatBox.SendDirect
    local count = 0
    for _, line in ipairs(lines) do
        if line ~= "" then
            for _, chunk in ipairs(SplitLine(line)) do
                if bcb then
                    pcall(bcb, chunk, chanType, target, nil)
                else
                    if chanType == "WHISPER" then
                        pcall(SafeSend, chunk, chanType, nil, target)
                    else
                        pcall(SafeSend, chunk, chanType)
                    end
                end
                count = count + 1
            end
        end
    end
    local ch = CHANNELS[_selChannel]
    BNB:Print(string.format(L["SEND_COMPLETE"], count, ch and ch.label or chanType))
end

local function SendToBCB(body)
    if not (BigChatBox and BCB_OpenMultiline) then
        BNB:Print("|cffff6666BigChatBox is not available.|r")
        return
    end
    BCB_OpenMultiline()
    -- Set text after a tick so the frame has fully initialized
    C_Timer.After(0, function()
        if BigChatBox.mlEditBox then
            BigChatBox.mlEditBox:SetText(body)
            BigChatBox.mlEditBox:SetFocus()
            BigChatBox.mlEditBox:SetCursorPosition(#body)
        end
    end)
    BNB.CloseSendToChat()
end

-- ── Custom confirm dialog ──────────────────────────────────────────────────────
local SK_STC_TITLE_H = 28

local function CreateConfirmDialog()
    local skinMode = BigNoteBoxDB and BigNoteBoxDB.skinMode
    local f
    local contentY  -- top of content below title chrome

    if skinMode then
        f = BNB.CreateSkinFrame(UIParent, false, "BigNoteBoxSendConfirm", false)
        _G["BigNoteBoxSendConfirm"] = f
        f:SetSize(300, 180)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetToplevel(true); f:SetClampedToScreen(true)
        f:SetMovable(true); f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self) self:StartMoving() end)
        f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)

        local titleBar = BNB.CreateSkinStrip(f, true, false)
        titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
        titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
        titleBar:SetHeight(SK_STC_TITLE_H)
        titleBar:EnableMouse(true)
        titleBar:RegisterForDrag("LeftButton")
        titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
        titleBar:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

        local titleLbl = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        titleLbl:SetPoint("CENTER", titleBar, "CENTER", -12, 0)
        titleLbl:SetTextColor(1, 0.82, 0)
        titleLbl:SetText("Confirm Send")

        local closeBtn = BNB.CreateSkinCloseButton(titleBar, function() f:Hide() end)
        closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -3, 0)

        f:SetScript("OnShow", function()
            if BNB.ApplyMainWindowSkin then BNB.ApplyMainWindowSkin() end
        end)
        contentY = -(SK_STC_TITLE_H + 8)
    else
        f = CreateFrame("Frame", "BigNoteBoxSendConfirm", UIParent, "ButtonFrameTemplate")
        f:SetSize(300, 180)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetToplevel(true); f:SetClampedToScreen(true)
        f:SetMovable(true); f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self) self:StartMoving() end)
        f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
        ButtonFrameTemplate_HidePortrait(f); ButtonFrameTemplate_HideButtonBar(f)
        if f.Inset then f.Inset:Hide() end
        f:SetAlpha(0.97); f:SetTitle("Confirm Send")
        if f.CloseButton then
            f.CloseButton:SetScript("OnClick", function() f:Hide() end)
        end
        contentY = -TITLE_H
    end
    tinsert(UISpecialFrames, "BigNoteBoxSendConfirm")

    local statsLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statsLbl:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, contentY)
    statsLbl:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, contentY)
    statsLbl:SetJustifyH("LEFT"); statsLbl:SetTextColor(0.90, 0.90, 0.90)
    f._statsLbl = statsLbl

    local chanLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    chanLbl:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, contentY - 22)
    chanLbl:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, contentY - 22)
    chanLbl:SetJustifyH("LEFT")
    f._chanLbl = chanLbl

    if skinMode then
        local divHost = CreateFrame("Frame", nil, f)
        divHost:SetHeight(1)
        divHost:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, contentY - 44)
        divHost:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, contentY - 44)
        local div = BNB.CreateDivider(divHost, "HORIZONTAL", 0.35, 0.35, 0.38, 0.8)
        div:SetPoint("TOPLEFT",  divHost, "TOPLEFT",  0, 0)
        div:SetPoint("TOPRIGHT", divHost, "TOPRIGHT", 0, 0)
    else
        local div = f:CreateTexture(nil, "ARTWORK")
        div:SetHeight(1); div:SetColorTexture(0.35, 0.35, 0.38, 0.8)
        div:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, contentY - 44)
        div:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, contentY - 44)
    end

    local warnLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    warnLbl:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, contentY - 52)
    warnLbl:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, contentY - 52)
    warnLbl:SetJustifyH("LEFT"); warnLbl:SetWordWrap(true)
    warnLbl:SetTextColor(1, 0.65, 0.10)
    warnLbl:SetText("Sending many lines rapidly may be considered\nspam and could trigger chat throttling.")

    local okBtn = BNB.CreateButton(nil, f, "Send", 90, 26)
    okBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, PAD)
    okBtn:SetScript("OnClick", function()
        if f._pendingLines and f._pendingChanType then
            DoSend(f._pendingLines, f._pendingChanType, f._pendingTarget)
        end
        f:Hide(); BNB.CloseSendToChat()
    end)
    local cancelBtn = BNB.CreateButton(nil, f, L["CANCEL"], 70, 26)
    cancelBtn:SetPoint("LEFT", okBtn, "RIGHT", 6, 0)
    cancelBtn:SetScript("OnClick", function() f:Hide() end)

    f:Hide(); return f
end

local function ShowConfirm(lines, chanType, target, ch)
    if not confirmFrame then confirmFrame = CreateConfirmDialog() end
    local f = confirmFrame
    f._pendingLines = lines; f._pendingChanType = chanType; f._pendingTarget = target

    local willSplit = false
    for _, l in ipairs(lines) do if #l > WOW_MSG_LIMIT then willSplit = true; break end end
    local extra = willSplit and "  |cffffff00(some lines will be split)|r" or ""
    if f._statsLbl then
        f._statsLbl:SetText(string.format("%d line(s)  |  %d total characters%s",
            #lines, TotalChars(lines), extra))
    end
    if f._chanLbl then
        f._chanLbl:SetText(string.format("Channel: %s%s|r%s", ChanColor(ch), ch.label,
            (chanType == "WHISPER" and target and target ~= "") and ("  ->  " .. target) or ""))
    end
    f:ClearAllPoints(); f:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    f:Show(); f:Raise()
end

-- ── Channel dropdown ───────────────────────────────────────────────────────────
local function BuildChannelDropdown(parent, onChange)
    local useNative = C_XMLUtil and C_XMLUtil.GetTemplateInfo
        and C_XMLUtil.GetTemplateInfo("WowStyle1DropdownTemplate")

    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(26)

    local curIdx   = 1
    local curLabel = ChanColor(CHANNELS[1]) .. CHANNELS[1].label .. "|r"

    local function labelToIdx(lbl)
        for i, ch in ipairs(CHANNELS) do
            if lbl == ChanColor(ch) .. ch.label .. "|r" or lbl == ch.label then return i end
        end
        return 1
    end

    -- Pre-declare dd so UpdateText closure can reference it safely
    local dd

    if useNative then
        dd = CreateFrame("DropdownButton", nil, container, "WowStyle1DropdownTemplate")
        dd:SetPoint("TOPLEFT",  container, "TOPLEFT",  0, 0)
        dd:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)
        dd:SetHeight(26)

        local function UpdateText()
            local ch = CHANNELS[curIdx]
            if dd.Text then
                dd.Text:SetText(ch.label)
                dd.Text:SetTextColor(ch.r, ch.g, ch.b)
            end
        end

        dd:SetupMenu(function(_, root)
            for _, ch in ipairs(CHANNELS) do
                local entry = ChanColor(ch) .. ch.label .. "|r"
                root:CreateRadio(entry,
                    function() return curLabel == entry end,
                    function()
                        curLabel = entry
                        curIdx   = labelToIdx(entry)
                        dd:GenerateMenu()
                        UpdateText()
                        if onChange then onChange(curIdx) end
                    end)
            end
        end)
        UpdateText()

        container.SetSelected = function(self, idx)
            curIdx   = idx
            curLabel = ChanColor(CHANNELS[idx]) .. CHANNELS[idx].label .. "|r"
            dd:GenerateMenu()
            local ch = CHANNELS[idx]
            if dd.Text then dd.Text:SetText(ch.label); dd.Text:SetTextColor(ch.r, ch.g, ch.b) end
        end
    else
        -- Fallback: cycling button
        local btn = BNB.CreateBackdropFrame("Button", nil, container)
        btn:SetHeight(26)
        btn:SetPoint("TOPLEFT",  container, "TOPLEFT",  0, 0)
        btn:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)
        if btn.SetBackdrop then
            btn:SetBackdrop({ bgFile="Interface\\Buttons\\White8x8",
                edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize=10, insets={left=2,right=2,top=2,bottom=2} })
            btn:SetBackdropColor(0.08,0.08,0.10,0.95)
            btn:SetBackdropBorderColor(0.35,0.35,0.35,1)
        end
        local st = btn:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        st:SetPoint("LEFT", btn, "LEFT", 8, 0); st:SetPoint("RIGHT", btn, "RIGHT", -20, 0)
        st:SetJustifyH("LEFT")
        local ch0 = CHANNELS[1]; st:SetText(ch0.label); st:SetTextColor(ch0.r, ch0.g, ch0.b)
        local ar = btn:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        ar:SetPoint("RIGHT", btn, "RIGHT", -6, 0); ar:SetText("▾"); ar:SetTextColor(0.65,0.65,0.65)

        local pp = CreateFrame("Frame", nil, btn, "BackdropTemplate")
        pp:SetFrameStrata("FULLSCREEN_DIALOG"); pp:SetFrameLevel(500); pp:SetClampedToScreen(true)
        if pp.SetBackdrop then
            pp:SetBackdrop({ bgFile="Interface\\Buttons\\White8x8",
                edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize=10, insets={left=2,right=2,top=2,bottom=2} })
            pp:SetBackdropColor(0.06,0.06,0.08,0.97); pp:SetBackdropBorderColor(0.5,0.5,0.5,1)
        end
        pp:Hide(); pp:EnableMouse(true)

        local function PopulateList()
            for _, c in ipairs({pp:GetChildren()}) do c:Hide(); c:SetParent(nil) end
            local rH, tH = 24, 0
            for i, ch in ipairs(CHANNELS) do
                local row = CreateFrame("Button", nil, pp)
                row:SetHeight(rH)
                row:SetPoint("TOPLEFT",  pp, "TOPLEFT",  2, -(tH+2))
                row:SetPoint("TOPRIGHT", pp, "TOPRIGHT", -2, -(tH+2))
                local hl = row:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints(); hl:SetColorTexture(1,1,1,0.10)
                local lbl = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
                lbl:SetPoint("LEFT", row, "LEFT", 8, 0)
                lbl:SetText(ch.label); lbl:SetTextColor(ch.r, ch.g, ch.b)
                local idx = i
                row:SetScript("OnClick", function()
                    curIdx = idx; st:SetText(ch.label); st:SetTextColor(ch.r, ch.g, ch.b)
                    pp:Hide(); if onChange then onChange(idx) end
                end)
                tH = tH + rH
            end
            pp:SetHeight(tH + 4)
        end
        btn:SetScript("OnClick", function()
            if pp:IsShown() then pp:Hide(); return end
            pp:SetWidth(btn:GetWidth()); PopulateList(); pp:ClearAllPoints()
            if (btn:GetBottom() or 0) - pp:GetHeight() < 0 then
                pp:SetPoint("BOTTOMLEFT", btn, "TOPLEFT", 0, 2)
            else
                pp:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
            end
            pp:Show()
        end)
        container.SetSelected = function(self, idx)
            curIdx = idx; local ch = CHANNELS[idx]
            st:SetText(ch.label); st:SetTextColor(ch.r, ch.g, ch.b)
        end
        container._popup = pp
    end
    container._dd = dd
    return container
end

-- ── Preview ────────────────────────────────────────────────────────────────────
-- Shows the expanded list (after split) as numbered rows with word-wrap.
local ROW_H = 13   -- base height per preview row
local NUM_W = 22   -- fixed width for line number column

local function GetPreviewFont()
    if BNB.GetBodyFont then
        local path = BNB.GetBodyFont()
        if path then return path, 11 end
    end
    return GameFontNormalSmall:GetFont(), 11
end

-- ExpandLines: sequential message numbers across all splits.
-- A 355-char paragraph → msg 1 (255 chars) + msg 2 (100 chars).
-- Next paragraph → msg 3. Continuous numbering, no split markers.
local function ExpandLines(lines)
    local out, msgNum = {}, 0
    for _, line in ipairs(lines) do
        local chunks = SplitLine(line)
        for _, chunk in ipairs(chunks) do
            msgNum = msgNum + 1
            out[#out + 1] = { text = chunk, msgNum = msgNum }
        end
    end
    return out
end

local function RebuildPreview(scrollChild, lines, ch)
    for _, child in ipairs({scrollChild:GetChildren()}) do child:Hide(); child:SetParent(nil) end
    for _, r   in ipairs({scrollChild:GetRegions()})  do r:Hide();     r:SetParent(nil)      end

    local cr = ch and ch.r or 1; local cg = ch and ch.g or 1; local cb = ch and ch.b or 1
    local fontPath, fontSize = GetPreviewFont()

    if #lines == 0 then
        local empty = scrollChild:CreateFontString(nil, "OVERLAY")
        pcall(function() empty:SetFont(fontPath, fontSize, "") end)
        empty:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", NUM_W + 6, -4)
        empty:SetHeight(ROW_H); empty:SetTextColor(0.45, 0.45, 0.45)
        empty:SetText("(note is empty)"); scrollChild:SetHeight(ROW_H + 8); return
    end

    local expanded = ExpandLines(lines)
    local y = 2

    for _, entry in ipairs(expanded) do
        local row = CreateFrame("Frame", nil, scrollChild)
        row:SetPoint("TOPLEFT",  scrollChild, "TOPLEFT",  0,  -y)
        row:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -2, -y)

        -- Sequential message number (grey)
        local numLbl = row:CreateFontString(nil, "OVERLAY")
        pcall(function() numLbl:SetFont(fontPath, fontSize, "") end)
        numLbl:SetPoint("TOPLEFT", row, "TOPLEFT", 4, 0)
        numLbl:SetWidth(NUM_W); numLbl:SetHeight(ROW_H); numLbl:SetJustifyH("RIGHT")
        numLbl:SetTextColor(0.40, 0.40, 0.40)
        numLbl:SetText(tostring(entry.msgNum))

        -- Message content with word-wrap
        local textLbl = row:CreateFontString(nil, "OVERLAY")
        pcall(function() textLbl:SetFont(fontPath, fontSize, "") end)
        textLbl:SetPoint("TOPLEFT",  row, "TOPLEFT",  NUM_W + 6, 0)
        textLbl:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0,         0)
        textLbl:SetJustifyH("LEFT"); textLbl:SetWordWrap(true)
        textLbl:SetTextColor(cr, cg, cb); textLbl:SetText(entry.text)

        -- Estimate row height based on expected line wraps
        local availW = math.max(40, (scrollChild:GetWidth() or 200) - NUM_W - 22)
        local charsPerLine = math.max(8, math.floor(availW / (fontSize * 0.55)))
        local estLines = math.ceil(math.max(1, #entry.text) / charsPerLine)
        row:SetHeight(estLines * ROW_H)
        y = y + estLines * ROW_H   -- tight list, no gap
    end
    scrollChild:SetHeight(math.max(y + 2, ROW_H))
end

-- ── Build main dialog ──────────────────────────────────────────────────────────
local function CreateSendDialog()
    local skinMode = BigNoteBoxDB and BigNoteBoxDB.skinMode
    local f

    if skinMode then
        f = BNB.CreateSkinFrame(UIParent, false, "BigNoteBoxSendDialog", false)
        _G["BigNoteBoxSendDialog"] = f
        f:SetSize(DLG_W, DLG_H)
        f:SetFrameStrata("DIALOG")
        f:SetToplevel(true); f:SetClampedToScreen(true)
        f:SetMovable(true); f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self) self:StartMoving() end)
        f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)

        local titleBar = BNB.CreateSkinStrip(f, true, false)
        titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
        titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
        titleBar:SetHeight(SK_STC_TITLE_H)
        titleBar:EnableMouse(true)
        titleBar:RegisterForDrag("LeftButton")
        titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
        titleBar:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

        local titleLbl = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        titleLbl:SetPoint("CENTER", titleBar, "CENTER", -12, 0)
        titleLbl:SetTextColor(1, 0.82, 0)
        titleLbl:SetText(L["SEND_TITLE"])

        local closeBtn = BNB.CreateSkinCloseButton(titleBar, function() BNB.CloseSendToChat() end)
        closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -3, 0)

        f:SetScript("OnShow", function()
            if BNB.ApplyMainWindowSkin then BNB.ApplyMainWindowSkin() end
        end)
    else
        f = CreateFrame("Frame", "BigNoteBoxSendDialog", UIParent, "ButtonFrameTemplate")
        f:SetSize(DLG_W, DLG_H)
        f:SetFrameStrata("DIALOG")
        f:SetToplevel(true); f:SetClampedToScreen(true)
        f:SetMovable(true); f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self) self:StartMoving() end)
        f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
        ButtonFrameTemplate_HidePortrait(f); ButtonFrameTemplate_HideButtonBar(f)
        if f.Inset then f.Inset:Hide() end
        f:SetAlpha(0.97); f:SetTitle(L["SEND_TITLE"])
        if f.CloseButton then
            f.CloseButton:SetScript("OnClick", function() BNB.CloseSendToChat() end)
        end
    end
    tinsert(UISpecialFrames, "BigNoteBoxSendDialog")

    -- Esc closes
    f:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then BNB.CloseSendToChat() end
    end)
    f:EnableKeyboard(true)

    local y = skinMode and -(SK_STC_TITLE_H + 8) or -TITLE_H

    -- Channel label + dropdown
    local chanHdr = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    chanHdr:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    chanHdr:SetTextColor(0.78, 0.78, 0.78); chanHdr:SetText(L["SEND_CHANNEL_LABEL"])
    y = y - 18

    local chanDropContainer
    chanDropContainer = BuildChannelDropdown(f, function(idx)
        _selChannel = idx
        local needsTarget = CHANNELS[idx] and CHANNELS[idx].needsTarget
        if f._targetRow then f._targetRow:SetShown(needsTarget == true) end
        if f._previewScrollChild then
            local note  = _noteID and BNB.GetNote(_noteID)
            local lines = GetLines(note and note.body or "", _lineByLine)
            RebuildPreview(f._previewScrollChild, lines, CHANNELS[idx])
        end
    end)
    chanDropContainer:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, y)
    chanDropContainer:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
    f._chanDrop = chanDropContainer
    y = y - 32

    -- Whisper target row
    local targetRow = CreateFrame("Frame", nil, f)
    targetRow:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, y)
    targetRow:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
    targetRow:SetHeight(24); targetRow:Hide()
    f._targetRow = targetRow

    local targetLbl = targetRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    targetLbl:SetPoint("LEFT", targetRow, "LEFT", 0, 0)
    targetLbl:SetTextColor(0.78, 0.78, 0.78); targetLbl:SetText("Target:")

    local targetEb = CreateFrame("EditBox", nil, targetRow,
        "BackdropTemplate")
    BNB.EnsureBackdrop(targetEb)
    targetEb:SetPoint("LEFT",  targetLbl, "RIGHT",  6, 0)
    targetEb:SetPoint("RIGHT", targetRow, "RIGHT",  0, 0)
    targetEb:SetHeight(20); targetEb:SetFontObject("GameFontNormal")
    targetEb:SetAutoFocus(false); targetEb:SetMaxLetters(64)
    BNB.SetBackdropDark(targetEb)
    targetEb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    BNB.AddPlaceholder(targetEb, "Player name", 0.38, 0.38, 0.38)
    f._targetEb = targetEb
    y = y - 30

    -- Line-by-line toggle
    local lineCheck = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    lineCheck:SetSize(20, 20); lineCheck:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    lineCheck:SetChecked(_lineByLine)
    local lineLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lineLbl:SetPoint("LEFT", lineCheck, "RIGHT", 4, 0)
    lineLbl:SetTextColor(0.88, 0.88, 0.88); lineLbl:SetText(L["SEND_LINE_BY_LINE"])
    f._lineCheck = lineCheck
    y = y - 28

    -- Stats label
    local statsLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statsLbl:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, y)
    statsLbl:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
    statsLbl:SetJustifyH("LEFT"); statsLbl:SetTextColor(0.55, 0.55, 0.55)
    f._statsLbl = statsLbl
    y = y - 20

    -- Preview header
    local previewHdr = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    previewHdr:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    previewHdr:SetTextColor(0.78, 0.78, 0.78); previewHdr:SetText("Preview:")
    y = y - 18

    -- Preview scroll — scrollbar renders outside ScrollFrameTemplate to the right,
    -- so we leave PAD on the left and PAD+16 on the right so the bar stays inside
    -- the dialog window.
    local PREVIEW_H = 220
    local previewSF = CreateFrame("ScrollFrame", nil, f, "ScrollFrameTemplate")
    previewSF:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD,       y)
    previewSF:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(PAD+16), y)
    previewSF:SetHeight(PREVIEW_H)
    if previewSF.ScrollBar then
        previewSF.ScrollBar:SetAlpha(0)
        previewSF:HookScript("OnScrollRangeChanged", function(_, _, yRange)
            previewSF.ScrollBar:SetAlpha((yRange or 0) > 1 and 1.0 or 0)
        end)
    end

    -- Dark background behind the scroll frame
    local previewBg = BNB.CreateBackdropFrame("Frame", nil, f)
    previewBg:SetPoint("TOPLEFT",     previewSF, "TOPLEFT",     -2,  2)
    previewBg:SetPoint("BOTTOMRIGHT", previewSF, "BOTTOMRIGHT",  2, -2)
    previewBg:SetFrameLevel(previewSF:GetFrameLevel() - 1)
    BNB.SetBackdrop(previewBg, 0.04, 0.04, 0.06, 1, 0.28, 0.28, 0.30, 1)

    local previewChild = CreateFrame("Frame", nil, previewSF)
    previewChild:SetHeight(1)
    previewSF:SetScrollChild(previewChild)
    -- Sync child width when layout resolves (GetWidth is 0 at build time)
    previewSF:HookScript("OnShow", function(self)
        C_Timer.After(0, function()
            local w = self:GetWidth()
            if w > 0 then previewChild:SetWidth(w - 22) end
        end)
    end)
    previewSF:SetScript("OnSizeChanged", function(self)
        local w = self:GetWidth()
        if w > 0 then previewChild:SetWidth(w - 22) end
    end)
    f._previewScrollChild = previewChild
    f._previewSF          = previewSF
    y = y - PREVIEW_H - 8

    -- ── Bottom action buttons: send.tga and bcb-icon.tga, centred in the dialog ──
    -- Both anchored to fixed positions on `f` so neither moves when the other grows.
    -- Icon pair: 32+16+32 = 80px wide, centred in DLG_W=340 → left edge at x=130.
    local ASSETS_STC  = "Interface\\AddOns\\BigNoteBox\\Assets\\"
    local ICON_NORM   = 32
    local ICON_HOVER  = 36
    local ICON_BTN_Y  = PAD    -- bottom margin
    local ICON_GAP    = 16     -- gap between the two icons
    local iconPairW   = ICON_NORM * 2 + ICON_GAP
    local iconLeftX   = math.floor((DLG_W - iconPairW) / 2)   -- 130
    local iconRightX  = iconLeftX + ICON_NORM + ICON_GAP       -- 178

    -- Helper: make a 32×32 icon button that grows on hover but is anchored by BOTTOMLEFT
    local function MakeBottomIcon(texName, tip, sub)
        local btn = CreateFrame("Button", nil, f)
        btn:SetSize(ICON_NORM, ICON_NORM)
        local tx = btn:CreateTexture(nil, "ARTWORK")
        tx:SetAllPoints()
        tx:SetTexture(ASSETS_STC .. texName)
        btn:SetScript("OnEnter", function(self)
            self:SetSize(ICON_HOVER, ICON_HOVER)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(tip, 1, 1, 1)
            if sub then GameTooltip:AddLine(sub, 0.78, 0.78, 0.78, true) end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function(self)
            self:SetSize(ICON_NORM, ICON_NORM)
            GameTooltip:Hide()
        end)
        btn._tx = tx
        return btn
    end

    -- Send button (send.tga)
    local sendBtn = MakeBottomIcon("Actionbar\\ab-send", "Send to Chat",
        "Send note lines to the selected channel.")
    sendBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", iconLeftX, ICON_BTN_Y)
    sendBtn:SetScript("OnClick", function()
        local note = _noteID and BNB.GetNote(_noteID)
        if not note then BNB.CloseSendToChat(); return end
        local body = note.body or ""
        if body == "" then BNB:Print(L["SEND_EMPTY"]); return end

        local ch       = CHANNELS[_selChannel]
        local chanType = ch and ch.type or "SAY"
        local target   = (ch and ch.needsTarget)
            and (f._targetEb and not f._targetEb._showingPlaceholder
                 and f._targetEb:GetText() or "") or nil

        if chanType == "WHISPER" and (not target or target == "") then
            BNB:Print("|cffff6666Please enter a target name for Whisper.|r")
            if f._targetEb then f._targetEb:SetFocus() end; return
        end

        local lines = GetLines(body, _lineByLine)
        if #lines == 0 then BNB:Print(L["SEND_EMPTY"]); return end

        if #lines > CONFIRM_THRESHOLD then
            ShowConfirm(lines, chanType, target, ch)
        else
            DoSend(lines, chanType, target)
            BNB.CloseSendToChat()
        end
    end)
    f._sendBtn = sendBtn

    -- BCB button (bcb-icon.tga) — shown when BigChatBox is active
    local bcbBtn = MakeBottomIcon("BCB\\bcb-icon", "Send to BCB Multiline Box",
        "Opens BigChatBox multiline input with the text pre-filled so you can edit before sending.")
    bcbBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", iconRightX, ICON_BTN_Y)
    bcbBtn:SetScript("OnClick", function()
        local note = _noteID and BNB.GetNote(_noteID)
        if not note or (note.body or "") == "" then
            BNB:Print(L["SEND_EMPTY"]); return
        end
        SendToBCB(note.body)
    end)
    if not (BigChatBox and BigChatBox.SendDirect) then bcbBtn:Hide() end
    f._bcbBtn = bcbBtn

    -- "Get BCB" promo button — shown when BigChatBox is NOT installed (same slot as bcbBtn)
    local getBCBBtn = MakeBottomIcon("BCB\\bcb-icon", "Get BigChatBox",
        "Install BigChatBox to enable direct multiline chat integration.")
    getBCBBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", iconRightX, ICON_BTN_Y)
    -- Slight desaturation to hint it's inactive/promo
    getBCBBtn:SetAlpha(0.55)
    getBCBBtn:SetScript("OnEnter", function(self)
        self:SetSize(ICON_HOVER, ICON_HOVER)
        self:SetAlpha(1.0)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Get BigChatBox", 1, 1, 1)
        GameTooltip:AddLine("Install BigChatBox to enable direct multiline\nchat integration. Click to learn more.", 0.78, 0.78, 0.78, true)
        GameTooltip:Show()
    end)
    getBCBBtn:SetScript("OnLeave", function(self)
        self:SetSize(ICON_NORM, ICON_NORM)
        self:SetAlpha(0.55)
        GameTooltip:Hide()
    end)
    getBCBBtn:SetScript("OnClick", function()
        if BNB.ShowBCBPromo then BNB.ShowBCBPromo() end
    end)
    if BigChatBox and BigChatBox.SendDirect then getBCBBtn:Hide() end
    f._getBCBBtn = getBCBBtn

    f:Hide(); return f
end

-- ── Refresh preview + stats ────────────────────────────────────────────────────
local function RefreshPreview()
    if not dlgFrame or not dlgFrame:IsShown() then return end
    local note  = _noteID and BNB.GetNote(_noteID)
    local lines = GetLines(note and note.body or "", _lineByLine)
    local ch    = CHANNELS[_selChannel]

    if dlgFrame._previewScrollChild then
        RebuildPreview(dlgFrame._previewScrollChild, lines, ch)
        if dlgFrame._previewSF then dlgFrame._previewSF:SetVerticalScroll(0) end
    end

    if dlgFrame._statsLbl then
        local expanded = ExpandLines(lines)
        if #lines == 0 then
            dlgFrame._statsLbl:SetText("|cffff6666Note is empty.|r")
        elseif #expanded > CONFIRM_THRESHOLD then
            dlgFrame._statsLbl:SetText(string.format(
                "|cffffff00%d line(s) -> %d message(s), %d chars - confirmation required|r",
                #lines, #expanded, TotalChars(lines)))
        else
            dlgFrame._statsLbl:SetText(string.format(
                "|cff888888%d line(s) -> %d message(s), %d chars|r",
                #lines, #expanded, TotalChars(lines)))
        end
    end

    if dlgFrame._lineCheck then
        dlgFrame._lineCheck:SetScript("OnClick", function(self)
            _lineByLine = self:GetChecked()
            RefreshPreview()
        end)
    end
end

-- ── Public API ─────────────────────────────────────────────────────────────────
function BNB.OpenSendToChat(noteID)
    if InCombatLockdown() then BNB:Print(L["COMBAT_BLOCKED"]); return end
    local note = noteID and BNB.GetNote(noteID)
    if not note then return end

    _noteID = noteID
    if not dlgFrame then dlgFrame = CreateSendDialog() end

    _selChannel = 1; _lineByLine = true
    if dlgFrame._lineCheck  then dlgFrame._lineCheck:SetChecked(true)  end
    if dlgFrame._chanDrop   then dlgFrame._chanDrop:SetSelected(1)      end
    if dlgFrame._targetRow  then dlgFrame._targetRow:Hide()             end
    if dlgFrame._targetEb   then
        dlgFrame._targetEb:SetText("")
        BNB.AddPlaceholder(dlgFrame._targetEb, "Player name", 0.38, 0.38, 0.38)
    end

    dlgFrame:ClearAllPoints()
    if BNB.mainFrame and BNB.mainFrame:IsShown() then
        dlgFrame:SetPoint("BOTTOM", BNB.mainFrame, "BOTTOM", 0, 40)
    else
        dlgFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end

    dlgFrame:Show(); dlgFrame:Raise()
    -- Refresh BCB / Get BCB buttons: BCB may have loaded after the dialog was first built
    local hasBCB = BigChatBox and BigChatBox.SendDirect and true or false
    if dlgFrame._bcbBtn    then dlgFrame._bcbBtn:SetShown(hasBCB)    end
    if dlgFrame._getBCBBtn then dlgFrame._getBCBBtn:SetShown(not hasBCB) end
    RefreshPreview()
end

function BNB.CloseSendToChat()
    if dlgFrame then dlgFrame:Hide() end
end

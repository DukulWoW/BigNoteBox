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
--   • Paced sending (BUG-29): party/raid/guild/officer/whisper go out one
--     message every CHAT_TICK seconds with a k/N status; say/yell need the
--     click itself outdoors, so they send one message per click of Send
--     (Dukul, 2026-10-02). Closing the dialog stops a send part way.
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
local CHAT_TICK         = 0.35   -- seconds between paced messages

-- ── Channel definitions ────────────────────────────────────────────────────────
local CHANNELS = {
    { type = "SAY",     label = L["CHAN_SAY"],     r = 1.00, g = 1.00, b = 1.00 },
    { type = "YELL",    label = L["CHAN_YELL"],    r = 1.00, g = 0.25, b = 0.25 },
    { type = "PARTY",   label = L["CHAN_PARTY"],   r = 0.67, g = 0.67, b = 1.00 },
    { type = "RAID",    label = L["CHAN_RAID"],    r = 1.00, g = 0.50, b = 0.00 },
    { type = "GUILD",   label = L["CHAN_GUILD"],   r = 0.25, g = 1.00, b = 0.25 },
    { type = "OFFICER", label = L["CHAN_OFFICER"], r = 0.25, g = 0.75, b = 0.75 },
    { type = "WHISPER", label = L["CHAN_WHISPER"], r = 0.85, g = 0.50, b = 1.00, needsTarget = true },
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

-- The text that goes to chat: a rich note's markup is left out, a link keeps
-- its text (ALL-345: the {h1} / {col} tags went to chat as typed)
local function ChatBody(note)
    if not note then return "" end
    local body = note.body or ""
    if note.richMode then
        body = body:gsub("{link%*([^*}]+)%*([^}]*)}", function(url, text)
            return text ~= "" and text or url
        end)
        body = body:gsub("{br}", "\n")
        local AM = BNB.AdvancedMode
        if AM and AM.StripMarkup then body = AM.StripMarkup(body) end
    end
    return body
end

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

-- ── Paced sending (BUG-29) ─────────────────────────────────────────────────────
-- One send at a time. Sending every message in the same frame let the server's
-- chat throttle drop lines of long notes, and every line was counted as sent.
local PACED = { PARTY = true, RAID = true, GUILD = true, OFFICER = true, WHISPER = true }
local _job  = nil   -- { items, chanType, target, label, pos, sent, perClick, ticker }

-- Encounters, Mythic+ and rated PvP lock addon chat on Midnight
local function ChatLocked()
    return C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() or false
end

-- Returns true when the message went out without an error.
local function SendOne(text, chanType, target)
    local bcb = BNB.hasBCB and BigChatBox and BigChatBox.SendDirect
    if bcb then return (pcall(bcb, text, chanType, target, nil)) end
    if chanType == "WHISPER" then return (pcall(SafeSend, text, chanType, nil, target)) end
    return (pcall(SafeSend, text, chanType))
end

-- Lines -> messages, long lines split at word boundaries
local function BuildItems(lines)
    local items = {}
    for _, line in ipairs(lines) do
        if line ~= "" then
            for _, chunk in ipairs(SplitLine(line)) do items[#items + 1] = chunk end
        end
    end
    return items
end

local function ShowJobStatus()
    if not (_job and dlgFrame and dlgFrame._statsLbl) then return end
    if _job.perClick then
        dlgFrame._statsLbl:SetText(string.format(L["STC_STATUS_NEXT_FMT"], _job.pos, #_job.items))
    else
        dlgFrame._statsLbl:SetText(string.format(L["STC_STATUS_SENDING_FMT"], _job.pos - 1, #_job.items))
    end
end

-- reason: "done" (closes the dialog), "locked" (closes it), "stopped" (the
-- dialog closed, the channel or the line setting changed)
local function EndJob(reason)
    local job = _job
    if not job then return end
    _job = nil
    if job.ticker then job.ticker:Cancel() end
    if reason == "done" then
        BNB:Print(string.format(L["SEND_COMPLETE"], job.sent, job.label))
    elseif reason == "locked" then
        BNB:Print(string.format(L["STC_LOCKED_FMT"], job.sent, #job.items))
    elseif job.sent > 0 then
        BNB:Print(string.format(L["STC_STOPPED_FMT"], job.sent, #job.items))
    end
    if reason ~= "stopped" then BNB.CloseSendToChat() end
end

local function SendNext()
    local job = _job
    if not job then return end
    if ChatLocked() then EndJob("locked"); return end
    if SendOne(job.items[job.pos], job.chanType, job.target) then job.sent = job.sent + 1 end
    job.pos = job.pos + 1
    if job.pos > #job.items then EndJob("done") else ShowJobStatus() end
end

-- The first message always goes out inside the click that started the send.
local function StartJob(lines, chanType, target)
    EndJob("stopped")
    local items = BuildItems(lines)
    if #items == 0 then return end
    local ch = CHANNELS[_selChannel]
    _job = { items = items, chanType = chanType, target = target, pos = 1, sent = 0,
             label = ch and ch.label or chanType, perClick = not PACED[chanType] }
    SendNext()
    if _job and not _job.perClick then
        _job.ticker = C_Timer.NewTicker(CHAT_TICK, SendNext)
    end
end

local function SendToBCB(body)
    if not (BigChatBox and BCB_OpenMultiline) then
        BNB:Print(L["STC_NO_BCB"])
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
local function CreateConfirmDialog()
    local f = BNB.CreateToolWindow({   -- shared chrome (CMP-02)
        name = "BigNoteBoxSendConfirm", w = 300, h = 180,
        title = L["STC_CONFIRM_SEND_TITLE"], strata = "FULLSCREEN_DIALOG",
        toplevel = true, escClose = true,
    })
    -- top of content below title chrome
    local contentY = f._isSkin and -(BNB.TOOL_SKIN_TITLE_H + 8) or -TITLE_H

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

    if f._isSkin then
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
    warnLbl:SetText(L["STC_SPAM_WARNING"])

    local okBtn = BNB.CreateButton(nil, f, L["SEND_CONFIRM_BTN"], 90, 26)
    okBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, PAD)
    okBtn:SetScript("OnClick", function()
        f:Hide()
        if f._pendingLines and f._pendingChanType then
            StartJob(f._pendingLines, f._pendingChanType, f._pendingTarget)
        end
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
    local extra = willSplit and L["STC_CONFIRM_SPLIT_HINT"] or ""
    if f._statsLbl then
        f._statsLbl:SetText(string.format(L["STC_CONFIRM_STATS_FMT"],
            #lines, TotalChars(lines), extra))
    end
    if f._chanLbl then
        f._chanLbl:SetText(string.format(L["STC_CONFIRM_CHANNEL_FMT"], ChanColor(ch), ch.label,
            (chanType == "WHISPER" and target and target ~= "") and ("  ->  " .. target) or ""))
    end
    f:ClearAllPoints(); f:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    f:Show(); f:Raise()
end

-- ── Channel dropdown ───────────────────────────────────────────────────────────
local function BuildChannelDropdown(parent, onChange)

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
        if path then return path, BNB.FontPx(path, 11) end
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
        empty:SetText(L["STC_PREVIEW_EMPTY"]); scrollChild:SetHeight(ROW_H + 8); return
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
    -- Chrome for both modes (CMP-02 S3); ESC closes through its own key handler too
    local f = BNB.CreateToolWindow({
        name = "BigNoteBoxSendDialog", w = DLG_W, h = DLG_H,
        title = L["SEND_TITLE"], toplevel = true, escClose = true, keyEsc = true,
        onClose = function() BNB.CloseSendToChat() end,
    })

    local y = f._isSkin and -(BNB.TOOL_SKIN_TITLE_H + 8) or -TITLE_H

    -- Channel label + dropdown
    local chanHdr = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    chanHdr:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    chanHdr:SetTextColor(0.78, 0.78, 0.78); chanHdr:SetText(L["SEND_CHANNEL_LABEL"])
    y = y - 18

    local chanDropContainer
    chanDropContainer = BuildChannelDropdown(f, function(idx)
        EndJob("stopped")
        _selChannel = idx
        local needsTarget = CHANNELS[idx] and CHANNELS[idx].needsTarget
        if f._targetRow then f._targetRow:SetShown(needsTarget == true) end
        if f._previewScrollChild then
            local note  = _noteID and BNB.GetNote(_noteID)
            local lines = GetLines(ChatBody(note), _lineByLine)
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
    targetLbl:SetTextColor(0.78, 0.78, 0.78); targetLbl:SetText(L["STC_TARGET_LBL"])

    local targetEb = CreateFrame("EditBox", nil, targetRow,
        "BackdropTemplate")
    BNB.EnsureBackdrop(targetEb)
    targetEb:SetPoint("LEFT",  targetLbl, "RIGHT",  6, 0)
    targetEb:SetPoint("RIGHT", targetRow, "RIGHT",  0, 0)
    targetEb:SetHeight(20); targetEb:SetFontObject("GameFontNormal")
    targetEb:SetAutoFocus(false); targetEb:SetMaxLetters(64)
    BNB.SetBackdropDark(targetEb)
    targetEb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    BNB.AddPlaceholder(targetEb, L["STC_TARGET_PLACEHOLDER"], 0.38, 0.38, 0.38)
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
    previewHdr:SetTextColor(0.78, 0.78, 0.78); previewHdr:SetText(L["STC_PREVIEW_HDR"])
    y = y - 18

    -- Preview scroll — scrollbar renders outside ScrollFrameTemplate to the right,
    -- so we leave PAD on the left and PAD+16 on the right so the bar stays inside
    -- the dialog window.
    local PREVIEW_H = 220
    local previewSF = BNB.CreateScrollFrame(nil, f)
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
    local sendBtn = MakeBottomIcon(BNB.AbIcon("send"), L["STC_SEND_TIP"],
        L["STC_SEND_TIP_SUB"])
    sendBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", iconLeftX, ICON_BTN_Y)
    sendBtn:SetScript("OnClick", function()
        -- Say/yell: each click sends the next message; a paced send runs by itself
        if _job then
            if _job.perClick then SendNext() end
            return
        end
        local note = _noteID and BNB.GetNote(_noteID)
        if not note then BNB.CloseSendToChat(); return end
        local body = ChatBody(note)
        if body == "" then BNB:Print(L["SEND_EMPTY"]); return end

        local ch       = CHANNELS[_selChannel]
        local chanType = ch and ch.type or "SAY"
        local target   = (ch and ch.needsTarget)
            and (f._targetEb and not f._targetEb._showingPlaceholder
                 and f._targetEb:GetText() or "") or nil

        if chanType == "WHISPER" and (not target or target == "") then
            BNB:Print(L["STC_NO_WHISPER_TARGET"])
            if f._targetEb then f._targetEb:SetFocus() end; return
        end

        local lines = GetLines(body, _lineByLine)
        if #lines == 0 then BNB:Print(L["SEND_EMPTY"]); return end

        if ChatLocked() then
            BNB:Print(string.format(L["STC_LOCKED_FMT"], 0, #BuildItems(lines)))
            return
        end
        if #lines > CONFIRM_THRESHOLD then
            ShowConfirm(lines, chanType, target, ch)
        else
            StartJob(lines, chanType, target)
        end
    end)
    f._sendBtn = sendBtn

    -- BCB button (bcb-icon.tga) — shown when BigChatBox is active
    local bcbBtn = MakeBottomIcon("BCB\\bcb-icon", L["STC_BCB_TIP"],
        L["STC_BCB_TIP_SUB"])
    bcbBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", iconRightX, ICON_BTN_Y)
    bcbBtn:SetScript("OnClick", function()
        local note = _noteID and BNB.GetNote(_noteID)
        local body = ChatBody(note)
        if body == "" then
            BNB:Print(L["SEND_EMPTY"]); return
        end
        SendToBCB(body)
    end)
    if not (BigChatBox and BigChatBox.SendDirect) then bcbBtn:Hide() end
    f._bcbBtn = bcbBtn

    -- "Get BCB" promo button — shown when BigChatBox is NOT installed (same slot as bcbBtn)
    local getBCBBtn = MakeBottomIcon("BCB\\bcb-icon", L["STC_GET_BCB_TIP"],
        L["STC_GET_BCB_TIP_SUB"])
    getBCBBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", iconRightX, ICON_BTN_Y)
    -- Slight desaturation to hint it's inactive/promo
    getBCBBtn:SetAlpha(0.55)
    getBCBBtn:SetScript("OnEnter", function(self)
        self:SetSize(ICON_HOVER, ICON_HOVER)
        self:SetAlpha(1.0)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["STC_GET_BCB_TIP"], 1, 1, 1)
        GameTooltip:AddLine(L["STC_GET_BCB_TIP_SUB2"], 0.78, 0.78, 0.78, true)
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

    f:HookScript("OnHide", function()
        EndJob("stopped")
        if confirmFrame then confirmFrame:Hide() end
    end)

    f:Hide(); return f
end

-- ── Refresh preview + stats ────────────────────────────────────────────────────
local function RefreshPreview()
    if not dlgFrame or not dlgFrame:IsShown() then return end
    local note  = _noteID and BNB.GetNote(_noteID)
    local lines = GetLines(ChatBody(note), _lineByLine)
    local ch    = CHANNELS[_selChannel]

    if dlgFrame._previewScrollChild then
        RebuildPreview(dlgFrame._previewScrollChild, lines, ch)
        if dlgFrame._previewSF then dlgFrame._previewSF:SetVerticalScroll(0) end
    end

    if dlgFrame._statsLbl then
        local expanded = ExpandLines(lines)
        if #lines == 0 then
            dlgFrame._statsLbl:SetText(L["STC_STATS_EMPTY"])
        elseif #expanded > CONFIRM_THRESHOLD then
            dlgFrame._statsLbl:SetText(string.format(
                L["STC_STATS_CONFIRM_FMT"],
                #lines, #expanded, TotalChars(lines)))
        else
            dlgFrame._statsLbl:SetText(string.format(
                L["STC_STATS_NORMAL_FMT"],
                #lines, #expanded, TotalChars(lines)))
        end
    end

    if dlgFrame._lineCheck then
        dlgFrame._lineCheck:SetScript("OnClick", function(self)
            EndJob("stopped")
            _lineByLine = self:GetChecked()
            RefreshPreview()
        end)
    end
    ShowJobStatus()
end

-- ── Public API ─────────────────────────────────────────────────────────────────
function BNB.OpenSendToChat(noteID)
    if InCombatLockdown() then BNB:Print(L["COMBAT_BLOCKED"]); return end
    local note = noteID and BNB.GetNote(noteID)
    if not note then return end

    EndJob("stopped")
    _noteID = noteID
    if not dlgFrame then dlgFrame = CreateSendDialog() end

    _selChannel = 1; _lineByLine = true
    if dlgFrame._lineCheck  then dlgFrame._lineCheck:SetChecked(true)  end
    if dlgFrame._chanDrop   then dlgFrame._chanDrop:SetSelected(1)      end
    if dlgFrame._targetRow  then dlgFrame._targetRow:Hide()             end
    if dlgFrame._targetEb   then
        dlgFrame._targetEb:SetText("")
        BNB.AddPlaceholder(dlgFrame._targetEb, L["STC_TARGET_PLACEHOLDER"], 0.38, 0.38, 0.38)
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

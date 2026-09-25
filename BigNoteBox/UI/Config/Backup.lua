-- BigNoteBox UI/Config/Backup.lua - Settings Backup tab (Export / Import),
-- the fallback export window and the per-note export entry points.
-- The codec itself is Features/NoteExport.lua.
-- Split out of ConfigWindow.lua (ALL-65.10).

local BNB = BigNoteBox
local L   = BNB.L

local K = BNB._ConfigKit
local CONTENT_W, ASSET   = K.CONTENT_W, K.ASSET
local AddRule, AddHeader = K.AddRule, K.AddHeader

-- Export window HTML mode: "noteonly", "plain", "stylized". Kept for the
-- session, so the per-note HTML export reuses the last choice.
local _htmlExportMode = "plain"

local function BuildBackupTab(sf, ct)
    local NE = BNB.NoteExport
    local y = -8

    -- ── Export section ────────────────────────────────────────────────────────
    y = AddHeader(ct, y, L["BACKUP_EXPORT_HEADER"])

    local desc = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    desc:SetPoint("TOPLEFT",  ct, "TOPLEFT",  0, y)
    desc:SetWidth(CONTENT_W); desc:SetJustifyH("LEFT")
    desc:SetWordWrap(true); desc:SetHeight(32)
    desc:SetTextColor(0.78, 0.78, 0.78)
    desc:SetText(L["BACKUP_EXPORT_DESC"])
    y = y - 38

    -- Format radio buttons
    local _exportFmt = NE.FMT_MARKDOWN   -- local state for this tab instance

    local function MakeRadio(label, fmt, xOff)
        local rb = CreateFrame("CheckButton", nil, ct, "UICheckButtonTemplate")
        rb:SetSize(20, 20)
        rb:SetPoint("TOPLEFT", ct, "TOPLEFT", xOff, y + 2)
        rb:SetChecked(_exportFmt == fmt)
        local lbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("LEFT", rb, "RIGHT", 4, 0)
        lbl:SetText(label)
        return rb
    end

    local rbMd   = MakeRadio(L["BACKUP_FORMAT_MARKDOWN"], NE.FMT_MARKDOWN, 0)
    local rbJson = MakeRadio(L["BACKUP_FORMAT_JSON"],     NE.FMT_JSON,     CONTENT_W / 2)
    -- Explicitly sync state after both buttons exist so neither is stuck visually checked
    rbMd:SetChecked(true); rbJson:SetChecked(false)

    -- Format description (single label, swaps text with the radio selection)
    y = y - 26
    local fmtDesc = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fmtDesc:SetPoint("TOPLEFT",  ct, "TOPLEFT",  0, y)
    fmtDesc:SetPoint("TOPRIGHT", ct, "TOPRIGHT", 0, y)
    fmtDesc:SetJustifyH("LEFT")
    fmtDesc:SetWordWrap(true)
    fmtDesc:SetHeight(32)   -- two wrapped lines at GameFontNormalSmall ≈ 13px each + gap
    fmtDesc:SetTextColor(0.60, 0.60, 0.60)
    fmtDesc:SetText(L["BACKUP_FMT_DESC_MARKDOWN"])
    y = y - 38

    rbMd:SetScript("OnClick", function()
        _exportFmt = NE.FMT_MARKDOWN
        rbMd:SetChecked(true); rbJson:SetChecked(false)
        fmtDesc:SetText(L["BACKUP_FMT_DESC_MARKDOWN"])
    end)
    rbJson:SetScript("OnClick", function()
        _exportFmt = NE.FMT_JSON
        rbJson:SetChecked(true); rbMd:SetChecked(false)
        fmtDesc:SetText(L["BACKUP_FMT_DESC_JSON"])
    end)

    -- Export button + status label
    local exportBtn = BNB.CreateButton(nil, ct, L["BACKUP_BTN_EXPORT"], 180, 26)
    exportBtn:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)

    local exportStatus = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    exportStatus:SetPoint("LEFT", exportBtn, "RIGHT", 10, 0)
    exportStatus:SetPoint("RIGHT", ct, "RIGHT", 0, 0)
    exportStatus:SetJustifyH("LEFT")
    exportStatus:SetHeight(26)
    exportStatus:SetTextColor(0.55, 0.82, 0.55)
    exportStatus:SetText("")

    exportBtn:SetScript("OnClick", function()
        local text, n = NE.SerializeNotes(_exportFmt)
        if not text or n == 0 then
            exportStatus:SetTextColor(0.82, 0.55, 0.55)
            exportStatus:SetText(L["BACKUP_IMPORT_NONE"])
            return
        end
        -- C_System.SetClipboard is nil on retail and Forever (ALL-21), so the
        -- export always goes to the scrollable editbox window for a manual copy
        BNB.OpenExportWindow(text)
        exportStatus:SetTextColor(0.78, 0.78, 0.78)
        exportStatus:SetText(L["BACKUP_BTN_COPY_FALLBACK"])
    end)
    y = y - 40

    y = AddRule(ct, y) - 4

    -- ── Import section ────────────────────────────────────────────────────────
    y = AddHeader(ct, y, L["BACKUP_IMPORT_HEADER"])

    local desc2 = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    desc2:SetPoint("TOPLEFT",  ct, "TOPLEFT",  0, y)
    desc2:SetWidth(CONTENT_W); desc2:SetJustifyH("LEFT")
    desc2:SetWordWrap(true); desc2:SetHeight(42)
    desc2:SetTextColor(0.78, 0.78, 0.78)
    desc2:SetText(L["BACKUP_IMPORT_DESC"])
    y = y - 48

    -- Paste target editbox (scrollable, fixed height)
    -- Shrunk from 140 (ALL-14, Dukul 2026-09-23): Data Summary moved to the bottom of this
    -- tab made it taller than the window overall, so the tab itself started scrolling.
    -- Dukul, retest: bump back up to 120 -- 90 was too cramped for pasting.
    local PASTE_H = 120
    local pasteFrame = BNB.CreateBackdropFrame("Frame", nil, ct)
    BNB.SetBackdropDark(pasteFrame)
    pasteFrame:SetPoint("TOPLEFT",  ct, "TOPLEFT",  0, y)
    pasteFrame:SetWidth(CONTENT_W)
    pasteFrame:SetHeight(PASTE_H)

    local pasteSF = CreateFrame("ScrollFrame", nil, pasteFrame, "ScrollFrameTemplate")
    pasteSF:SetPoint("TOPLEFT",     pasteFrame, "TOPLEFT",      4,  -4)
    pasteSF:SetPoint("BOTTOMRIGHT", pasteFrame, "BOTTOMRIGHT", -24,  4)
    if pasteSF.ScrollBar then
        pasteSF.ScrollBar:SetAlpha(0)
        pasteSF:HookScript("OnScrollRangeChanged", function(_, _, yRange)
            pasteSF.ScrollBar:SetAlpha((yRange or 0) > 1 and 1.0 or 0)
        end)
    end

    local pasteChild = CreateFrame("Frame", nil, pasteSF)
    pasteChild:SetSize(CONTENT_W - 32, PASTE_H - 8)
    pasteSF:SetScrollChild(pasteChild)

    local pasteEb = CreateFrame("EditBox", nil, pasteChild)
    pasteEb:SetPoint("TOPLEFT",     pasteChild, "TOPLEFT",      0,  0)
    pasteEb:SetPoint("BOTTOMRIGHT", pasteChild, "BOTTOMRIGHT",  0,  0)
    pasteEb:SetFontObject("GameFontNormalSmall")
    pasteEb:SetMultiLine(true)
    pasteEb:SetAutoFocus(false)
    pasteEb:SetMaxLetters(0)   -- unlimited
    BNB.AddPlaceholder(pasteEb, L["BACKUP_PASTE_HINT"], 0.38, 0.38, 0.38)

    -- The scroll frame handles overflow; pasteChild just needs a stable minimum.
    -- EditBox does not expose GetStringHeight -- height expansion is not needed here.

    y = y - PASTE_H - 6

    -- Import button + status label
    local importBtn = BNB.CreateButton(nil, ct, L["BACKUP_BTN_IMPORT"], 120, 26)
    importBtn:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)

    local clearBtn = BNB.CreateButton(nil, ct, L["CANCEL"], 80, 26)
    clearBtn:SetPoint("LEFT", importBtn, "RIGHT", 8, 0)

    local importStatus = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    importStatus:SetPoint("LEFT", clearBtn, "RIGHT", 10, 0)
    importStatus:SetPoint("RIGHT", ct, "RIGHT", 0, 0)
    importStatus:SetJustifyH("LEFT")
    importStatus:SetHeight(26)
    importStatus:SetText("")

    -- Enable/disable Import + Cancel based on whether the paste box has content.
    local function UpdateImportBtns()
        local hasContent = not pasteEb._showingPlaceholder
            and not pasteEb:GetText():match("^%s*$")
        importBtn:SetEnabled(hasContent)
        clearBtn:SetEnabled(hasContent)
    end
    importBtn:SetEnabled(false)
    clearBtn:SetEnabled(false)
    pasteEb:HookScript("OnTextChanged", UpdateImportBtns)

    clearBtn:SetScript("OnClick", function()
        pasteEb:SetRealText("")
        importStatus:SetText("")
    end)

    importBtn:SetScript("OnClick", function()
        local raw = pasteEb._showingPlaceholder and "" or pasteEb:GetText()
        if not raw or raw:match("^%s*$") then
            importStatus:SetTextColor(0.82, 0.55, 0.55)
            importStatus:SetText(L["BACKUP_IMPORT_NONE"])
            return
        end

        local notes = NE.ParseJsonNotes(raw) or NE.ParseMarkdownNotes(raw)
        if not notes then
            importStatus:SetTextColor(0.82, 0.55, 0.55)
            importStatus:SetText(L["BACKUP_IMPORT_ERR"])
            return
        end

        -- Check if any notes are scoped to a different character
        local foreignChar = nil
        for _, note in ipairs(notes) do
            if note.scope and note.scope:find("^char:") then
                local charPart = note.scope:sub(6)
                if charPart ~= (BNB.currentChar or "") then
                    foreignChar = charPart
                    break
                end
            end
        end

        if foreignChar and BNB.currentChar and foreignChar ~= BNB.currentChar then
            -- Store pending data for the popup callbacks
            BNB._pendingImport = { notes = notes, status = importStatus, paste = pasteEb }
            BNB._pendingImportForeign = foreignChar
            StaticPopup_Show("BNB_IMPORT_SCOPE_REMAP", foreignChar, BNB.currentChar)
        else
            -- Same-character or scope-less path — confirm count before importing
            BNB._pendingImport = { notes = notes, status = importStatus, paste = pasteEb }
            StaticPopup_Show("BNB_IMPORT_CONFIRM", #notes)
        end
    end)
    y = y - 40

    -- ── Data Summary section (moved here from General tab, ALL-14) ─────────────
    y = AddRule(ct, y) - 4
    y = AddHeader(ct, y, L["CFG_HDR_DATA_SUMMARY"])

    -- Compute stats from live notes DB
    local noteCount    = 0
    local totalBytes   = 0
    local largestBytes = 0
    local trashCount   = 0
    local trashBytes   = 0
    local ndb = BigNoteBoxNotesDB
    if ndb then
        if ndb.notes then
            for _, note in pairs(ndb.notes) do
                noteCount = noteCount + 1
                local sz  = #(note.title or "") + #(note.body or "")
                totalBytes = totalBytes + sz
                if sz > largestBytes then largestBytes = sz end
            end
        end
        if ndb.trash then
            for _, note in pairs(ndb.trash) do
                trashCount = trashCount + 1
                trashBytes = trashBytes + #(note.title or "") + #(note.body or "")
            end
        end
    end

    local function fmtSize(bytes)
        if bytes >= 1024 * 1024 then
            return string.format(L["CFG_SIZE_MB_FMT"], bytes / (1024 * 1024))
        elseif bytes >= 1024 then
            return string.format(L["CFG_SIZE_KB_FMT"], bytes / 1024)
        else
            return string.format(L["CFG_SIZE_B_FMT"], bytes)
        end
    end

    local avgBytes   = noteCount > 0 and (totalBytes / noteCount) or 0
    local histBytes  = BNB.HistoryTotalSize and BNB.HistoryTotalSize() or 0
    local totalCount = noteCount + trashCount
    local grandTotal = totalBytes + trashBytes

    local GREEN = "|cff66bb6a"
    local GREY  = "|cffaaaaaa"
    local RESET = "|r"
    local SZ    = 14   -- inline icon size

    local ICO_N  = ASSET .. "Icons\\Notes\\INV_Misc_Note_01"  -- note count
    local ICO_S  = "Interface\\Icons\\INV_Misc_Coin_01"       -- notes size
    local ICO_A  = "Interface\\Icons\\Trade_Engineering"      -- average
    local ICO_T  = "Interface\\Icons\\inv_misc_1h_bucket_b_01"-- trash count
    local ICO_TS = "Interface\\Icons\\inv_misc_bag_07"        -- trash size
    local ICO_H  = "Interface\\Icons\\ability_spy"            -- history
    local ICO_L  = "Interface\\Icons\\INV_Scroll_06"          -- largest
    local ICO_TN = "Interface\\Icons\\inv_misc_lockchest02"   -- total notes
    local ICO_GS = "Interface\\Icons\\INV_Misc_Bag_10"        -- grand total size

    -- 3-column grid, 3 rows — compact single-line-height rows with no row gap
    local NCOLS = 3
    local COL   = math.floor(CONTENT_W / NCOLS)
    local STAT_H = 18  -- single row height, no extra gap between rows

    local stats = {
        -- Row 1: live notes
        { icon = ICO_N,  label = L["CFG_STAT_NOTES"],        value = string.format(L["CFG_STAT_COUNT_FMT"], noteCount) },
        { icon = ICO_S,  label = L["CFG_STAT_NOTES_SIZE"],   value = fmtSize(totalBytes) },
        { icon = ICO_A,  label = L["CFG_STAT_AVG_SIZE"],     value = fmtSize(avgBytes) },
        -- Row 2: trash + history
        { icon = ICO_T,  label = L["CFG_STAT_IN_TRASH"],     value = string.format(L["CFG_STAT_COUNT_FMT"], trashCount) },
        { icon = ICO_TS, label = L["CFG_STAT_TRASH_SIZE"],   value = fmtSize(trashBytes) },
        { icon = ICO_H,  label = L["CFG_STAT_HISTORY_SIZE"], value = fmtSize(histBytes) },
        -- Row 3: totals
        { icon = ICO_TN, label = L["CFG_STAT_TOTAL_NOTES"],  value = string.format(L["CFG_STAT_COUNT_FMT"], totalCount) },
        { icon = ICO_GS, label = L["CFG_STAT_TOTAL_SIZE"],   value = fmtSize(grandTotal) },
        { icon = ICO_L,  label = L["CFG_STAT_LARGEST_NOTE"], value = fmtSize(largestBytes) },
    }

    -- 3-column grid, 3 rows — render each stat at the correct col/row offset
    for i, s in ipairs(stats) do
        local col  = (i - 1) % NCOLS
        local row  = math.floor((i - 1) / NCOLS)
        local xOff = col * COL
        local yOff = y - row * STAT_H

        local lbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", ct, "TOPLEFT", xOff, yOff)
        lbl:SetWidth(COL - 4)
        lbl:SetJustifyH("LEFT")
        lbl:SetText(
            "|T" .. s.icon .. ":" .. SZ .. "|t " ..
            GREY .. s.label .. ": " .. RESET ..
            GREEN .. s.value .. RESET
        )
    end

    local numRows = math.ceil(#stats / NCOLS)
    y = y - numRows * STAT_H

    sf:FinaliseHeight(math.abs(y) + 12)
end

-- ── Fallback export window (clipboard unavailable or oversized payload) ───────
-- A simple resizable frame with a scrollable read-only editbox.
-- User selects all with Ctrl+A and copies manually.

local _exportWin = nil
local SK_EXP_TITLE_H = 28

function BNB.OpenExportWindow(text, warningText, htmlNoteID)
    local NE = BNB.NoteExport
    if not _exportWin then
        local f
        if BigNoteBoxDB and BigNoteBoxDB.skinMode then
            f = BNB.CreateSkinFrame(UIParent, false, "BigNoteBoxExportFrame", false)
            _G["BigNoteBoxExportFrame"] = f
            f:SetSize(520, 440)
            f:SetPoint("CENTER")
            f:SetFrameStrata("DIALOG")
            f:SetToplevel(true); f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true)
            f:RegisterForDrag("LeftButton")
            f:SetScript("OnDragStart", function(self) self:StartMoving() end)
            f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)

            local titleBar = BNB.CreateSkinStrip(f, true, false)
            titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
            titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
            titleBar:SetHeight(SK_EXP_TITLE_H)
            titleBar:EnableMouse(true)
            titleBar:RegisterForDrag("LeftButton")
            titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
            titleBar:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

            local titleLbl = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            titleLbl:SetPoint("CENTER", titleBar, "CENTER", -12, 0)
            titleLbl:SetTextColor(1, 0.82, 0)
            titleLbl:SetText(L["CFG_EXPORT_TITLE"])

            local closeBtn = BNB.CreateSkinCloseButton(titleBar, function() f:Hide() end)
            closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -3, 0)

            local copyBtn = BNB.CreateButton(nil, f, L["HISTORY_EXPORT_COPY"], 140, 24)
            copyBtn:SetPoint("TOP", f, "TOP", 0, -(SK_EXP_TITLE_H + 8))
            copyBtn:SetScript("OnClick", function() BNB.ShowClipboardHint(f._eb:GetText()) end)
            f._copyBtn = copyBtn

            local sf = CreateFrame("ScrollFrame", nil, f, "ScrollFrameTemplate")
            sf:SetPoint("TOPLEFT",     f, "TOPLEFT",     16, -(SK_EXP_TITLE_H + 8 + 24 + 6))
            sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -24, 16)
            if sf.ScrollBar then
                sf.ScrollBar:SetAlpha(0)
                sf:HookScript("OnScrollRangeChanged", function(_, _, yRange)
                    sf.ScrollBar:SetAlpha((yRange or 0) > 1 and 1.0 or 0)
                end)
            end

            local child = CreateFrame("Frame", nil, sf)
            child:SetSize(460, 1)
            sf:SetScrollChild(child)

            local eb = CreateFrame("EditBox", nil, child)
            eb:SetPoint("TOPLEFT",     child, "TOPLEFT",     0, 0)
            eb:SetPoint("BOTTOMRIGHT", child, "BOTTOMRIGHT", 0, 0)
            eb:SetFontObject("GameFontNormalSmall")
            eb:SetMultiLine(true); eb:SetAutoFocus(true)
            eb:SetMaxLetters(0)
            eb:SetScript("OnEscapePressed", function() f:Hide() end)

            f._eb = eb; f._child = child; f._sf = sf

            f:SetScript("OnShow", function()
                if BNB.ApplyMainWindowSkin then BNB.ApplyMainWindowSkin() end
            end)
            f:Hide()
        else
            f = CreateFrame("Frame", "BigNoteBoxExportFrame", UIParent, "ButtonFrameTemplate")
            f:SetSize(520, 440)
            f:SetPoint("CENTER")
            f:SetFrameStrata("DIALOG")
            f:SetToplevel(true); f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true)
            f:RegisterForDrag("LeftButton")
            f:SetScript("OnDragStart", function(self) self:StartMoving() end)
            f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
            ButtonFrameTemplate_HidePortrait(f)
            ButtonFrameTemplate_HideButtonBar(f)
            if f.Inset then f.Inset:Hide() end
            BNB.SeatChrome(f)   -- FOR-05: Forever border offset (UI/Chrome.lua)
            f._forGlow = BNB.AddForeverGlow(f, f.Bg)   -- Forever: glow over the wood grain
            f:SetTitle(L["CFG_EXPORT_TITLE"])
            if f.CloseButton then
                f.CloseButton:SetScript("OnClick", function() f:Hide() end)
            end

            local copyBtn = BNB.CreateButton(nil, f, L["HISTORY_EXPORT_COPY"], 140, 24)
            copyBtn:SetPoint("TOP", f, "TOP", 0, -58)
            copyBtn:SetScript("OnClick", function()
                BNB.ShowClipboardHint(f._eb:GetText())
            end)
            f._copyBtn = copyBtn

            local sf = CreateFrame("ScrollFrame", nil, f, "ScrollFrameTemplate")
            sf:SetPoint("TOPLEFT",     f, "TOPLEFT",    16, -90)
            sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT",-24,  16)
            if sf.ScrollBar then
                sf.ScrollBar:SetAlpha(0)
                sf:HookScript("OnScrollRangeChanged", function(_, _, yRange)
                    sf.ScrollBar:SetAlpha((yRange or 0) > 1 and 1.0 or 0)
                end)
            end

            local child = CreateFrame("Frame", nil, sf)
            child:SetSize(460, 1)
            sf:SetScrollChild(child)

            local eb = CreateFrame("EditBox", nil, child)
            eb:SetPoint("TOPLEFT",     child, "TOPLEFT",      0,  0)
            eb:SetPoint("BOTTOMRIGHT", child, "BOTTOMRIGHT",  0,  0)
            eb:SetFontObject("GameFontNormalSmall")
            eb:SetMultiLine(true); eb:SetAutoFocus(true)
            eb:SetMaxLetters(0)
            eb:SetScript("OnEscapePressed", function() f:Hide() end)

            f._eb    = eb
            f._child = child
            f._sf    = sf
            f:Hide()
        end
        tinsert(UISpecialFrames, "BigNoteBoxExportFrame")
        _exportWin = f
    end

    -- Lazy-create the warning label (anchored above the copy button)
    if not _exportWin._warnLbl then
        local wl = _exportWin:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        wl:SetPoint("BOTTOMLEFT",  _exportWin._copyBtn, "TOPLEFT",  0, 4)
        wl:SetPoint("BOTTOMRIGHT", _exportWin._copyBtn, "TOPRIGHT", 0, 4)
        wl:SetJustifyH("CENTER")
        wl:SetWordWrap(true)
        wl:SetTextColor(1, 0.75, 0.25)
        wl:Hide()
        _exportWin._warnLbl = wl
    end

    -- Lazy-create the HTML mode dropdown (anchored to the right of the copy button)
    if not _exportWin._htmlDD then
        local HTML_MODES = {
            { key = "noteonly",  label = L["CFG_EXPORT_HTML_NOTEONLY"] },
            { key = "plain",    label = L["CFG_EXPORT_HTML_PLAIN"] },
            { key = "stylized", label = L["CFG_EXPORT_HTML_STYLIZED"] },
        }
        local dd = CreateFrame("DropdownButton", nil, _exportWin, "WowStyle1DropdownTemplate")
        dd:SetPoint("LEFT", _exportWin._copyBtn, "RIGHT", 8, 0)
        dd:SetWidth(150)
        dd:SetHeight(24)
        local function SetupHtmlDD()
            dd:SetupMenu(function(_, root)
                for _, opt in ipairs(HTML_MODES) do
                    root:CreateRadio(opt.label,
                        function() return _htmlExportMode == opt.key end,
                        function()
                            _htmlExportMode = opt.key
                            dd:GenerateMenu()
                            -- Regenerate with the new mode
                            if _exportWin._htmlNoteID then
                                local note = BNB.GetNote(_exportWin._htmlNoteID)
                                if note then
                                    local html, hasImages = NE.HtmlEncodeNote(note, _htmlExportMode)
                                    _exportWin._eb:SetText(html)
                                    if hasImages then
                                        _exportWin._warnLbl:SetText(L["CFG_EXPORT_IMG_WARN"])
                                        _exportWin._warnLbl:Show()
                                    else
                                        _exportWin._warnLbl:SetText("")
                                        _exportWin._warnLbl:Hide()
                                    end
                                    C_Timer.After(0.05, function()
                                        if _exportWin then
                                            _exportWin._child:SetHeight(math.max(_exportWin._eb:GetHeight() + 20, 400))
                                        end
                                    end)
                                end
                            end
                        end)
                end
            end)
        end
        SetupHtmlDD()
        dd:Hide()
        _exportWin._htmlDD = dd
        _exportWin._setupHtmlDD = SetupHtmlDD
    end

    -- Show or hide the HTML mode dropdown
    _exportWin._htmlNoteID = htmlNoteID
    if htmlNoteID then
        if _exportWin._setupHtmlDD then _exportWin._setupHtmlDD() end
        _exportWin._htmlDD:Show()
    else
        _exportWin._htmlDD:Hide()
    end

    -- Show or hide the warning
    if warningText and warningText ~= "" then
        _exportWin._warnLbl:SetText(warningText)
        _exportWin._warnLbl:Show()
    else
        _exportWin._warnLbl:SetText("")
        _exportWin._warnLbl:Hide()
    end

    _exportWin._eb:SetText(text or "")
    -- Size child to content -- use a generous fixed height; scroll handles the rest
    C_Timer.After(0.05, function()
        if not _exportWin then return end
        _exportWin._child:SetHeight(math.max(_exportWin._eb:GetHeight() + 20, 400))
    end)
    _exportWin:Show()
    _exportWin._eb:SetFocus()
    _exportWin._eb:HighlightText()
end

-- ── Per-note export helpers (called from the note context menu) ───────────────
-- C_System.SetClipboard is restricted on retail — always use the export window
-- with ShowClipboardHint for the Ctrl+C copy flow.

function BNB.ExportNoteJSON(noteID)
    local NE = BNB.NoteExport
    local note = BNB.GetNote(noteID)
    if not note then return end
    BNB.OpenExportWindow(NE.JsonEncodeNote(note))
end

function BNB.ExportNoteMD(noteID)
    local NE = BNB.NoteExport
    local note = BNB.GetNote(noteID)
    if not note then return end
    BNB.OpenExportWindow(NE.MdEncodeNote(note))
end

function BNB.ExportNoteHTML(noteID)
    local NE = BNB.NoteExport
    local note = BNB.GetNote(noteID)
    if not note then return end
    _htmlExportMode = _htmlExportMode or "plain"
    local html, hasImages = NE.HtmlEncodeNote(note, _htmlExportMode)
    local warn = hasImages
        and L["CFG_EXPORT_IMG_WARN"]
        or nil
    BNB.OpenExportWindow(html, warn, noteID)
end

K.BUILDERS.backup = BuildBackupTab

-- BigNoteBox UI/Config/Backup.lua - Settings Backup tab (Export / Import),
-- the fallback export window and the per-note export entry points.
-- The codec itself is Features/NoteExport.lua.
-- Split out of ConfigWindow.lua (ALL-65.10).

local BNB = BigNoteBox
local L   = BNB.L

local K = BNB._ConfigKit
local CONTENT_W, ROW_H, ROW_GAP = K.CONTENT_W, K.ROW_H, K.ROW_GAP
local AddRule, AddHeader = K.AddRule, K.AddHeader

-- Export window HTML mode: "noteonly", "plain", "stylized". Kept for the
-- session, so the per-note HTML export reuses the last choice.
local _htmlExportMode = "plain"

-- ── Rescue (ALL-466 stage 3): the way to the Rescue list on the Note History
-- page. At the top, and shown only while there is something to rescue
-- (Dukul, 2026-10-17, ALL-495: the section gave the page a scrollbar).
-- Built in its own frame; onLayout(shown, height) moves the rest of the page.
local function BuildRescue(sf, page, onLayout)
    local box = CreateFrame("Frame", nil, page)
    box:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    box:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)
    local y = -8
    y = AddHeader(box, y, L["RESCUE_HDR"])
    local desc = box:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    desc:SetPoint("TOPLEFT", box, "TOPLEFT", 0, y)
    desc:SetWidth(CONTENT_W); desc:SetJustifyH("LEFT"); desc:SetWordWrap(true)
    desc:SetTextColor(0.60, 0.60, 0.60)
    desc:SetText(L["RESCUE_BACKUP_DESC"])
    local h = desc:GetStringHeight() + 4
    desc:SetHeight(h); y = y - h - 6

    local btn = BNB.CreateButton(nil, box, L["RESCUE_OPEN_BTN"], 180, 26)
    btn:SetPoint("TOPLEFT", box, "TOPLEFT", 0, y)
    btn:SetScript("OnClick", function() BNB.OpenRescuePage() end)
    local status = box:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    status:SetPoint("LEFT", btn, "RIGHT", 10, 0)
    status:SetPoint("RIGHT", box, "TOPRIGHT", 0, y - 13)
    status:SetJustifyH("LEFT"); status:SetWordWrap(false)
    status:SetTextColor(0.55, 0.55, 0.55)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["RESCUE_OPEN_BTN"], 1, 1, 1)
        GameTooltip:AddLine(L["RESCUE_OPEN_TIP"], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    y = y - 26 - 10
    y = AddRule(box, y) - 4
    local boxH = math.abs(y)
    box:SetHeight(boxH)

    local function Sync()
        local n = BNB.HistoryAddonLoaded() and BNB.HistoryRescueCount and BNB.HistoryRescueCount() or 0
        box:SetShown(n > 0)
        if n > 0 then status:SetText(BNB.HistoryRescueCountText(n)) end
        onLayout(n > 0, boxH)
    end
    sf:HookScript("OnShow", Sync)
    for _, msg in ipairs({ "NoteCreated", "NoteDeleted", "NoteRestored", "TrashChanged", "HistoryRescueChanged" }) do
        BNB.RegisterMessage("BackupRescue", msg, function()
            if sf:IsVisible() then BNB.Debounce("BackupRescue", 0, Sync) end
        end)
    end
    return Sync
end

local function BuildBackupTab(sf, page)
    local NE = BNB.NoteExport
    local y = -8

    -- Everything under the Rescue section lives in ct, which sits right
    -- under it while it shows and at the top otherwise (ALL-495)
    local ct = CreateFrame("Frame", nil, page)
    ct:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)
    ct:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    local bodyH
    local rescueShown, rescueH = false, 0
    local function Layout()
        local top = rescueShown and -rescueH or 0
        ct:ClearAllPoints()
        ct:SetPoint("TOPLEFT", page, "TOPLEFT", 0, top)
        ct:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, top)
        if bodyH then
            ct:SetHeight(bodyH)
            sf:FinaliseHeight(bodyH + (rescueShown and rescueH or 0))
        end
    end
    local SyncRescue = BuildRescue(sf, page, function(shown, h)
        rescueShown, rescueH = shown, h
        Layout()
    end)

    -- ── Back up (ALL-507) ───────────────────────────────────────────────────
    -- Three backups, each straight to the copy popup (C_System.SetClipboard
    -- is nil on Retail and Forever, ALL-21): Full = everything as JSON,
    -- Settings = every profile and no notes, Selective = a sub-page with the
    -- format and the parts. Markdown is notes only, so it lives on that page
    -- (Dukul, 2026-10-18).
    y = AddHeader(ct, y, L["BACKUP_EXPORT_HEADER"])

    local desc = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    desc:SetPoint("TOPLEFT",  ct, "TOPLEFT",  0, y)
    desc:SetWidth(CONTENT_W); desc:SetJustifyH("LEFT")
    desc:SetWordWrap(true); desc:SetHeight(32)
    desc:SetTextColor(0.78, 0.78, 0.78)
    desc:SetText(L["BACKUP_EXPORT_DESC"])
    y = y - 38

    local selPage = K.NewSubPage(L["BACKUP_SEL_TITLE"], K.BuildSelectiveBackupPage, "selectivebackup")

    local BTN_GAP = 8
    local BTN_W = math.floor((CONTENT_W - 2 * BTN_GAP) / 3)
    local function TipBtn(btn, title, tip)
        btn:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(title, 1, 1, 1)
            GameTooltip:AddLine(tip, 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        btn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end
    local fullBtn = BNB.CreateButton(nil, ct, L["BACKUP_BTN_FULL"], BTN_W, 26)
    fullBtn:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    TipBtn(fullBtn, L["BACKUP_BTN_FULL"], L["BACKUP_BTN_FULL_TIP"])
    local setBtn = BNB.CreateButton(nil, ct, L["BACKUP_BTN_SETTINGS"], BTN_W, 26)
    setBtn:SetPoint("LEFT", fullBtn, "RIGHT", BTN_GAP, 0)
    TipBtn(setBtn, L["BACKUP_BTN_SETTINGS"], L["BACKUP_BTN_SETTINGS_TIP"])
    local selBtn = BNB.CreateButton(nil, ct, L["BACKUP_BTN_SELECTIVE"], BTN_W, 26)
    selBtn:SetPoint("LEFT", setBtn, "RIGHT", BTN_GAP, 0)
    TipBtn(selBtn, L["BACKUP_BTN_SELECTIVE"], L["BACKUP_BTN_SELECTIVE_TIP"])
    y = y - 26 - 4

    local exportStatus = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    exportStatus:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    exportStatus:SetWidth(CONTENT_W)
    exportStatus:SetJustifyH("LEFT"); exportStatus:SetWordWrap(false)
    exportStatus:SetHeight(16)
    exportStatus:SetTextColor(0.78, 0.78, 0.78)
    exportStatus:SetText("")
    sf:HookScript("OnShow", function() exportStatus:SetText("") end)
    y = y - 16 - 8

    local function CopyBackup(btn, opts)
        local text = NE.BuildBackup(opts)
        if not text then return end
        BNB.ShowClipboardHint(text, btn)
        exportStatus:SetText(L["BACKUP_BTN_COPY_FALLBACK"])
    end
    fullBtn:SetScript("OnClick", function(self)
        CopyBackup(self, { templates = true, tokens = true, tagColors = true, profiles = true })
    end)
    setBtn:SetScript("OnClick", function(self)
        CopyBackup(self, { ids = {}, profiles = true })
    end)
    selBtn:SetScript("OnClick", function() selPage.Open() end)

    y = AddRule(ct, y) - 4

    -- ── Import section ────────────────────────────────────────────────────────
    y = AddHeader(ct, y, L["BACKUP_IMPORT_HEADER"])

    local desc2 = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
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

    local pasteSF = BNB.CreateScrollFrame(nil, pasteFrame)
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
    pasteEb:SetFontObject("BNBFontNormalSmall")
    pasteEb:SetMultiLine(true)
    pasteEb:SetAutoFocus(false)
    pasteEb:SetMaxLetters(0)   -- unlimited
    BNB.AddPlaceholder(pasteEb, L["BACKUP_PASTE_HINT"], 0.38, 0.38, 0.38)

    -- The scroll frame handles overflow; pasteChild just needs a stable minimum.
    -- EditBox does not expose GetStringHeight -- height expansion is not needed here.

    y = y - PASTE_H - 6

    -- What the paste holds, before Import (Dukul, 2026-10-18, ALL-507). Read
    -- once the text has rested a moment: a big backup is parsed only once.
    local pastePreview = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    pastePreview:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    pastePreview:SetWidth(CONTENT_W)
    pastePreview:SetJustifyH("LEFT"); pastePreview:SetWordWrap(false)
    pastePreview:SetHeight(16)
    pastePreview:SetText("")
    local function Describe(raw)
        local code = raw:match("^%s*(.-)%s*$")
        if code == "" then return "" end
        local function Bad(text) return "|cffd18c8c" .. text .. "|r" end
        local function Good(text) return "|cff8cd18c" .. text .. "|r" end
        if code:find("^BNBP%d:") then
            local pl = BNB.Profiles and BNB.Profiles.Decode(code)
            if not pl then return Bad(L["PROFILE_IMPORT_BAD"]) end
            return Good(string.format(L["BACKUP_PREVIEW_PROFILE"], BNB.Profiles.DisplayName(pl.name or "?")))
        end
        local tpl = BNB.Templates.PeekCode and BNB.Templates.PeekCode(code)
        if tpl == false then return Bad(L["TPL_IMPORT_ERR"]) end
        if tpl then return Good(string.format(L["BACKUP_PREVIEW_TEMPLATE"], tpl.name or "?")) end
        if code:find("^BNB%d:") then
            local data, err
            if BNB.ShareDecode then data, err = BNB.ShareDecode(code) end
            if not data then return Bad(err or L["SHARE_ERR_INVALID"]) end
            local title = (data.title and data.title ~= "") and data.title or "-"
            return Good(string.format(L["BACKUP_PREVIEW_SHARE"], title))
        end
        local list, err = NE.ParseJsonNotes(raw, true)
        local kind = "BACKUP_PREVIEW_JSON"
        if not list and not err then
            list = NE.ParseMarkdownNotes(raw, true)
            kind = "BACKUP_PREVIEW_MD"
        end
        if not list then return Bad(err or L["BACKUP_IMPORT_ERR"]) end
        local parts = { string.format(L["BACKUP_PREVIEW_NOTES"], #list) }
        local function Add(t, key)
            local n = 0
            for _ in pairs(type(t) == "table" and t or {}) do n = n + 1 end
            if n > 0 then parts[#parts + 1] = string.format(L[key], n) end
        end
        Add(list.templates, "BACKUP_PREVIEW_TEMPLATES")
        Add(list.tokens, "BACKUP_PREVIEW_TOKENS")
        Add(list.tagColors, "BACKUP_PREVIEW_TAGCOLORS")
        Add(list.profiles, "BACKUP_PREVIEW_PROFILES")
        return Good(L[kind] .. " " .. table.concat(parts, ", "))
    end
    local function UpdatePreview()
        local raw = pasteEb._showingPlaceholder and "" or pasteEb:GetText()
        local ok, text = pcall(Describe, raw or "")
        pastePreview:SetText(ok and text or "")
    end
    pasteEb:HookScript("OnTextChanged", function()
        BNB.Debounce("backupPastePreview", 0.3, UpdatePreview)
    end)
    y = y - 16 - 4

    -- Import button + status label
    local importBtn = BNB.CreateButton(nil, ct, L["BACKUP_BTN_IMPORT"], 120, 26)
    importBtn:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)

    local clearBtn = BNB.CreateButton(nil, ct, L["CANCEL"], 80, 26)
    clearBtn:SetPoint("LEFT", importBtn, "RIGHT", 8, 0)

    local importStatus = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
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

    -- The import picker (ALL-507): built with the tab, opened by Import
    local pickPage = K.NewSubPage(L["BACKUP_PICK_TITLE"], K.BuildImportPickerPage, "importpicker")

    -- notes: a parsed backup (maybe filtered by the picker). confirmed: the
    -- picker was the confirm step, so no "Import N notes?" popup
    local function StartImport(notes, confirmed)
        local function Say(text, ok)
            if ok then importStatus:SetTextColor(0.55, 0.82, 0.55)
            else importStatus:SetTextColor(0.82, 0.55, 0.55) end
            importStatus:SetText(text)
        end
        -- Only templates / tokens / tag colours / profiles: nothing to back up first
        if #notes == 0 then
            BNB._DoImport(notes, false)
            Say(L["BACKUP_IMPORT_PARTS_OK"], true)
            pasteEb:SetRealText("")
            return
        end
        -- Check if any notes are scoped to a different character
        local foreignChar = BNB.ForeignScopeChar(notes)
        BNB.OfferBackupFirst(function()   -- ALL-186
            -- Stored for the popup callbacks
            BNB._pendingImport = { notes = notes, status = importStatus, paste = pasteEb }
            if foreignChar and BNB.currentChar then
                StaticPopup_Show("BNB_IMPORT_SCOPE_REMAP", foreignChar, BNB.currentChar)
            elseif confirmed then
                BNB._pendingImport = nil
                local n = BNB._DoImport(notes, false) or 0
                if n > 0 then Say(string.format(L["BACKUP_IMPORT_OK"], n), true)
                else Say(L["BACKUP_IMPORT_NONE"], false) end
                pasteEb:SetRealText("")
            else
                -- Same-character or scope-less path: confirm count before importing
                StaticPopup_Show("BNB_IMPORT_CONFIRM", #notes)
            end
        end)
    end

    importBtn:SetScript("OnClick", function()
        local raw = pasteEb._showingPlaceholder and "" or pasteEb:GetText()
        if not raw or raw:match("^%s*$") then
            importStatus:SetTextColor(0.82, 0.55, 0.55)
            importStatus:SetText(L["BACKUP_IMPORT_NONE"])
            return
        end

        -- A share code (BNB2: / BNB1:) goes to the share preview, as on the
        -- Welcome panel (ALL-67): it is a note, not a broken backup
        local code = raw:match("^%s*(.-)%s*$")
        -- A template code adds a template (ALL-68 S3)
        local tplDone, tplMsg, tplOk = BNB.Templates.TryImport(code)
        if tplDone then
            if tplOk then importStatus:SetTextColor(0.55, 0.82, 0.55)
            else importStatus:SetTextColor(0.82, 0.55, 0.55) end
            importStatus:SetText(tplMsg)
            return
        end
        -- A profile code (BNBP1:) gets the Profiles row's name prompt (ALL-507)
        if code:find("^BNBP%d:") then
            if BNB.ImportProfileCode(code) then
                importStatus:SetText("")
                pasteEb:SetRealText("")
            else
                importStatus:SetTextColor(0.82, 0.55, 0.55)
                importStatus:SetText(L["PROFILE_IMPORT_BAD"])
            end
            return
        end
        if code:find("^BNB%d:") then
            local data, err
            if BNB.ShareDecode then data, err = BNB.ShareDecode(code) end
            if not data then
                importStatus:SetTextColor(0.82, 0.55, 0.55)
                importStatus:SetText(err or L["SHARE_ERR_INVALID"])
                return
            end
            importStatus:SetText("")
            BNB.OpenSharePreview(data)
            return
        end

        -- A damaged JSON file says where it breaks (ALL-294), never falls
        -- through to Markdown
        local notes, jsonErr = NE.ParseJsonNotes(raw)
        if not notes and not jsonErr then notes = NE.ParseMarkdownNotes(raw) end
        if not notes then
            importStatus:SetTextColor(0.82, 0.55, 0.55)
            importStatus:SetText(jsonErr or L["BACKUP_IMPORT_ERR"])
            return
        end
        importStatus:SetText("")

        -- More than notes (a full or settings backup, ALL-507): the picker
        -- shows what it holds and is the confirm step. Notes only: as before.
        local extra = (notes.templates and #notes.templates > 0) or (notes.tokens and #notes.tokens > 0)
            or (notes.tagColors and next(notes.tagColors) ~= nil) or (notes.profiles and #notes.profiles > 0)
        if extra then
            pickPage.SetData(notes, function(picked)
                BNB.ConfigSubPageBack()
                StartImport(picked, true)
            end)
            pickPage.Open()
        else
            StartImport(notes, false)
        end
    end)
    y = y - 40

    -- Migrate moved here from Advanced (ALL-84): it is an import.
    local db = BigNoteBoxDB
    -- ── Migrate section (only shown if any supported addon is installed) ─────────
    if BNB.Migration and BNB.Migration.HasAny() then
        AddRule(ct, y); y = y - 18
        y = AddHeader(ct, y, L["CFG_HDR_MIGRATE"])

        local migDesc = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
        migDesc:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        migDesc:SetWidth(CONTENT_W); migDesc:SetJustifyH("LEFT")
        migDesc:SetWordWrap(true)
        migDesc:SetTextColor(0.60, 0.60, 0.60)
        migDesc:SetText(L["CFG_IMPORT_DESC"])
        y = y - 36

        -- Use the Migration module's own key/name tables so this list stays
        -- in sync automatically whenever new addons are added to MigrateNotes.lua.
        local M = BNB.Migration
        for _, k in ipairs(M.ADDON_KEYS) do
            if M.IsAddonAvailable(k) then
                local displayName = M.ADDON_NAMES[k] or k
                local isDone = db.migrationDone and db.migrationDone[k]

                -- Row: label + status badge + button
                local rowLbl = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
                rowLbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
                rowLbl:SetText(displayName)

                local statusLbl = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
                statusLbl:SetPoint("LEFT", rowLbl, "RIGHT", 8, 0)
                if isDone then
                    statusLbl:SetText("|cff66bb6a" .. L["CFG_DONE_BADGE"] .. "|r")
                else
                    statusLbl:SetText("|cff888888" .. L["CFG_NOT_YET_BADGE"] .. "|r")
                end

                local migrateRowBtn = BNB.CreateButton(nil, ct, isDone and L["CFG_MIGRATE_AGAIN_BTN"] or L["CFG_MIGRATE_BTN"], 110, 22)
                migrateRowBtn:SetPoint("TOPRIGHT", ct, "TOPRIGHT", 0, y)
                migrateRowBtn:SetScript("OnClick", function()
                    if M.ShowAddonPopup then
                        M.ShowAddonPopup(k)
                    end
                end)

                y = y - (ROW_H + ROW_GAP)
            end
        end
    end

    -- ── Data Summary section (moved here from General tab, ALL-14) ─────────────
    y = AddRule(ct, y) - 4
    y = AddHeader(ct, y, L["CFG_HDR_DATA_SUMMARY"])

    -- Counted on every refresh, never once at build: the page is built once and
    -- an import or delete must show at once (ALL-293)
    local function ComputeStats()
        local noteCount    = 0
        local totalBytes   = 0
        local largestBytes = 0
        local trashCount   = 0
        local trashBytes   = 0
        local ndb = BNB.NotesDB()
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
        return {
            string.format(L["CFG_STAT_COUNT_FMT"], noteCount), fmtSize(totalBytes), fmtSize(avgBytes),
            string.format(L["CFG_STAT_COUNT_FMT"], trashCount), fmtSize(trashBytes), fmtSize(histBytes),
            string.format(L["CFG_STAT_COUNT_FMT"], totalCount), fmtSize(grandTotal), fmtSize(largestBytes),
        }
    end

    local GREEN = "|cff66bb6a"
    local GREY  = "|cffaaaaaa"
    local RESET = "|r"
    local SZ    = 14   -- inline icon size

    local ICO_N  = "Interface\\Icons\\INV_Misc_Note_01"       -- note count
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
        { icon = ICO_N,  label = L["CFG_STAT_NOTES"] },
        { icon = ICO_S,  label = L["CFG_STAT_NOTES_SIZE"] },
        { icon = ICO_A,  label = L["CFG_STAT_AVG_SIZE"] },
        -- Row 2: trash + history
        { icon = ICO_T,  label = L["CFG_STAT_IN_TRASH"] },
        { icon = ICO_TS, label = L["CFG_STAT_TRASH_SIZE"] },
        { icon = ICO_H,  label = L["CFG_STAT_HISTORY_SIZE"] },
        -- Row 3: totals
        { icon = ICO_TN, label = L["CFG_STAT_TOTAL_NOTES"] },
        { icon = ICO_GS, label = L["CFG_STAT_TOTAL_SIZE"] },
        { icon = ICO_L,  label = L["CFG_STAT_LARGEST_NOTE"] },
    }

    -- 3-column grid, 3 rows — render each stat at the correct col/row offset
    for i, s in ipairs(stats) do
        local col  = (i - 1) % NCOLS
        local row  = math.floor((i - 1) / NCOLS)
        local xOff = col * COL
        local yOff = y - row * STAT_H

        local lbl = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
        lbl:SetPoint("TOPLEFT", ct, "TOPLEFT", xOff, yOff)
        lbl:SetWidth(COL - 4)
        lbl:SetJustifyH("LEFT")
        s.lbl = lbl
    end

    local function RefreshStats()
        local values = ComputeStats()
        for i, s in ipairs(stats) do
            s.lbl:SetText(
                "|T" .. s.icon .. ":" .. SZ .. "|t " ..
                GREY .. s.label .. ": " .. RESET ..
                GREEN .. values[i] .. RESET
            )
        end
    end
    RefreshStats()
    sf:HookScript("OnShow", RefreshStats)
    -- Follows note changes while the page is shown; one recount per frame
    local function StatsFollow()
        if sf:IsVisible() then BNB.Debounce("cfgDataSummary", 0, RefreshStats) end
    end
    for _, msg in ipairs({ "NoteCreated", "NoteChanged", "NoteDeleted", "NoteRestored", "TrashChanged" }) do
        BNB.RegisterMessage("ConfigDataSummary", msg, StatsFollow)
    end

    local numRows = math.ceil(#stats / NCOLS)
    y = y - numRows * STAT_H

    bodyH = math.abs(y) + 12
    SyncRescue()   -- places ct and reports the page height
end

-- ── Fallback export window (clipboard unavailable or oversized payload) ───────
-- A simple resizable frame with a scrollable read-only editbox.
-- User selects all with Ctrl+A and copies manually.

local _exportWin = nil

-- Before an import or a migration adds notes (ALL-186): while there are notes
-- already, offer a JSON backup of them first. "Back up first" opens the export
-- window with the notes as they are now, then carries on (the text in the
-- window is taken before anything changes); "Skip" carries on; Esc stops.
function BNB.OfferBackupFirst(proceed)
    local ndb, n = BNB.NotesDB(), 0
    for _ in pairs(ndb and ndb.notes or {}) do n = n + 1 end
    if n == 0 then proceed(); return end
    if not StaticPopupDialogs["BNB_BACKUP_FIRST"] then
        StaticPopupDialogs["BNB_BACKUP_FIRST"] = {
            text = L["BACKUP_FIRST_TEXT"],
            button1 = L["BACKUP_FIRST_BTN"],
            button2 = L["BACKUP_FIRST_SKIP"],
            OnAccept = function(_, data)
                local NE = BNB.NoteExport
                local text = NE and NE.SerializeNotes(NE.FMT_JSON)
                if text then BNB.OpenExportWindow(text) end
                if data then data() end
            end,
            -- reason "clicked" = Skip; Esc does not call OnCancel (noCancelOnEscape)
            OnCancel = function(_, data, reason)
                if reason == "clicked" and data then data() end
            end,
            noCancelOnEscape = true,
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
    end
    StaticPopupDialogs["BNB_BACKUP_FIRST"].text = (n == 1) and L["BACKUP_FIRST_TEXT_ONE"] or L["BACKUP_FIRST_TEXT"]
    StaticPopup_Show("BNB_BACKUP_FIRST", n, nil, proceed)
end

function BNB.OpenExportWindow(text, warningText, htmlNoteID)
    local NE = BNB.NoteExport
    if not _exportWin then
        -- Shared chrome (CMP-02); one body for both modes, the old offsets kept
        local f = BNB.CreateToolWindow({
            name = "BigNoteBoxExportFrame", w = 520, h = 440, title = L["CFG_EXPORT_TITLE"],
            toplevel = true, escClose = true,
        })
        f:SetPoint("CENTER")
        local copyY = f._isSkin and (BNB.TOOL_SKIN_TITLE_H + 8) or 58

        local copyBtn = BNB.CreateButton(nil, f, L["HISTORY_EXPORT_COPY"], 140, 24)
        copyBtn:SetPoint("TOP", f, "TOP", 0, -copyY)
        -- Selects the text already in this box for Ctrl+C, rather than
        -- copying it into the copy popup's hidden box a second time (ALL-507)
        copyBtn:SetScript("OnClick", function() f._eb:SetFocus(); f._eb:HighlightText() end)
        f._copyBtn = copyBtn

        local sf = BNB.CreateScrollFrame(nil, f)
        sf:SetPoint("TOPLEFT",     f, "TOPLEFT",     16, -(f._isSkin and (copyY + 24 + 6) or 90))
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
        eb:SetFontObject("BNBFontNormalSmall")
        eb:SetMultiLine(true); eb:SetAutoFocus(true)
        eb:SetMaxLetters(0)
        eb:SetScript("OnEscapePressed", function() f:Hide() end)

        f._eb = eb; f._child = child; f._sf = sf
        _exportWin = f
    end

    -- Lazy-create the warning label (anchored above the copy button)
    if not _exportWin._warnLbl then
        local wl = _exportWin:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
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
        local dd = BNB.SkinDropdown(CreateFrame("DropdownButton", nil, _exportWin, "WowStyle1DropdownTemplate"))
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
    -- Wrapped like a backup, so it imports in Settings > Backup
    BNB.OpenExportWindow(NE.JsonEncodeNotes({ note }))
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

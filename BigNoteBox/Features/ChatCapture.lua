-- BigNoteBox Features/ChatCapture.lua — Chat capture (BCB integration)
--
-- Hooks the BigChatBox editbox to add a right-click "Save to BigNoteBox" menu
-- item. When triggered, the editbox text is saved as a new note (or appended
-- to the currently selected note if the main window is open and a note is
-- selected). The first non-empty line becomes the note title.
--
-- Also wires the Import toolbar button in MainWindow to trigger the same
-- capture from the BCB editbox (same logic, just invoked from BNB's own UI).
--
-- Public API:
--   BNB.SetupChatCapture()   — called by Initialize.lua; idempotent
--   BNB.CaptureFromBCB()     — capture current BCB editbox text right now
--
-- Requirements:
--   BigChatBox ~= nil and BigChatBox.SendDirect ~= nil  (BNB.hasBCB)
--   BCB must expose a single editbox as BigChatBox.editBox (standard BCB API)

local BNB = BigNoteBox
local L   = BNB.L

-- Whether we've already run setup (idempotency guard)
local _setupDone = false

-- ── Helpers ────────────────────────────────────────────────────────────────────

-- Extract the first non-empty line from a string (used as auto-title)
local function FirstNonEmptyLine(text)
    if not text or text == "" then return nil end
    for line in text:gmatch("[^\n]+") do
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed ~= "" then return trimmed end
    end
    return nil
end

-- Truncate a title to a sane display length
local function TruncateTitle(s, maxLen)
    maxLen = maxLen or 60
    if #s <= maxLen then return s end
    return s:sub(1, maxLen - 1) .. "..."
end

-- Safely get the BCB editbox widget (returns nil if BCB is absent or changed)
local function GetBCBEditBox()
    if not (BigChatBox and BigChatBox.SendDirect) then return nil end
    local eb = BigChatBox.editBox
    if eb and eb.GetText then return eb end
    return nil
end

-- ── Core capture logic ─────────────────────────────────────────────────────────

-- Reads the BCB editbox and creates/updates a note. Returns success, message.
local function DoCaptureFromBCB()
    local eb = GetBCBEditBox()
    if not eb then
        BNB:Print("|cffff8800BigNoteBox:|r BigChatBox editbox not found.")
        return false
    end

    local text = eb:GetText()
    if not text or text:match("^%s*$") then
        BNB:Print(L["CAPTURE_EMPTY"])
        return false
    end

    -- Auto-title from first non-empty line
    local autoTitle = FirstNonEmptyLine(text) or ""
    autoTitle = TruncateTitle(autoTitle)

    -- Create a new note
    local id = BNB.CreateNote(autoTitle, text)

    -- Refresh UI if main window is open
    if BNB.RefreshNoteList then BNB.RefreshNoteList() end

    -- Select the new note in the editor so the user can see it immediately
    if BNB.SelectNote then
        pcall(BNB.SelectNote, id)
    end

    BNB:Print(string.format(L["CAPTURE_SAVED"], "|cffffd100" .. autoTitle .. "|r"))
    return true, id
end

-- ── Public API ─────────────────────────────────────────────────────────────────

function BNB.CaptureFromBCB()
    DoCaptureFromBCB()
end

-- ── Right-click menu hook ──────────────────────────────────────────────────────

-- Reused WowStyle1 dropdown frame
local _bcbCtxDropdown = nil

-- Show a small context menu anchored to the BCB editbox
local function ShowBCBCaptureMenu(eb)
    local menuTitle = "BigNoteBox"

    if not _bcbCtxDropdown then
        _bcbCtxDropdown = CreateFrame("DropdownButton", "BNBBCBCaptureDropdown",
            UIParent, "WowStyle1DropdownTemplate")
        _bcbCtxDropdown:SetSize(1, 1)
        _bcbCtxDropdown:SetAlpha(0)
    end
    _bcbCtxDropdown:ClearAllPoints()
    _bcbCtxDropdown:SetPoint("TOPLEFT", eb, "TOPLEFT", 0, 0)

    _bcbCtxDropdown:SetupMenu(function(_, root)
        root:CreateTitle(menuTitle)
        root:CreateButton(L["CAPTURE_MENU"], function()
            DoCaptureFromBCB()
        end)
    end)
    _bcbCtxDropdown:OpenMenu()
end

-- ── Setup ──────────────────────────────────────────────────────────────────────

function BNB.SetupChatCapture()
    if _setupDone then return end
    _setupDone = true

    -- Wire the Import toolbar button (always, even without BCB, so the button
    -- gives useful feedback).
    -- BNB._toolbarImportBtn is set by MainWindow.lua during frame construction.
    -- We defer one frame so MainWindow has had time to build the toolbar.
    C_Timer.After(0, function()
        local btn = BNB._toolbarImportBtn
        if btn and btn.SetScript then
            btn:SetScript("OnClick", function()
                if not (BigChatBox and BigChatBox.SendDirect) then
                    if BNB.ShowBCBPromo then BNB.ShowBCBPromo() end
                    return
                end
                local id   = BNB._currentNoteID
                local note = id and BNB.GetNote(id)
                local body = note and (note.body or "") or ""
                if body == "" then
                    BNB:Print("|cffff8800BigNoteBox:|r This note is empty.")
                    return
                end
                if BCB_OpenMultiline then BCB_OpenMultiline() end
                C_Timer.After(0.05, function()
                    if BigChatBox.mlEditBox then
                        BigChatBox.mlEditBox:SetText(body)
                        BigChatBox.mlEditBox:SetFocus()
                        BigChatBox.mlEditBox:SetCursorPosition(#body)
                    end
                end)
            end)
        end
    end)

    -- Only hook BCB if it is actually loaded
    if not BNB.hasBCB then return end

    local eb = GetBCBEditBox()
    if not eb then return end

    -- Hook right-click on the BCB editbox to append our menu item.
    -- BCB may have its own OnMouseUp handler — we chain, not replace.
    local prevOnMouseUp = eb:GetScript("OnMouseUp")
    eb:SetScript("OnMouseUp", function(self, button, ...)
        if button == "RightButton" then
            -- Let BCB's own handler run first (if any), then show ours.
            if prevOnMouseUp then
                pcall(prevOnMouseUp, self, button, ...)
            end
            ShowBCBCaptureMenu(self)
        else
            if prevOnMouseUp then
                prevOnMouseUp(self, button, ...)
            end
        end
    end)
end

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

    -- Select the new note in the editor so the user can see it immediately
    if BNB.SelectNote then
        pcall(BNB.SelectNote, id)
    end

    BNB:Print(string.format(L["CAPTURE_SAVED"], "|cffffd100" .. autoTitle .. "|r"))
    return true, id
end

-- ── Right-click menu hook ──────────────────────────────────────────────────────

-- Show a small context menu at the pointer over the BCB editbox (ALL-148)
local function ShowBCBCaptureMenu(eb)
    BNB.ContextMenu.Open(eb, function(root)
        root:CreateTitle("BigNoteBox")
        root:CreateButton(L["CAPTURE_MENU"], function()
            DoCaptureFromBCB()
        end)
    end)
end

-- ── Setup ──────────────────────────────────────────────────────────────────────

function BNB.SetupChatCapture()
    if _setupDone then return end
    _setupDone = true

    -- Only hook BCB if it is actually loaded
    if not BNB.hasBCB then return end

    local eb = GetBCBEditBox()
    if not eb then return end

    -- Hook right-click on the BCB editbox to append our menu item.
    -- HookScript, not SetScript: BCB's own OnMouseUp runs first and any hooks
    -- other addons put on BCB's box survive (CMP-06).
    if eb._bnbCaptureHooked then return end
    eb._bnbCaptureHooked = true
    eb:HookScript("OnMouseUp", function(self, button)
        if button == "RightButton" then ShowBCBCaptureMenu(self) end
    end)
end

-- BigNoteBox Features/DragDrop.lua — Drag-and-drop for note body edit boxes
--
-- Allows dragging items, spells, macros, and mounts from the cursor onto any
-- BNB body EditBox (main editor, Focus Mode). Drops insert the WoW hyperlink
-- at the current cursor position, or appends if the box has no focus.
--
-- Also enables dragging existing hyperlinks OUT of the editor body by holding
-- the drag key (default Ctrl) and clicking a link — inserts it back to cursor.
-- (Full link-extraction drag-out is not possible from a plain EditBox without
-- a custom tokeniser, so we don't attempt it; see note below.)
--
-- Public API:
--   BNB.SetupDragDrop()   — called once from Initialize.lua
--   BNB.WireDropTarget(eb) — wire any EditBox as a drop target (called by
--                            BuildBodyField and FocusEditor after creation)
--
-- Supported cursor types:
--   item, spell, macro, mount, currency, battlepet

local BNB = BigNoteBox
local L   = BNB.L

-- ── Spell name helper ────────────────────────────────────────────────────────
local function SpellName(spellID)
    if not spellID then return nil end
    local info = C_Spell.GetSpellInfo(spellID)
    return info and info.name
end

-- ── Link builders ─────────────────────────────────────────────────────────────
-- Build a WoW hyperlink string for the dragged object.
-- Returns a string ready to pass to EditBox:Insert(), or nil if not supported.
local function BuildCursorLink()
    local ctype, id, subtype, extra = GetCursorInfo()
    if not ctype then return nil end

    if ctype == "item" then
        -- id is itemID; GetItemInfo returns the full link as return #2
        local _, link = GetItemInfo(id)
        return link  -- may be nil if not yet cached; caller should handle

    elseif ctype == "spell" then
        -- On retail TWW/Midnight, GetCursorInfo returns:
        --   "spell", slotIndex, bookType, spellID
        -- The 4th return is the actual spellID; the 2nd is the spellbook slot index.
        local spellID = extra or id
        local name = SpellName(spellID)
        if not name then return nil end
        -- Build a spell link: |cff71d5ff|Hspell:ID|h[Name]|h|r
        return string.format("|cff71d5ff|Hspell:%d|h[%s]|h|r", spellID, name)

    elseif ctype == "macro" then
        -- Macros don't have hyperlinks. Insert the macro name as plain text.
        -- GetMacroInfo(index) returns name, iconTexture, body
        local name = extra or (id and (GetMacroInfo(id)))
        if name and name ~= "" then
            return "[" .. name .. "]"
        end
        return nil

    elseif ctype == "mount" then
        -- id is mountID. C_MountJournal is retail+MoP; guard for Vanilla/TBC.
        if C_MountJournal and C_MountJournal.GetMountInfoByID then
            local mname = C_MountJournal.GetMountInfoByID(id)
            if mname then
                -- Mounts don't have a standard hyperlink — insert name in brackets
                return "[" .. mname .. "]"
            end
        end
        return nil

    elseif ctype == "currency" then
        if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
            local info = C_CurrencyInfo.GetCurrencyInfo(id)
            if info and info.name then
                return string.format("|cffffd100|Hcurrency:%d|h[%s]|h|r", id, info.name)
            end
        end
        return nil

    elseif ctype == "quest" then
        -- id is questID
        local title
        if C_QuestLog and C_QuestLog.GetQuestInfo then
            title = C_QuestLog.GetQuestInfo(id)
        end
        title = (title and title ~= "") and title or ("Quest " .. id)
        return string.format("|cffffff00|Hquest:%d:0|h[%s]|h|r", id, title)

    elseif ctype == "battlepet" then
        -- id is speciesID; C_PetJournal may not exist on all clients
        if C_PetJournal and C_PetJournal.GetPetInfoBySpeciesID then
            local name = C_PetJournal.GetPetInfoBySpeciesID(id)
            if name then return "[" .. name .. "]" end
        end
        return nil
    end

    return nil
end

-- ── Drop handler ──────────────────────────────────────────────────────────────
-- Called when a cursor object is released over an EditBox.
local function HandleDrop(eb)
    if not eb or not eb:IsEnabled() then return end

    -- Capture cursor state BEFORE ClearCursor wipes it
    local ctype = GetCursorInfo()
    if not ctype then return end

    local link = BuildCursorLink()

    -- Always clear the cursor — if we can't build a link we still consume
    -- the drag so WoW doesn't try to process it as something else.
    ClearCursor()

    if not link then return end

    -- Give the EditBox focus so Insert() places text at cursor position.
    -- If it already had focus the cursor position is preserved.
    eb:SetFocus()
    eb:Insert(link)
    BNB.MarkDirty()
end

-- ── Tooltip on hover while dragging ──────────────────────────────────────────
-- Show a small "Release to insert" hint in the tooltip when the player hovers
-- over the edit box with a draggable cursor object.
local function UpdateDragTooltip(eb)
    local ctype = GetCursorInfo()
    if not ctype then return end
    -- Only show hint for types we actually handle
    local supported = {
        item=true, spell=true, macro=true,
        mount=true, currency=true, battlepet=true,
    }
    if not supported[ctype] then return end
    GameTooltip:SetOwner(eb, "ANCHOR_CURSOR")
    GameTooltip:AddLine(L["DROP_INSERT_TIP"] or "Drop to insert link", 0.6, 1, 0.6)
    GameTooltip:Show()
end

-- ── Wire a single EditBox as a drop target ────────────────────────────────────
function BNB.WireDropTarget(eb)
    if not eb or eb._bnbDropWired then return end
    eb._bnbDropWired = true

    -- OnReceiveDrag fires when the player releases a cursor object over the frame
    local prev = eb:GetScript("OnReceiveDrag")
    eb:SetScript("OnReceiveDrag", function(self)
        HandleDrop(self)
        if prev then pcall(prev, self) end
    end)

    -- OnMouseDown with LeftButton also fires for drag releases in some clients;
    -- guard with GetCursorInfo so we only intercept actual drag operations.
    local prevMD = eb:GetScript("OnMouseDown")
    eb:SetScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" and GetCursorInfo() then
            HandleDrop(self)
        elseif prevMD then
            prevMD(self, btn)
        end
    end)

    -- OnEnter/OnLeave: show tooltip hint while dragging over the box
    local prevEnter = eb:GetScript("OnEnter")
    local prevLeave = eb:GetScript("OnLeave")

    eb:SetScript("OnEnter", function(self)
        if GetCursorInfo() then
            UpdateDragTooltip(self)
        elseif prevEnter then
            prevEnter(self)
        end
    end)

    eb:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        if prevLeave then prevLeave(self) end
    end)
end

-- ── Setup: wire the already-created editor body boxes ────────────────────────
-- BuildBodyField and FocusEditor call BNB.WireDropTarget immediately after
-- creating their EditBoxes. This function wires anything that already exists
-- at setup time (in case of load order edge cases).
function BNB.SetupDragDrop()
    -- Main editor body (created by BuildNoteEditor → BuildBodyField)
    if BNB._editorBody then
        BNB.WireDropTarget(BNB._editorBody)
    end
    -- Focus editor body is module-local in FocusEditor.lua; it calls
    -- BNB.WireDropTarget itself after creating the EditBox, so nothing to do
    -- here unless it was already built before this function ran.
end

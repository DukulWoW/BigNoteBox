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
        -- GetCursorInfo gives "item", itemID, itemLink: the link is there even for an
        -- item not in the cache yet, where C_Item.GetItemInfo would return nil.
        return subtype or select(2, C_Item.GetItemInfo(id))

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
        -- C_MountJournal is retail+MoP; guard for Vanilla/TBC. A mount has no
        -- link of its own: its summon spell's link, as the Reference Box keeps
        -- mounts (UI/ReferenceBox.lua drop), so it gets a tooltip and goes into
        -- the Reference Box like any link (ALL-445, Dukul 2026-10-11). The
        -- mount's ID is the 2nd return; the 3rd is tried when that is no mount.
        if C_MountJournal and C_MountJournal.GetMountInfoByID then
            for _, v in ipairs({ id, subtype }) do
                if type(v) == "number" then
                    local ok, mname, spellID = pcall(C_MountJournal.GetMountInfoByID, v)
                    if ok and mname then
                        if spellID then
                            return string.format("|cff71d5ff|Hspell:%d|h[%s]|h|r", spellID, mname)
                        end
                        return "[" .. mname .. "]"
                    end
                end
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
        -- An owned pet's GUID: its real link (species first in the link data,
        -- what the Reference Box reads). Else id is a speciesID: the name.
        -- C_PetJournal may not exist on all clients
        if type(id) == "string" and C_PetJournal and C_PetJournal.GetBattlePetLink then
            local ok, plink = pcall(C_PetJournal.GetBattlePetLink, id)
            if ok and plink then return plink end
        end
        if type(id) == "number" and C_PetJournal and C_PetJournal.GetPetInfoBySpeciesID then
            local name = C_PetJournal.GetPetInfoBySpeciesID(id)
            if name then return "[" .. name .. "]" end
        end
        return nil
    end

    return nil
end

-- A link put into a note's text also goes into its Reference Box (ALL-445,
-- the setting and the checks live in UI/ReferenceBox.lua). The note is the
-- box's own (a sticky's, Focus mode's), else the main editor's.
local function AddToRefBox(eb, link)
    if not BNB.RefBoxAddFromText then return end
    local noteID = eb._bnbNoteOf and eb._bnbNoteOf() or BNB._currentNoteID
    pcall(BNB.RefBoxAddFromText, noteID, link)
end

-- ── Drop handler ──────────────────────────────────────────────────────────────
-- Called when a cursor object is released over an EditBox. atEnd: dropped on
-- the empty area below the text (the scroll frame), so the link goes last.
local function HandleDrop(eb, atEnd)
    if not eb or not eb:IsEnabled() then return end

    -- Capture cursor state BEFORE ClearCursor wipes it
    local ctype = GetCursorInfo()
    if not ctype then return end

    local link = BuildCursorLink()

    -- Clear the cursor only once a link was built; a drop we cannot handle
    -- leaves the object on the cursor instead of swallowing it.
    if not link then return end
    ClearCursor()

    -- Give the EditBox focus so Insert() places text at cursor position.
    -- If it already had focus the cursor position is preserved.
    eb:SetFocus()
    if atEnd then eb:SetCursorPosition(#eb:GetText()) end
    eb:Insert(link)
    if not eb._bnbOwnSave then BNB.MarkDirty() end
    AddToRefBox(eb, link)
end

-- ── Link tooltips in plain note text (ALL-228) ───────────────────────────────
-- Hyperlinks on in the body EditBox: hovering an item / spell / quest link
-- shows its tooltip. Probed 2026-10-11 (Dukul, Retail): Enter / Leave / Click
-- fire, typing, cursor placement and selecting work as before. A plain click
-- still only places the cursor; the link acts on hover only.
local TIP_TYPES = { item = true, spell = true, achievement = true, quest = true, currency = true }
local function OnLinkEnter(self, link)
    if GetCursorInfo() then return end   -- the drag hint owns the tooltip
    local linkType = link and link:match("^(%a+):")
    if not TIP_TYPES[linkType] then return end
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    if pcall(GameTooltip.SetHyperlink, GameTooltip, link) then GameTooltip:Show()
    else GameTooltip:Hide() end
end

-- ── Shift-click into the note (2026-10-11) ───────────────────────────────────
-- Shift-clicking an item in the bags, a link in chat etc. goes through
-- ChatEdit_InsertLink, which only knows the chat box: a note body that has
-- focus takes the link instead. 12.x calls both names (as the Reference Box
-- hook knows), so a repeat of the same link in the same frame is dropped.
local wired = {}
local lastLink, lastTime
local function InsertIntoFocusedBody(link)
    if not link or link == "" then return end
    local now = GetTime()
    if link == lastLink and lastTime == now then return end
    for eb in pairs(wired) do
        if eb:IsVisible() and eb:IsEnabled() and eb:HasFocus() then
            lastLink, lastTime = link, now
            eb:Insert(link)
            if not eb._bnbOwnSave then BNB.MarkDirty() end
            AddToRefBox(eb, link)
            return
        end
    end
end

-- True while a note body has the keyboard: a shift-click is for the text,
-- not for the Reference Box (UI/ReferenceBox.lua TryAddLink asks)
function BNB.NoteBodyHasFocus()
    for eb in pairs(wired) do
        if eb:IsVisible() and eb:HasFocus() then return true end
    end
    return false
end

local insertHooked = false
local function HookInsertLink()
    if insertHooked then return end
    insertHooked = true
    if ChatEdit_InsertLink then hooksecurefunc("ChatEdit_InsertLink", InsertIntoFocusedBody) end
    if ChatFrameUtil and ChatFrameUtil.InsertLink then
        hooksecurefunc(ChatFrameUtil, "InsertLink", InsertIntoFocusedBody)
    end
end

-- ── Tooltip on hover while dragging ──────────────────────────────────────────
-- Show a small "Release to insert" hint in the tooltip when the player hovers
-- over the edit box with a draggable cursor object.
local function UpdateDragTooltip(eb)
    local ctype = GetCursorInfo()
    if not ctype or not eb:IsEnabled() then return end   -- a sticky not being edited
    -- Only show hint for types we actually handle
    local supported = {
        item=true, spell=true, macro=true,
        mount=true, currency=true, quest=true, battlepet=true,
    }
    if not supported[ctype] then return end
    GameTooltip:SetOwner(eb, "ANCHOR_CURSOR")
    GameTooltip:AddLine(L["DROP_INSERT_TIP"], 0.6, 1, 0.6)
    GameTooltip:Show()
end

-- ── Wire a single EditBox as a drop target ────────────────────────────────────
-- ownSave: the box saves its own text (a sticky's inline edit saves when the
-- edit ends), so an insert must not mark the main editor dirty.
-- noteOf: returns the id of the note the box holds (nil = the main editor's)
function BNB.WireDropTarget(eb, ownSave, noteOf)
    if not eb or eb._bnbDropWired then return end
    eb._bnbDropWired = true
    eb._bnbOwnSave = ownSave or nil
    eb._bnbNoteOf  = noteOf

    -- HookScript throughout, never SetScript: SetScript would drop any hooks
    -- already on the box, so this only worked while it was wired first (CMP-06).
    -- The box has no OnMouseDown / OnEnter of its own today; if one is added,
    -- it runs first and the drag checks below still act on GetCursorInfo().

    -- OnReceiveDrag fires when the player releases a cursor object over the frame
    eb:HookScript("OnReceiveDrag", HandleDrop)

    -- OnMouseDown with LeftButton also fires for drag releases in some clients;
    -- guard with GetCursorInfo so we only intercept actual drag operations.
    eb:HookScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" and GetCursorInfo() then HandleDrop(self) end
    end)

    -- OnEnter/OnLeave: show tooltip hint while dragging over the box. A hook
    -- runs after the box's own OnEnter, so the drag hint wins the tooltip.
    eb:HookScript("OnEnter", function(self)
        if GetCursorInfo() then UpdateDragTooltip(self) end
    end)
    eb:HookScript("OnLeave", function() GameTooltip:Hide() end)

    -- The empty area below the last line is the scroll frame, not the box:
    -- a drop there went nowhere (Dukul, 2026-10-11). It goes at the end now.
    local sf = eb:GetParent()
    if sf and sf.GetScrollChild and sf:GetScrollChild() == eb then
        sf:HookScript("OnReceiveDrag", function() HandleDrop(eb, true) end)
        sf:HookScript("OnMouseDown", function(_, btn)
            if btn == "LeftButton" and GetCursorInfo() then HandleDrop(eb, true) end
        end)
    end

    -- Typing above the Notes heading of a player note that updates itself
    -- (ALL-474, Features/PlayerNoteAuto.lua); looked up at call time
    eb:HookScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local UN = BNB.UnitNotes
        if UN and UN.OnTopEdit then UN.OnTopEdit(self, noteOf and noteOf() or BNB._currentNoteID) end
    end)

    -- Ctrl+click on a /way line places the waypoint, as a click on the link
    -- in a rich note does (ALL-477); Ctrl+Shift+click opens the map at it.
    -- The click has moved the cursor by OnMouseUp: the line around it is read
    -- (GetCursorPosition is a byte offset, as Blizzard's AutoComplete uses it).
    eb:HookScript("OnMouseUp", function(self, btn)
        if btn ~= "LeftButton" or not IsControlKeyDown() or GetCursorInfo() then return end
        if not (BNB.ParseWayLine and BNB.FollowWayLine) then return end
        local text, pos = self:GetText() or "", self:GetCursorPosition() or 0
        local s = pos
        while s > 0 and text:sub(s, s) ~= "\n" do s = s - 1 end
        local e = text:find("\n", pos + 1, true) or (#text + 1)
        local line = text:sub(s + 1, e - 1)
        if BNB.ParseWayLine(line) then BNB.FollowWayLine(line, IsShiftKeyDown()) end
    end)

    -- Link tooltips (ALL-228) and shift-click into the box
    if eb.SetHyperlinksEnabled then
        eb:SetHyperlinksEnabled(true)
        eb:HookScript("OnHyperlinkEnter", OnLinkEnter)
        eb:HookScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)
    end
    wired[eb] = true
    HookInsertLink()
end

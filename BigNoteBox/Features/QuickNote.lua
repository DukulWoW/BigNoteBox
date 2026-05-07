-- BigNoteBox Features/QuickNote.lua
-- Inject a small icon button into WoW's quest, gossip, and item-text panels
-- so the player can create a note directly from the source frame.
--
-- Supported surfaces (v1):
--   • QuestFrame          — quest detail (accept) and turn-in
--   • GossipFrame         — NPC gossip greeting
--   • ItemTextFrame       — books, letters, readable items
--   • ImmersionFrame      — Immersion addon (floating moveable button)
--   • DialogueUI          — DialogueUI / YUI-Dialogue addon
--
-- Quest reward items on accept/turn-in frames are added to the new note's
-- RefBox attachments automatically.
--
-- On create behaviour is controlled by BigNoteBoxDB.quickNoteAction:
--   "silent"  — create in background, no window change (default)
--   "open"    — create then open BNB on the new note
--   "confirm" — show a small popup to confirm / edit the title before creating

local BNB = BigNoteBox

-- ── Constants ────────────────────────────────────────────────────────────────

local ASSETS          = "Interface\\AddOns\\BigNoteBox\\Assets\\"
local QUEST_ICON      = ASSETS .. "Buttons\\bt-createnote-normal"        -- normal state for Blizzard frame buttons
local QUEST_ICON_HOVER= ASSETS .. "Buttons\\bt-createnote-hover"  -- hover state for Blizzard frame buttons

-- ── Button position on Blizzard frames ───────────────────────────────────────
-- POSITION: top-left corner of the host frame, next to the native X button.
-- QN_X / QN_Y measured and confirmed in-game; adjust if chrome shifts.
local QN_X =  292  -- pixels right from frame TOPLEFT
local QN_Y =  1    -- pixels down  from frame TOPLEFT
local QN_SZ = 24   -- button size in pixels

-- QUEST LOG POPUP BUTTON POSITION (fallback only)
-- The button is normally anchored to QuestLogPopupDetailFrame.ShowMapButton.
-- QL_X / QL_Y are only used if ShowMapButton does not exist on this patch.
local QL_X =  290  -- fallback: pixels right from QuestLogPopupDetailFrame TOPLEFT
local QL_Y =  -2   -- fallback: pixels down  from QuestLogPopupDetailFrame TOPLEFT

-- ── Icon pools for random fallback ───────────────────────────────────────────
-- Books + Notes from the manifest — used when no item icon is available.
local RANDOM_ICONS = {}
do
    -- Collect Books and Notes sub-paths from ICON_MANIFEST at runtime.
    -- The manifest is loaded before Features, so BNB.ICON_MANIFEST is ready.
    if BNB.ICON_MANIFEST then
        for _, path in ipairs(BNB.ICON_MANIFEST) do
            if path:find("\\Books\\") or path:find("\\Notes\\") then
                RANDOM_ICONS[#RANDOM_ICONS + 1] = path
            end
        end
    end
end

local function RandomIcon()
    if #RANDOM_ICONS == 0 then return nil end
    return RANDOM_ICONS[math.random(1, #RANDOM_ICONS)]
end

-- ── DB helpers ───────────────────────────────────────────────────────────────
local function DB() return BigNoteBoxDB end
local function IsEnabled() return DB() and DB().quickNoteEnabled ~= false end
local function GetAction() return (DB() and DB().quickNoteAction) or "silent" end

-- ── Quest reward item harvesting ─────────────────────────────────────────────
-- Reads reward items from the active quest frame and adds them as attachments
-- to noteID.  Works for both QUEST_DETAIL (accept) and QUEST_COMPLETE (turn-in).
--
-- Strategy (two tiers):
--   1. API-first: GetNumQuestChoices / GetNumQuestRewards + GetQuestItemInfo.
--      GetQuestItemInfo returns itemID as the 6th value and is populated during
--      both QUEST_DETAIL and QUEST_COMPLETE events. GetNumQuestChoices/Rewards
--      may return 0 on certain accept frames — if so, fall through to tier 2.
--   2. Frame scan: iterate QuestInfoRewardsFrame children for shown buttons
--      with a .questRewardID or .itemID field. This covers cases where the API
--      counts are 0 but Blizzard's UI has populated widget-level item data.
local function AttachQuestRewards(noteID)
    if not BNB.RBAddAttachment then return end

    local attached = 0
    local seen = {}   -- prevent duplicate attachments

    local function TryAttach(itemID)
        local n = tonumber(itemID)
        if not n or n <= 0 then return end
        if seen[n] then return end
        seen[n] = true
        BNB.RBAddAttachment(noteID, { type = "item", id = n })
        attached = attached + 1
    end

    -- ── Tier 1: direct API calls ─────────────────────────────────────────────
    local numChoices = GetNumQuestChoices and GetNumQuestChoices() or 0
    local numRewards = GetNumQuestRewards and GetNumQuestRewards() or 0

    for i = 1, numChoices do
        local _, _, _, _, _, itemID = GetQuestItemInfo("choice", i)
        TryAttach(itemID)
    end
    for i = 1, numRewards do
        local _, _, _, _, _, itemID = GetQuestItemInfo("reward", i)
        TryAttach(itemID)
    end

    -- ── Tier 2: scan QuestInfoRewardsFrame children ──────────────────────────
    -- Fallback when API counts return 0 (e.g. some accept-frame edge cases).
    -- Blizzard's quest UI populates .questRewardID or .itemID on reward buttons.
    if attached == 0 and QuestInfoRewardsFrame then
        local children = { QuestInfoRewardsFrame:GetChildren() }
        for _, child in ipairs(children) do
            if child.IsShown and child:IsShown() then
                local id = child.questRewardID
                            or child.itemID
                            or (child.item and type(child.item) == "table"
                                and child.item.GetItemID and child.item:GetItemID())
                TryAttach(id)
            end
        end
    end
end

-- Attaches the quest itself (as a quest attachment) to the note's RefBox.
-- questID: from GetQuestID() — valid during QuestFrame interactions.
local function AttachQuestID(noteID, questID)
    if not questID or questID <= 0 then return end
    if not BNB.RBAddAttachment then return end
    BNB.RBAddAttachment(noteID, { type = "quest", id = questID })
end
-- icon:   full texture path or nil (falls back to random)
-- tags:   array of tag strings
-- title, body: strings
-- rewardAttacher: optional function(noteID) called after creation to add rewards
local function CreateQuickNote(title, body, icon, tags, rewardAttacher)
    if not BNB.CreateNote then return end

    local action = GetAction()

    if action == "confirm" then
        -- Small static popup to confirm/edit the title before creating
        StaticPopupDialogs["BNB_QUICKNOTE_CONFIRM"] = StaticPopupDialogs["BNB_QUICKNOTE_CONFIRM"] or {
            text         = "Create note — edit title if needed:",
            button1      = "Create",
            button2      = "Cancel",
            hasEditBox   = true,
            maxLetters   = 100,
            whileDead    = false,
            hideOnEscape = true,
            OnShow = function(self)
                self.EditBox:SetText(self._qnTitle or "")
                self.EditBox:SetFocus()
                self.EditBox:HighlightText()
            end,
            OnAccept = function(self)
                local t = self.EditBox:GetText()
                if t == "" then t = self._qnTitle or "" end
                local id = BNB.CreateNote(t, self._qnBody or "")
                if not id then return end
                local n = BigNoteBoxNotesDB and BigNoteBoxNotesDB.notes and BigNoteBoxNotesDB.notes[id]
                if n then
                    n.icon = self._qnIcon or RandomIcon()
                    n.tags = self._qnTags or {}
                    n.updated = time()
                    for _, tag in ipairs(n.tags) do
                        BNB.TagIndexAdd(id, tag)
                    end
                end
                if self._qnReward then self._qnReward(id) end
                if BNB.RefreshNoteList then BNB.RefreshNoteList() end
            end,
        }
        local dlg = StaticPopup_Show("BNB_QUICKNOTE_CONFIRM")
        if dlg then
            dlg._qnTitle  = title
            dlg._qnBody   = body
            dlg._qnIcon   = icon or RandomIcon()
            dlg._qnTags   = tags
            dlg._qnReward = rewardAttacher
        end
        return
    end

    -- Silent or open: create immediately
    local id = BNB.CreateNote(title or "", body or "")
    if not id then return end

    -- Set icon and tags directly on the new note record
    local ndb = BigNoteBoxNotesDB
    local note = ndb and ndb.notes and ndb.notes[id]
    if note then
        note.icon    = icon or RandomIcon()
        note.tags    = tags or {}
        note.updated = time()
        for _, tag in ipairs(note.tags) do
            BNB.TagIndexAdd(id, tag)
        end
    end

    if rewardAttacher then rewardAttacher(id) end
    if BNB.RefreshNoteList then BNB.RefreshNoteList() end

    if action == "open" then
        if BNB.mainFrame and not BNB.mainFrame:IsShown() then
            BNB.mainFrame:Show()
        end
        if BNB.SelectNote then BNB.SelectNote(id) end
    end
end

-- ── Icon from item texture ────────────────────────────────────────────────────
-- Returns the item icon as a texture path string, or nil if unavailable.
-- We use GetItemInfo's 10th return (texture) which is available for cached items.
local function ItemIcon(itemID)
    if not itemID then return nil end
    local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(itemID)
    if tex then
        -- tex is usually a numeric fileID on retail; convert to string for SetTexture
        return tostring(tex)
    end
    return nil
end

-- ── Button builder helper ─────────────────────────────────────────────────────
-- Creates a button anchored at TOPLEFT of `parent` with QN_X / QN_Y offset.
-- Uses note-copy.tga (normal) and note-copy-hover.tga (hover) — no tinted overlay.
-- onClickFn receives no arguments; it should call CreateQuickNote itself.
local function MakeButton(name, parent, onClickFn)
    local btn = CreateFrame("Button", name, parent)
    btn:SetSize(QN_SZ, QN_SZ)
    -- POSITION: adjust QN_X / QN_Y at the top of this file if needed
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", QN_X, QN_Y)
    btn:SetFrameStrata("HIGH")
    btn:SetFrameLevel((parent:GetFrameLevel() or 0) + 10)

    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture(QUEST_ICON)
    btn._tex = tex

    -- Hover: swap to the dedicated hover texture instead of a colour overlay
    local hi = btn:CreateTexture(nil, "HIGHLIGHT")
    hi:SetAllPoints()
    hi:SetTexture(QUEST_ICON_HOVER)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:AddLine("Create a BigNoteBox note", 1, 1, 1)
        GameTooltip:AddLine("from this content.", 0.78, 0.78, 0.78)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    btn:SetScript("OnClick", onClickFn)
    return btn
end

-- ── Text extraction helpers ───────────────────────────────────────────────────

-- Paragraph spacer: double single-newlines to add breathing room.
-- WoW Lua 5.1 treats \0 in gsub as an empty-pattern match (inserts between
-- every character), so we use a safe multi-char sentinel instead.
local PH = "@@DNLBRK@@"

local function DoubleNewlines(text)
    if not text or text == "" then return text end
    -- Also strip \r so \r\n normalises to \n before processing
    text = text:gsub("\r", "")
    return text:gsub("\n\n", PH):gsub("\n", "\n\n"):gsub(PH, "\n\n")
end

local function QuestDetailText()
    -- Returns title, body for the current quest detail (accept) frame.
    local title = GetTitleText() or ""
    local body  = DoubleNewlines(GetQuestText() or "")
    return title, body
end

local function QuestCompleteText()
    -- Quest turn-in frame.
    local title = GetTitleText() or ""
    local body  = DoubleNewlines(GetRewardText() or "")
    return title, body
end

-- Returns title, body for a quest viewed from the quest log.
-- Uses C_QuestLog.SetSelectedQuest + GetQuestLogQuestText (quest-log-specific
-- APIs) which do NOT rely on the active quest accept/turn-in frame globals.
local function QuestLogText(questID)
    if not questID or questID == 0 then return "Quest", "" end

    -- Ensure this quest is selected in the quest log
    if C_QuestLog and C_QuestLog.SetSelectedQuest then
        C_QuestLog.SetSelectedQuest(questID)
    end

    local title = ""
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        title = C_QuestLog.GetTitleForQuestID(questID) or ""
    end
    if title == "" then title = "Quest " .. questID end

    local desc, objText = "", ""
    if GetQuestLogQuestText then
        desc, objText = GetQuestLogQuestText()
        desc    = desc    or ""
        objText = objText or ""
    end

    -- Double-space paragraphs for readability
    if desc ~= "" then
        desc = DoubleNewlines(desc)
    end

    return title, desc
end

-- Returns a formatted money string (e.g. "34g 16s") from a copper amount,
-- or nil if copper is zero or nil.
local function FormatMoney(copper)
    if not copper or copper <= 0 then return nil end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if c > 0 then parts[#parts + 1] = c .. "c" end
    return #parts > 0 and table.concat(parts, " ") or nil
end

-- Appends quest objectives to a body string.
-- Uses C_QuestLog.GetQuestObjectives (questID-based, reliable on Midnight).
-- Returns the body unchanged if no objectives found.
local function AppendObjectives(body, questID)
    if not questID or questID == 0 then return body end
    if not (C_QuestLog and C_QuestLog.GetQuestObjectives) then return body end
    local ok, objectives = pcall(function()
        return C_QuestLog.GetQuestObjectives(questID)
    end)
    if not ok or not objectives or #objectives == 0 then return body end
    local parts = {}
    for _, obj in ipairs(objectives) do
        if obj and obj.text and obj.text ~= "" then
            parts[#parts + 1] = obj.text
        end
    end
    if #parts == 0 then return body end
    return body .. "\n\nObjectives\n" .. table.concat(parts, "\n") .. "\n"
end

-- Collects quest rewards for a given questID into a formatted multi-line
-- string, or nil if nothing found.
-- Mirrors DUI's approach: active-frame APIs for money/XP/honor,
-- C_QuestInfoSystem.GetQuestRewardCurrencies for currencies (TWW/Midnight),
-- and C_QuestOffer.GetQuestOfferMajorFactionReputationRewards for warband rep.
-- All paths are pcall-guarded so unknown APIs silently produce nothing.
-- Only called when BigNoteBoxDB.saveQuestRewards is true.
local function FormatRewards(questID)
    if not questID or questID == 0 then return nil end
    local lines = {}

    -- Money (active frame -- same API DUI uses)
    local money = FormatMoney(GetRewardMoney and GetRewardMoney())
    if money then lines[#lines + 1] = "Money: " .. money end

    -- XP (active frame)
    local xp = GetRewardXP and GetRewardXP()
    if xp and xp > 0 then lines[#lines + 1] = "XP: " .. xp end

    -- Honor (active frame)
    local honor = GetRewardHonor and GetRewardHonor()
    if honor and honor > 0 then lines[#lines + 1] = "Honor: " .. honor end

    -- Currencies -- TWW/Midnight: C_QuestInfoSystem.GetQuestRewardCurrencies
    -- returns a table of {currencyID, totalRewardAmount, ...} per entry.
    if C_QuestInfoSystem and C_QuestInfoSystem.GetQuestRewardCurrencies then
        local ok, currencies = pcall(C_QuestInfoSystem.GetQuestRewardCurrencies, questID)
        if ok and currencies then
            for _, cur in ipairs(currencies) do
                if cur and cur.currencyID and cur.currencyID > 0 then
                    local amount = cur.totalRewardAmount or cur.quantity or cur.numItems or 0
                    if amount > 0 then
                        local name
                        if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
                            local ok2, info = pcall(C_CurrencyInfo.GetCurrencyInfo, cur.currencyID)
                            if ok2 and info then name = info.name end
                        end
                        name = name or ("Currency " .. cur.currencyID)
                        lines[#lines + 1] = name .. ": " .. amount
                    end
                end
            end
        end
    end

    -- Major faction / warband reputation (TWW/Midnight)
    -- Returns array of {factionID, rewardAmount} for the active quest offer frame.
    if C_QuestOffer and C_QuestOffer.GetQuestOfferMajorFactionReputationRewards then
        local ok, repRewards = pcall(C_QuestOffer.GetQuestOfferMajorFactionReputationRewards)
        if ok and repRewards then
            for _, rep in ipairs(repRewards) do
                if rep and rep.factionID and rep.rewardAmount and rep.rewardAmount > 0 then
                    local name
                    if C_MajorFactions and C_MajorFactions.GetMajorFactionData then
                        local ok2, data = pcall(C_MajorFactions.GetMajorFactionData, rep.factionID)
                        if ok2 and data then name = data.name end
                    end
                    name = name or ("Faction " .. rep.factionID)
                    lines[#lines + 1] = name .. ": +" .. rep.rewardAmount .. " rep"
                end
            end
        end
    end

    -- Regular (non-major-faction) reputation -- older API, still works on Midnight
    if GetNumQuestRewardFactions and GetQuestRewardFactionInfo then
        local ok, numFac = pcall(GetNumQuestRewardFactions)
        if ok and numFac and numFac > 0 then
            for i = 1, numFac do
                local ok2, factionName, reputationAmount = pcall(GetQuestRewardFactionInfo, i)
                if ok2 and factionName and factionName ~= "" and reputationAmount and reputationAmount > 0 then
                    lines[#lines + 1] = factionName .. ": +" .. reputationAmount .. " rep"
                end
            end
        end
    end

    if #lines == 0 then return nil end
    return table.concat(lines, "\n")
end

-- Collects quest rewards for a quest viewed from the quest log into a
-- formatted multi-line string, or nil if nothing found.
-- Uses quest-log-specific APIs (GetQuestLogRewardMoney, GetQuestLogRewardXP,
-- GetQuestLogRewardInfo) which do NOT rely on the active quest frame globals.
-- Requires C_QuestLog.SetSelectedQuest(questID) to have been called first.
local function FormatQuestLogRewards(questID)
    if not questID or questID == 0 then return nil end
    local lines = {}

    -- Money
    local money = FormatMoney(GetQuestLogRewardMoney and GetQuestLogRewardMoney())
    if money then lines[#lines + 1] = "Money: " .. money end

    -- XP
    local xp = GetQuestLogRewardXP and GetQuestLogRewardXP()
    if xp and xp > 0 then lines[#lines + 1] = "XP: " .. xp end

    -- Currencies -- same questID-based API used in FormatRewards
    if C_QuestInfoSystem and C_QuestInfoSystem.GetQuestRewardCurrencies then
        local ok, currencies = pcall(C_QuestInfoSystem.GetQuestRewardCurrencies, questID)
        if ok and currencies then
            for _, cur in ipairs(currencies) do
                if cur and cur.currencyID and cur.currencyID > 0 then
                    local amount = cur.totalRewardAmount or cur.quantity or cur.numItems or 0
                    if amount > 0 then
                        local name
                        if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
                            local ok2, info = pcall(C_CurrencyInfo.GetCurrencyInfo, cur.currencyID)
                            if ok2 and info then name = info.name end
                        end
                        name = name or ("Currency " .. cur.currencyID)
                        lines[#lines + 1] = name .. ": " .. amount
                    end
                end
            end
        end
    end

    -- Item rewards (name list in note body for reference)
    if GetNumQuestLogRewards then
        local ok, numRewards = pcall(GetNumQuestLogRewards)
        if ok and numRewards and numRewards > 0 then
            for i = 1, numRewards do
                local ok2, name = pcall(GetQuestLogRewardInfo, i)
                if ok2 and name and name ~= "" then
                    lines[#lines + 1] = "Item: " .. name
                end
            end
        end
    end

    -- Choice rewards
    if GetNumQuestLogChoices then
        local ok, numChoices = pcall(GetNumQuestLogChoices, questID)
        if ok and numChoices and numChoices > 0 then
            for i = 1, numChoices do
                local ok2, name = pcall(GetQuestLogChoiceInfo, i)
                if ok2 and name and name ~= "" then
                    lines[#lines + 1] = "Choice: " .. name
                end
            end
        end
    end

    if #lines == 0 then return nil end
    return table.concat(lines, "\n")
end

-- Reads reward items from the quest log and adds them as attachments to noteID.
-- Uses quest-log-specific APIs. Requires C_QuestLog.SetSelectedQuest(questID)
-- to have been called first.
local function AttachQuestLogRewards(noteID, questID)
    if not BNB.RBAddAttachment then return end
    if not questID or questID == 0 then return end

    local seen = {}

    local function TryAttach(itemID)
        local n = tonumber(itemID)
        if not n or n <= 0 then return end
        if seen[n] then return end
        seen[n] = true
        BNB.RBAddAttachment(noteID, { type = "item", id = n })
    end

    -- Fixed rewards
    if GetNumQuestLogRewards then
        local ok, numRewards = pcall(GetNumQuestLogRewards)
        if ok and numRewards and numRewards > 0 then
            for i = 1, numRewards do
                local ok2, name, tex, cnt, qual, isUsable, itemID = pcall(GetQuestLogRewardInfo, i)
                if ok2 then TryAttach(itemID) end
            end
        end
    end

    -- Choice rewards
    if GetNumQuestLogChoices then
        local ok, numChoices = pcall(GetNumQuestLogChoices, questID)
        if ok and numChoices and numChoices > 0 then
            for i = 1, numChoices do
                local ok2, name, tex, cnt, qual, isUsable, itemID = pcall(GetQuestLogChoiceInfo, i)
                if ok2 then TryAttach(itemID) end
            end
        end
    end
end

-- Returns an icon from quest log reward items, or a random fallback.
-- Uses quest-log-specific APIs. Requires C_QuestLog.SetSelectedQuest(questID)
-- to have been called first.
local function QuestLogIcon(questID)
    if not questID or questID == 0 then return RandomIcon() end

    -- Try fixed rewards first, then choices
    if GetNumQuestLogRewards then
        local ok, numRewards = pcall(GetNumQuestLogRewards)
        if ok and numRewards and numRewards > 0 then
            for i = 1, numRewards do
                local ok2, name, tex = pcall(GetQuestLogRewardInfo, i)
                if ok2 and tex then return tostring(tex) end
            end
        end
    end

    if GetNumQuestLogChoices then
        local ok, numChoices = pcall(GetNumQuestLogChoices, questID)
        if ok and numChoices and numChoices > 0 then
            for i = 1, numChoices do
                local ok2, name, tex = pcall(GetQuestLogChoiceInfo, i)
                if ok2 and tex then return tostring(tex) end
            end
        end
    end

    return RandomIcon()
end

local function GossipText()
    -- NPC gossip greeting.
    -- GetGossipText() was removed in Midnight; C_GossipInfo.GetText() is the replacement.
    -- Title: prefer UnitName("npc"). If the target is a world object (no NPC unit),
    -- extract the creature ID from the GUID for a stable fallback title.
    local npcName = UnitName("npc")
    if not npcName or npcName == "" then
        -- Try to extract creature ID from GUID: "Creature-0-REALM-MAP-ID-CREATUREID-SPAWN"
        local guid = UnitGUID("npc")
        local creatureID = guid and guid:match("^Creature%-0%-%d+%-%d+%-%d+%-(%d+)")
        if creatureID then
            npcName = "NPC: " .. creatureID
        else
            npcName = "NPC " .. math.random(1000, 9999)
        end
    end
    local body = (C_GossipInfo and C_GossipInfo.GetText and C_GossipInfo.GetText()) or ""
    return npcName, body
end

-- Tag for item-text: try ItemTextGetMaterial() to distinguish parchment/book
local function ItemTextTags()
    local mat = ItemTextGetMaterial and ItemTextGetMaterial() or ""
    -- Material "Book" typically indicates a readable book rather than a letter/note
    if mat and mat:lower():find("book") then return { "Book" } end
    return { "Letter" }
end

local function ItemTextContent()
    -- Single-page read (kept as fallback; full capture uses the async accumulator).
    -- ItemTextGetItem() returns the item/object name (the "title")
    -- ItemTextGetText() returns the current page body
    local title = ItemTextGetItem and ItemTextGetItem() or ""
    local body  = ItemTextGetText and ItemTextGetText()  or ""
    -- Strip any |c colour codes and |r resets from book/letter body
    body = body:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return title, body
end

-- ── Item-text async page accumulator ─────────────────────────────────────────
-- ItemTextNextPage() is asynchronous: it fires ITEM_TEXT_READY when the new
-- page is ready. We cannot read all pages in a synchronous loop.
-- Strategy: when the button is clicked we start collecting from page 1.
--   • We record which page the reader was on, navigate to page 1, then
--     collect each page as ITEM_TEXT_READY fires.
--   • When there are no more pages we create the note and navigate back to
--     the original page.
--   • A 10-page safety cap prevents runaway loops on unexpectedly large books.
--   • While collecting, the button is temporarily disabled to prevent re-entry.

local _itCollecting = false   -- true while we are mid-collection
local _itPages      = {}      -- accumulated page texts
local _itTitle      = ""
local _itTags       = {}
local _itOrigPage   = 1       -- page the reader was on when they clicked
local _itCurrentPage= 0       -- page we have just received
local MAX_PAGES     = 50      -- safety cap

-- Forward declaration: FoundAtHeader is defined later but referenced inside
-- FinishItemTextCapture. Declaring local here lets Lua resolve it correctly.
local FoundAtHeader

-- Called once all pages have been gathered.
local function FinishItemTextCapture()
    _itCollecting = false
    -- Re-enable the button
    local btn = _G["BNBQuickNoteItemTextBtn"]
    if btn then btn:SetAlpha(1); btn:SetEnabled(true) end

    local parts = {}
    for i, pageText in ipairs(_itPages) do
        if #_itPages > 1 then
            parts[i] = "--- Page " .. i .. " ---\n" .. pageText
        else
            parts[i] = pageText
        end
    end
    local body = FoundAtHeader() .. table.concat(parts, "\n\n")
    -- Strip colour codes
    body = body:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")

    CreateQuickNote(_itTitle, body, RandomIcon(), _itTags, nil)

    -- Navigate back to the original page.
    -- We are currently on the last page; step back one page at a time.
    -- Each call to ItemTextPrevPage() fires ITEM_TEXT_READY, but we don't
    -- need to read those pages — just count steps back. We temporarily
    -- stop our collector during this phase by leaving _itCollecting = false.
    local stepsBack = _itCurrentPage - _itOrigPage
    if stepsBack > 0 then
        -- Use a repeating timer that fires once per tick to avoid
        -- calling ItemTextPrevPage() inside ITEM_TEXT_READY (documented gotcha)
        local ticks = 0
        C_Timer.NewTicker(0.1, function(ticker)
            ticks = ticks + 1
            if ticks <= stepsBack and ItemTextPrevPage then
                ItemTextPrevPage()
            else
                ticker:Cancel()
            end
        end)
    end

    _itPages = {}
end

-- Called on each ITEM_TEXT_READY while collecting.
local function OnItemTextReady()
    if not _itCollecting then return end

    local text = ItemTextGetText and ItemTextGetText() or ""
    _itCurrentPage = _itCurrentPage + 1
    _itPages[#_itPages + 1] = text

    if ItemTextHasNextPage and ItemTextHasNextPage() and _itCurrentPage < MAX_PAGES then
        -- Request next page on the next tick to avoid the documented
        -- synchronisation issue with calling NextPage inside ITEM_TEXT_READY.
        C_Timer.After(0, function()
            if ItemTextNextPage then ItemTextNextPage() end
        end)
    else
        -- All pages collected (or cap reached).
        C_Timer.After(0, FinishItemTextCapture)
    end
end

-- Start collection from whatever page the reader is currently on.
-- We navigate to page 1 first so the note always contains all pages in order.
local function StartItemTextCapture()
    if _itCollecting then return end   -- already in progress

    _itTitle      = ItemTextGetItem and ItemTextGetItem() or ""
    _itTags       = ItemTextTags()
    _itPages      = {}
    _itCurrentPage= 0
    _itCollecting = true

    -- Disable button to prevent re-entry
    local btn = _G["BNBQuickNoteItemTextBtn"]
    if btn then btn:SetAlpha(0.4); btn:SetEnabled(false) end

    -- Figure out current page number: ItemTextGetPage() returns the current page.
    _itOrigPage = (ItemTextGetPage and ItemTextGetPage()) or 1

    -- Navigate back to page 1 first using PrevPage.
    -- Each PrevPage fires ITEM_TEXT_READY, but we don't want to collect yet.
    -- We use a staged approach: suppress the collector until we reach page 1,
    -- then start collecting.
    if _itOrigPage > 1 then
        local stepsBack = _itOrigPage - 1
        local ticks = 0
        -- Temporarily flag that we are navigating (not yet collecting)
        _itCollecting = false
        C_Timer.NewTicker(0.1, function(ticker)
            ticks = ticks + 1
            if ticks <= stepsBack and ItemTextPrevPage then
                ItemTextPrevPage()
            else
                ticker:Cancel()
                -- Now on page 1 — start collecting on next ITEM_TEXT_READY
                _itCurrentPage = 0
                _itCollecting  = true
                -- Fire collection for page 1 immediately since ITEM_TEXT_READY
                -- won't fire again unless we navigate. Read the current page now.
                C_Timer.After(0, OnItemTextReady)
            end
        end)
    else
        -- Already on page 1 — collect it immediately.
        C_Timer.After(0, OnItemTextReady)
    end
end

-- ── Location header helpers ───────────────────────────────────────────────────

-- Returns the current zone name and coordinates as formatted strings, or nils.
local function GetLocationInfo()
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return nil, nil, nil end
    local mapInfo = C_Map.GetMapInfo(mapID)
    local zoneName = mapInfo and mapInfo.name or nil
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    local x, y
    if pos then
        x = string.format("%.2f", pos.x * 100)
        y = string.format("%.2f", pos.y * 100)
    end
    return zoneName, x, y
end

-- "Said by <NPC> in <Zone> at XX.XX XX.XX\n----------\n\n" — for quest and gossip sources.
local function NPCLocationHeader()
    local npc = UnitName("npc") or ""
    local zone, x, y = GetLocationInfo()
    if npc == "" and not zone then return "" end
    local parts = { "Said by " .. (npc ~= "" and npc or "Unknown") }
    if zone then
        parts[#parts + 1] = " in " .. zone
        if x and y then
            parts[#parts + 1] = " at " .. x .. " " .. y
        end
    end
    return table.concat(parts) .. "\n----------\n\n"
end

-- "Found in <Zone> at XX.XX XX.XX\n----------\n\n" — for book and letter sources.
FoundAtHeader = function()
    local zone, x, y = GetLocationInfo()
    if not zone then return "" end
    local line = "Found in " .. zone
    if x and y then
        line = line .. " at " .. x .. " " .. y
    end
    return line .. "\n----------\n\n"
end


local function QuestFrameIcon()
    -- Try choice rewards first, then fixed rewards
    for i = 1, (GetNumQuestChoices() or 0) do
        local link = GetQuestItemLink("choice", i)
        if link then
            local id = tonumber(link:match("item:(%d+)"))
            local ic = id and ItemIcon(id)
            if ic then return ic end
        end
    end
    for i = 1, (GetNumQuestRewards() or 0) do
        local link = GetQuestItemLink("reward", i)
        if link then
            local id = tonumber(link:match("item:(%d+)"))
            local ic = id and ItemIcon(id)
            if ic then return ic end
        end
    end
    return RandomIcon()   -- fallback: random book/note icon
end

-- ── Vanilla WoW frame injection ───────────────────────────────────────────────
-- QuestFrame hosts both detail and complete sub-frames; we check which is
-- visible at click time.

local function InjectQuestFrame()
    if not QuestFrame then return end

    MakeButton("BNBQuickNoteQuestBtn", QuestFrame, function()
        if not IsEnabled() then return end

        local title, body, icon, tags, rewardFn
        local questID = GetQuestID and GetQuestID() or 0

        -- Midnight retail renamed QuestDetailFrame → QuestFrameDetailPanel
        -- and QuestRewardFrame → QuestFrameCompletePanel.
        -- Check both old and new names for forward/backward compatibility.
        local detailShown = (QuestFrameDetailPanel and QuestFrameDetailPanel:IsShown())
                         or (QuestDetailFrame and QuestDetailFrame:IsShown())
        local rewardShown = (QuestFrameCompletePanel and QuestFrameCompletePanel:IsShown())
                         or (QuestFrameRewardPanel and QuestFrameRewardPanel:IsShown())
                         or (QuestRewardFrame and QuestRewardFrame:IsShown())

        if detailShown then
            -- Quest accept frame
            title, body = QuestDetailText()
            body        = NPCLocationHeader() .. body
            body        = AppendObjectives(body, questID)
            if BigNoteBoxDB and BigNoteBoxDB.saveQuestRewards ~= false then
                local rewardStr = FormatRewards(questID)
                if rewardStr then body = body .. "\n\n----------\n" .. rewardStr end
            end
            icon        = QuestFrameIcon()
            tags        = { "Quest" }
            rewardFn    = function(noteID)
                AttachQuestID(noteID, questID)
                AttachQuestRewards(noteID)
            end

        elseif rewardShown then
            -- Quest turn-in frame
            title, body = QuestCompleteText()
            body        = NPCLocationHeader() .. body
            if BigNoteBoxDB and BigNoteBoxDB.saveQuestRewards ~= false then
                local rewardStr = FormatRewards(questID)
                if rewardStr then body = body .. "\n\n----------\n" .. rewardStr end
            end
            icon        = QuestFrameIcon()
            tags        = { "Quest" }
            rewardFn    = function(noteID)
                AttachQuestID(noteID, questID)
                AttachQuestRewards(noteID)
            end
        else
            -- Fallback: grab whatever text is in the frame
            title = GetTitleText() or "Quest"
            body  = NPCLocationHeader() .. (GetQuestText() or GetRewardText() or "")
            icon  = RandomIcon()
            tags  = { "Quest" }
            rewardFn = function(noteID)
                AttachQuestID(noteID, questID)
                AttachQuestRewards(noteID)
            end
        end

        CreateQuickNote(title, body, icon, tags, rewardFn)
    end)
end

-- ── Quest log detail popup injection ─────────────────────────────────────────
-- Quest log injection covers two contexts on Midnight retail:
--   1. QuestMapFrame.DetailsFrame   — full map + quest log view
--   2. QuestLogPopupDetailFrame     — popup detail when clicking a quest title
-- We create a single button, reparent and reposition it between the two contexts.

local _questLogSelectedID = nil  -- questID currently shown in quest log detail
local _qlBtn               = nil  -- our single reusable button

local function PositionQuestLogBtn()
    if not _qlBtn then return end
    -- QuestLogPopupDetailFrame (popup): anchor LEFT of the ShowMapButton
    if QuestLogPopupDetailFrame and QuestLogPopupDetailFrame:IsVisible() then
        _qlBtn:SetParent(QuestLogPopupDetailFrame)
        _qlBtn:ClearAllPoints()
        if QuestLogPopupDetailFrame.ShowMapButton then
            _qlBtn:SetPoint("LEFT", QuestLogPopupDetailFrame.ShowMapButton, "RIGHT", -4, 0)
        else
            -- Fallback if ShowMapButton not present: adjust QL_X/QL_Y at top of file
            _qlBtn:SetPoint("TOPLEFT", QuestLogPopupDetailFrame, "TOPLEFT", QL_X, QL_Y)
        end
        _qlBtn:Show()
    -- QuestMapFrame.DetailsFrame (full map view): anchor TOPRIGHT
    elseif QuestMapFrame and QuestMapFrame.DetailsFrame
        and QuestMapFrame.DetailsFrame:IsVisible() then
        _qlBtn:SetParent(QuestMapFrame.DetailsFrame)
        _qlBtn:ClearAllPoints()
        _qlBtn:SetPoint("TOPLEFT", QuestMapFrame.DetailsFrame, "TOPLEFT", 100, -10)
        _qlBtn:Show()
    else
        _qlBtn:Hide()
    end
end

local function InjectQuestLogFrame()
    -- Create one button, parented initially to UIParent (hidden).
    -- PositionQuestLogBtn() reparents it on each hook call.
    local btn = CreateFrame("Button", "BNBQuickNoteQuestLogBtn", UIParent)
    btn:SetSize(QN_SZ, QN_SZ)
    btn:SetFrameStrata("HIGH")
    btn:SetFrameLevel(100)
    btn:Hide()

    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture(QUEST_ICON)

    local hi = btn:CreateTexture(nil, "HIGHLIGHT")
    hi:SetAllPoints()
    hi:SetTexture(QUEST_ICON_HOVER)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:AddLine("Create a BigNoteBox note", 1, 1, 1)
        GameTooltip:AddLine("from this quest.", 0.78, 0.78, 0.78)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    btn:SetScript("OnClick", function()
        if not IsEnabled() then return end

        local questID = _questLogSelectedID or 0
        if questID == 0 then
            BNB:Print("|cffff6666No quest selected in the quest log.|r")
            return
        end

        -- QuestLogText calls SetSelectedQuest internally, which primes all
        -- quest-log APIs (GetQuestLogQuestText, GetQuestLogRewardMoney, etc.)
        local title, body = QuestLogText(questID)
        body = AppendObjectives(body, questID)

        if BigNoteBoxDB and BigNoteBoxDB.saveQuestRewards ~= false then
            local rewardStr = FormatQuestLogRewards(questID)
            if rewardStr then body = body .. "\n\n----------\n" .. rewardStr end
        end

        local icon = QuestLogIcon(questID)
        local rewardFn = function(noteID)
            AttachQuestID(noteID, questID)
            AttachQuestLogRewards(noteID, questID)
        end
        CreateQuickNote(title, body, icon, { "Quest" }, rewardFn)
    end)

    _qlBtn = btn

    -- Hook 1: quest title clicked in the log list
    hooksecurefunc("QuestMapLogTitleButton_OnClick", function(self)
        if self and self.questID then
            _questLogSelectedID = self.questID
        end
        PositionQuestLogBtn()
    end)

    -- Hook 2: quest details shown via map frame (e.g. clicking from world map)
    hooksecurefunc("QuestMapFrame_ShowQuestDetails", function(questID)
        if questID and questID > 0 then
            _questLogSelectedID = questID
        end
        PositionQuestLogBtn()
    end)

    -- Hook 3: popup detail frame shown
    -- QuestLogPopupDetailFrame.questID is populated by Blizzard before this fires
    hooksecurefunc("QuestLogPopupDetailFrame_Show", function()
        if QuestLogPopupDetailFrame and QuestLogPopupDetailFrame.questID then
            _questLogSelectedID = QuestLogPopupDetailFrame.questID
        end
        PositionQuestLogBtn()
    end)
end

local function InjectGossipFrame()
    if not GossipFrame then return end

    MakeButton("BNBQuickNoteGossipBtn", GossipFrame, function()
        if not IsEnabled() then return end
        local title, body = GossipText()
        body = NPCLocationHeader() .. body
        CreateQuickNote(title, body, RandomIcon(), { "Gossip" }, nil)
    end)
end

local function InjectItemTextFrame()
    if not ItemTextFrame then return end

    MakeButton("BNBQuickNoteItemTextBtn", ItemTextFrame, function()
        if not IsEnabled() then return end
        -- Kick off the async multi-page collection.
        -- StartItemTextCapture handles navigation to page 1 and
        -- collects all pages before calling CreateQuickNote.
        StartItemTextCapture()
    end)
end

-- ── Immersion addon: floating moveable button ─────────────────────────────────
-- ImmersionFrame is the main Immersion container.  We create a draggable
-- button parented to UIParent (not ImmersionFrame, so it isn't hidden when
-- Immersion slides offscreen) that appears when Immersion is active.

local _immersionBtn = nil

-- Default position confirmed in-game (CENTER offset from UIParent CENTER).
local IMMERSION_BTN_DEFAULT_X = -250.0
local IMMERSION_BTN_DEFAULT_Y = -250.0

local function SaveImmersionPos()
    if not _immersionBtn then return end
    -- GetLeft/GetBottom and GetScreenWidth/GetScreenHeight all return values in
    -- UIParent virtual coordinate space. No scale conversion needed.
    local left   = _immersionBtn:GetLeft()
    local bottom = _immersionBtn:GetBottom()
    local w      = _immersionBtn:GetWidth()
    local h      = _immersionBtn:GetHeight()
    if not left or not bottom then return end
    local cx = (left + w / 2) - GetScreenWidth()  / 2
    local cy = (bottom + h / 2) - GetScreenHeight() / 2
    DB().quickNoteImmersionX = cx
    DB().quickNoteImmersionY = cy
    -- Debug output when Immersion position debug is active
    if BNB._debugImmersionPos then
        BNB:Print(string.format(
            "|cff88bbff[BNB Immersion] Saved position: X=%.1f Y=%.1f|r", cx, cy))
    end
end

-- Called from ConfigWindow "Reset button position" button.
function BNB.ResetImmersionBtnPos()
    if DB() then
        DB().quickNoteImmersionX = nil
        DB().quickNoteImmersionY = nil
    end
    if _immersionBtn then
        _immersionBtn:ClearAllPoints()
        _immersionBtn:SetPoint("CENTER", UIParent, "CENTER",
            IMMERSION_BTN_DEFAULT_X, IMMERSION_BTN_DEFAULT_Y)
    end
end

local function BuildImmersionButton()
    if _immersionBtn then return end

    local BTN_FLOAT_SZ = 64   -- large floating button for Immersion

    local btn = CreateFrame("Button", "BNBQuickNoteImmersionBtn", UIParent)
    btn:SetSize(BTN_FLOAT_SZ, BTN_FLOAT_SZ)
    btn:SetFrameStrata("DIALOG")
    btn:SetMovable(true)
    btn:EnableMouse(true)
    btn:RegisterForDrag("LeftButton")
    btn:SetClampedToScreen(true)
    -- Immersion fades UIParent alpha to 0 when active — ignore that so we stay visible.
    btn:SetIgnoreParentAlpha(true)
    btn:Hide()

    -- Default position confirmed in-game: center-left of screen, mid-height.
    -- Users can shift-drag it anywhere; position is saved across sessions.
    local savedX = DB() and DB().quickNoteImmersionX
    local savedY = DB() and DB().quickNoteImmersionY
    if savedX and savedY then
        btn:SetPoint("CENTER", UIParent, "CENTER", savedX, savedY)
    else
        btn:SetPoint("CENTER", UIParent, "CENTER",
            IMMERSION_BTN_DEFAULT_X, IMMERSION_BTN_DEFAULT_Y)
    end

    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetTexture(ASSETS .. "UI\\ui-icon-quest")
    -- Anchor texture to center so it scales symmetrically without moving the hitbox
    tex:SetPoint("CENTER", btn, "CENTER")
    tex:SetSize(BTN_FLOAT_SZ, BTN_FLOAT_SZ)

    -- Visual-only scale feedback on the texture — frame hitbox stays fixed
    local PAD_HOVER = 4   -- grow 4px each side on hover
    local PAD_CLICK = -3  -- shrink 3px each side on click
    local function SetTexPad(pad)
        local s = BTN_FLOAT_SZ + pad * 2
        tex:SetSize(s, s)
    end

    -- Shift+drag to reposition; plain drag does nothing so click still works cleanly
    btn:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() then
            self:StartMoving()
        end
    end)
    btn:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveImmersionPos()
    end)

    btn:SetScript("OnEnter", function(self)
        SetTexPad(PAD_HOVER)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:AddLine("Create a BigNoteBox note", 1, 1, 1)
        GameTooltip:AddLine("from this Immersion dialogue.", 0.78, 0.78, 0.78)
        GameTooltip:AddLine("Shift+Drag to reposition.", 0.55, 0.55, 0.55)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        SetTexPad(0)
        GameTooltip:Hide()
    end)

    btn:SetScript("OnMouseDown", function(self)
        SetTexPad(PAD_CLICK)
    end)
    btn:SetScript("OnMouseUp", function(self)
        if self:IsMouseOver() then
            SetTexPad(PAD_HOVER)
        else
            SetTexPad(0)
        end
    end)

    btn:SetScript("OnClick", function()
        if not IsEnabled() then return end
        -- Read text directly from Immersion's FontStrings.
        -- textFs.storedText holds the FULL original dialogue text before Immersion
        -- splits it into animated "pages" (sentences). :GetText() only has the
        -- currently displayed sentence — always prefer storedText.
        local imm = _G["ImmersionFrame"]
        local immTitle, immBody
        if imm and imm.TalkBox then
            local nameFs = imm.TalkBox.NameFrame and imm.TalkBox.NameFrame.Name
            local textFs = imm.TalkBox.TextFrame and imm.TalkBox.TextFrame.Text
            immTitle = nameFs and nameFs:GetText()
            -- storedText is the complete un-paged text; fall back to GetText() if absent
            immBody  = textFs and (textFs.storedText or textFs:GetText())
        end
        -- Fallback to live APIs if Immersion frame path fails
        local questTitle = GetTitleText()
        local title = (immTitle and immTitle ~= "") and immTitle
                   or (questTitle and questTitle ~= "") and questTitle
                   or UnitName("npc") or "NPC"
        local body = (immBody and immBody ~= "") and immBody
                  or GetQuestText()
                  or (C_GossipInfo and C_GossipInfo.GetText and C_GossipInfo.GetText())
                  or GetRewardText()
                  or ""
        local questID = GetQuestID and GetQuestID() or 0
        local rewardFn = (questID > 0) and function(noteID)
            AttachQuestID(noteID, questID)
            AttachQuestRewards(noteID)
        end or nil
        local immBody = NPCLocationHeader() .. body
        if questID > 0 then
            immBody = AppendObjectives(immBody, questID)
        end
        if questID > 0 and BigNoteBoxDB and BigNoteBoxDB.saveQuestRewards ~= false then
            local rewardStr = FormatRewards(questID)
            if rewardStr then immBody = immBody .. "\n\n----------\n" .. rewardStr end
        end
        CreateQuickNote(title, immBody, RandomIcon(), { "Quest" }, rewardFn)
        BNB:Print("Note created: " .. (title or ""))
    end)

    _immersionBtn = btn
end

-- Show/hide the Immersion floating button based on ImmersionFrame visibility
local function SyncImmersionBtn()
    if not _immersionBtn then return end
    local imm = _G["ImmersionFrame"]
    local btnEnabled = DB() and DB().quickNoteImmersionBtn ~= false
    if imm and imm:IsShown() and IsEnabled() and btnEnabled then
        _immersionBtn:Show()
    else
        _immersionBtn:Hide()
    end
end

-- ── Immersion bypass ─────────────────────────────────────────────────────────
-- Keybind toggles whether Immersion handles the next interaction.
-- When bypass is active we unregister ImmersionFrame from its events so the
-- native Blizzard frames take over, then re-register when the session ends.

local _immBypass = false   -- true while bypass is active for this session

-- The events Immersion registers on ImmersionFrame (from Onload.lua / Events.lua)
local IMM_EVENTS = {
    "GOSSIP_SHOW", "GOSSIP_CLOSED",
    "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE",
    "QUEST_GREETING", "QUEST_FINISHED",
}

local function ImmersionBypassStart()
    local imm = _G["ImmersionFrame"]
    if not imm then return end
    _immBypass = true
    for _, ev in ipairs(IMM_EVENTS) do
        imm:UnregisterEvent(ev)
    end
end

local function ImmersionBypassEnd()
    if not _immBypass then return end
    _immBypass = false
    local imm = _G["ImmersionFrame"]
    if not imm then return end
    for _, ev in ipairs(IMM_EVENTS) do
        imm:RegisterEvent(ev)
    end
end

function BNB.ToggleImmersionBypass()
    if not _G["ImmersionFrame"] then return end
    if _immBypass then
        ImmersionBypassEnd()
        BNB:Print("QuickNote: Immersion restored.")
    else
        ImmersionBypassStart()
        BNB:Print("QuickNote: Immersion bypassed — native frames active until conversation ends.")
    end
end

-- ── DialogueUI (YUI-Dialogue) integration ────────────────────────────────────
-- DUIQuestFrame is a named global (from DialogueUI.xml).
-- DUIDialogBaseMixin:GetContentForClipboard() is a public mixin method that
-- returns the fully assembled NPC name + dialogue text + quest details.
--
-- IMPORTANT: GetContentForClipboard() re-reads C_GossipInfo.GetText() and
-- similar live APIs. These clear after the event fires, so calling the method
-- at copy-button-click time returns "" for gossip text.
--
-- Fix: we cache the result at interaction-open time (one tick after the event,
-- so DUI's own handler runs first and its internal state is populated).
-- The hook on SendContentToClipboard reads from _duiCache, not live APIs.
--
-- Book text: DUI's book module assembles all pages internally via a private
-- Cache object. The fully assembled text ends up in DUI's anonymous Clipboard
-- frame's EditBox immediately after the copy button fires. We locate that frame
-- once (by scanning UIParent children for the anonymous frame DUI creates), then
-- read its EditBox text in OnDUIBookCopy.
--
-- Text format (dialogue): "[NPC: 12345] Magister Umbric\n<body...>"
-- We strip the [NPC: XXXX] prefix and use the name as the note title.

local _duiInjected  = false  -- true once we have confirmed DUI is loaded
local _duiCache     = nil    -- cached GetContentForClipboard() for current dialogue
local _duiQuestID   = nil    -- cached GetQuestID() for current quest dialogue

local function CacheDUIText()
    -- Called one tick after a dialogue event fires. DUI has already populated
    -- its internal state by this point, so GetContentForClipboard() reads live
    -- APIs while they are still valid.
    -- Wrapped in pcall: DUI's GetContentForClipboard can crash if reward item
    -- names are not yet cached (nil concatenation in DUI's UITemplates.lua).
    local frame = _G["DUIQuestFrame"]
    if not frame or not frame.GetContentForClipboard then return end
    local ok, raw = pcall(function() return frame:GetContentForClipboard() end)
    if ok then
        _duiCache = (raw and raw ~= "") and raw or nil
    end
    -- Cache quest ID while QUEST_DETAIL/QUEST_COMPLETE events still have it live
    _duiQuestID = GetQuestID and GetQuestID() or nil
    if _duiQuestID and _duiQuestID <= 0 then _duiQuestID = nil end
end

local function GetDUIText()
    -- Parse _duiCache into title + body.
    -- Falls back to a live call in case the cache missed.
    local frame = _G["DUIQuestFrame"]
    local raw = _duiCache
    if not raw then
        if frame and frame.GetContentForClipboard then
            raw = frame:GetContentForClipboard()
        end
    end
    if not raw or raw == "" then return nil, nil end
    -- Strip leading "[NPC: XXXX] " and split into title / body
    local npcName, body = raw:match("^%[NPC:%s*%d+%]%s*(.-)%s*\n(.+)$")
    if npcName then
        return npcName, NPCLocationHeader() .. body
    end
    return UnitName("npc") or "NPC", NPCLocationHeader() .. raw
end

local function TryInitDUI()
    if _duiInjected then return end
    if _G["DUIQuestFrame"] ~= nil
    or _G["DialogueUI_DB"] ~= nil
    or _G["DialogueUIAPI"] ~= nil
    or C_AddOns.IsAddOnLoaded("DialogueUI") then
        _duiInjected = true
        BNB.ApplyDUIAutoNote()
    end
end

-- ── DUI auto-note: hook DUI's copy text button ───────────────────────────────
-- Dialogue: hooksecurefunc on SendContentToClipboard reads _duiCache.
-- Book: accumulate page text on each ITEM_TEXT_READY while DUI's book is
--   shown. DUI calls ItemTextNextPage() itself to cache all pages — we
--   piggyback on those events without navigating ourselves.

local _duiHooked    = false  -- true once dialogue hooksecurefunc called
local _duiBookPages = {}     -- [pageNum] = text, populated by ITEM_TEXT_READY

local function OnDUIDialogueCopy()
    if not DB() or not DB().duiAutoNote then return end
    if not IsEnabled() then return end
    local title, body = GetDUIText()
    if title and body and body ~= NPCLocationHeader() then
        local qid = _duiQuestID
        local rewardFn = qid and function(noteID)
            AttachQuestID(noteID, qid)
            AttachQuestRewards(noteID)
        end or nil
        CreateQuickNote(title, body, RandomIcon(), { "Quest" }, rewardFn)
    end
end

local function OnDUIBookCopy()
    if not DB() or not DB().duiAutoNote then return end
    if not IsEnabled() then return end
    local bookFrame = _G["DUIBookFrame"]
    if not bookFrame or not bookFrame:IsShown() then return end

    local title = (bookFrame.Header and bookFrame.Header.Title
                    and bookFrame.Header.Title:GetText())
               or (ItemTextGetItem and ItemTextGetItem())
               or "Book"

    -- Build body from our accumulated page cache.
    local body
    local numPages = 0
    for _ in pairs(_duiBookPages) do numPages = numPages + 1 end

    if numPages > 0 then
        local parts = {}
        for i = 1, numPages do
            local text = _duiBookPages[i] or ""
            text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            if numPages > 1 then
                parts[#parts + 1] = "--- Page " .. i .. " ---\n" .. text
            else
                parts[#parts + 1] = text
            end
        end
        body = table.concat(parts, "\n\n")
    end

    if not body or body == "" then
        body = ItemTextGetText and ItemTextGetText() or ""
        body = body:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    end

    body = FoundAtHeader() .. body
    CreateQuickNote(title, body, RandomIcon(), { "Book" }, nil)
end

function BNB.ApplyDUIAutoNote()
    if _duiHooked then return end

    local questFrame = _G["DUIQuestFrame"]
    if questFrame and questFrame.SendContentToClipboard then
        hooksecurefunc(questFrame, "SendContentToClipboard", OnDUIDialogueCopy)
        _duiHooked = true
    end

    local function HookBookCopyBtn(bf)
        bf.CopyTextButton:HookScript("OnClick", function()
            OnDUIBookCopy()
        end)
    end

    local bookFrame = _G["DUIBookFrame"]
    if bookFrame and bookFrame.CopyTextButton then
        HookBookCopyBtn(bookFrame)
    else
        C_Timer.After(3, function()
            local bf = _G["DUIBookFrame"]
            if bf and bf.CopyTextButton then HookBookCopyBtn(bf) end
        end)
    end
end

-- ── Event handling ────────────────────────────────────────────────────────────

local qnFrame = CreateFrame("Frame")
qnFrame:RegisterEvent("PLAYER_LOGIN")
qnFrame:RegisterEvent("QUEST_DETAIL")
qnFrame:RegisterEvent("QUEST_PROGRESS")
qnFrame:RegisterEvent("QUEST_COMPLETE")
qnFrame:RegisterEvent("QUEST_GREETING")
qnFrame:RegisterEvent("GOSSIP_SHOW")
qnFrame:RegisterEvent("ITEM_TEXT_READY")
-- Close / Immersion sync events
qnFrame:RegisterEvent("QUEST_FINISHED")
qnFrame:RegisterEvent("GOSSIP_CLOSED")
qnFrame:RegisterEvent("ITEM_TEXT_CLOSED")

qnFrame:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "PLAYER_LOGIN" then
        -- Inject into vanilla frames (they exist by PLAYER_LOGIN)
        InjectQuestFrame()
        InjectGossipFrame()
        InjectItemTextFrame()
        InjectQuestLogFrame()

        -- Build Immersion floating button if Immersion is loaded
        if _G["ImmersionFrame"] or C_AddOns.IsAddOnLoaded("Immersion") then
            BuildImmersionButton()
        end

        -- Try DialogueUI detection (addon may or may not be loaded)
        TryInitDUI()
        -- If DUI was already injected before login fired, still apply the hook
        if _duiInjected then BNB.ApplyDUIAutoNote() end
        return
    end

    -- Dialogue open events: sync Immersion button and cache DUI text
    if event == "QUEST_DETAIL"  or event == "QUEST_COMPLETE"
    or event == "QUEST_PROGRESS" or event == "QUEST_GREETING"
    or event == "GOSSIP_SHOW"   or event == "ITEM_TEXT_READY" then
        -- Feed the item-text page accumulator if a collection is in progress.
        -- Must not be called from inside the ITEM_TEXT_READY handler itself
        -- (documented gotcha), so we defer one tick.
        if event == "ITEM_TEXT_READY" and _itCollecting then
            C_Timer.After(0, OnItemTextReady)
            return
        end

        -- DUI book: accumulate each page as DUI navigates through them.
        -- DUI calls ItemTextNextPage() itself to cache all pages; we piggyback
        -- on each ITEM_TEXT_READY to read ItemTextGetText() for that page.
        -- NOTE: DUIBookFrame is NOT shown during caching — DUI only calls
        -- ShowUI() after all pages are cached and text heights calculated.
        -- So we gate on the frame existing (DUI book module active) rather
        -- than IsShown(). Harmless if DUI book module is disabled — the data
        -- just sits unused and is cleared on ITEM_TEXT_CLOSED.
        if event == "ITEM_TEXT_READY" and _duiInjected then
            local bf = _G["DUIBookFrame"]
            if bf then
                local page = ItemTextGetPage and ItemTextGetPage() or 1
                local text = ItemTextGetText and ItemTextGetText() or ""
                if text ~= "" then
                    _duiBookPages[page] = text
                end
            end
        end

        -- Defer one tick: let DUI (and Immersion) run their own handlers first,
        -- then cache DUI text while live APIs are still populated.
        C_Timer.After(0, SyncImmersionBtn)
        if _duiInjected then
            C_Timer.After(0, CacheDUIText)
        end

        -- If DialogueUI wasn't detected yet, try again now (lazy fallback)
        if not _duiInjected then
            C_Timer.After(0.1, TryInitDUI)
        end
        return
    end

    if event == "QUEST_FINISHED" or event == "GOSSIP_CLOSED"
    or event == "ITEM_TEXT_CLOSED" then
        if _immersionBtn then _immersionBtn:Hide() end
        _duiCache   = nil    -- clear stale dialogue cache
        _duiQuestID = nil    -- clear stale quest ID
        _duiBookPages = {}   -- clear stale book page cache
        ImmersionBypassEnd()
        return
    end
end)

-- Also hook ImmersionFrame OnShow/OnHide if it exists at login time
-- (Immersion may load after PLAYER_LOGIN if it's an optional dep)
local function HookImmersionFrame()
    local imm = _G["ImmersionFrame"]
    if not imm or imm._bnbHooked then return end
    imm._bnbHooked = true
    imm:HookScript("OnShow", function()
        BuildImmersionButton()
        if IsEnabled() then _immersionBtn:Show() end
    end)
    imm:HookScript("OnHide", function()
        if _immersionBtn then _immersionBtn:Hide() end
    end)
end

-- Try hooking at login; also retry after a short delay in case Immersion
-- initialises its frame slightly after PLAYER_LOGIN fires.
C_Timer.After(2, function()
    HookImmersionFrame()
    if not _duiInjected then TryInitDUI() end
end)
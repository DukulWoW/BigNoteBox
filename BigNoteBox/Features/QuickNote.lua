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
    -- The books and notes categories of the icon catalog (ALL-238).
    -- The manifest is loaded before Features, so BNB.IconsIn is ready.
    if BNB.IconsIn then
        for _, key in ipairs({ "books", "notes" }) do
            for _, path in ipairs(BNB.IconsIn(key)) do
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
-- Creates the note and fills it in. Shared by the confirm popup and the
-- silent/open path, which used to carry two copies of this.
local function MakeQuickNote(title, body, icon, tags, rewardAttacher, rich)
    local id = BNB.CreateNote(title or "", body or "")
    if not id then return end
    -- Through UpdateNote, so the tags are deduped and indexed (SV-07)
    -- Every quick note also gets BNB.QUICK_NOTE_TAG (ALL-152), first
    local all = { BNB.QUICK_NOTE_TAG }
    for _, t in ipairs(tags or {}) do all[#all + 1] = t end
    BNB.UpdateNote(id, {
        icon   = icon or RandomIcon(),
        source = "quicknote",   -- made from a quest, gossip or book frame; Oracle badge (ALL-69)
        tags   = all,
        richMode = rich and true or nil,   -- ALL-634: per kind, Settings > Note Capture
    })
    if rewardAttacher then rewardAttacher(id) end
    return id
end

-- A note of what an NPC said is titled "<name> (Dialogue)", so the name itself
-- stays free for the NPC's own note (F6 / unit menu), which would otherwise
-- come out as "<name> (Duplicate)" (Dukul, 2026-10-31)
local function DialogueTitle(npcName)
    return string.format(BNB.L["QN_DIALOGUE_TITLE_FMT"], npcName)
end

-- icon:   full texture path or nil (falls back to random)
-- tags:   array of tag strings
-- title, body: strings
-- rewardAttacher: optional function(noteID) called after creation to add rewards
-- rich: make it a rich note (the body is rich markup, ALL-634)
local function CreateQuickNote(title, body, icon, tags, rewardAttacher, rich)
    if not BNB.CreateNote then return end

    local action = GetAction()

    if action == "confirm" then
        -- Small static popup to confirm/edit the title before creating.
        -- The note's parts travel as the popup's data (BUG-15): they used to
        -- be set on the popup frame after StaticPopup_Show, when OnShow had
        -- already run, so the box showed nothing or the previous title.
        -- Our own dialog (ALL-572 S3); an empty box keeps the title
        local data = {
            title = title, body = body, icon = icon or RandomIcon(),
            tags = tags, reward = rewardAttacher, rich = rich,
        }
        BNB.Dialog.Prompt({
            text = BNB.L["QN_CONFIRM_TEXT"], value = data.title or "", maxLetters = 100,
            okLabel = BNB.L["QN_CONFIRM_CREATE"], allowEmpty = true,
            onAccept = function(t)
                if t == "" then t = data.title or "" end
                if MakeQuickNote(t, data.body, data.icon, data.tags, data.reward, data.rich) then
                    BNB:Print(string.format(BNB.L["QN_NOTE_CREATED"], t))
                end
            end,
        })
        return
    end

    -- Silent or open: create immediately
    local id = MakeQuickNote(title, body, icon, tags, rewardAttacher, rich)
    if not id then return end

    if action == "open" then
        if BNB.mainFrame and not BNB.mainFrame:IsShown() then
            BNB.mainFrame:Show()
        end
        if BNB.SelectNote then BNB.SelectNote(id) end
    else
        -- Silent mode shows nothing else, so say it in chat
        BNB:Print(string.format(BNB.L["QN_NOTE_CREATED"], title or ""))
    end
end

-- ── Icon from item texture ────────────────────────────────────────────────────
-- Returns the item icon as a texture path string, or nil if unavailable.
-- We use GetItemInfo's 10th return (texture) which is available for cached items.
local function ItemIcon(itemID)
    if not itemID then return nil end
    local _, _, _, _, _, _, _, _, _, tex = C_Item.GetItemInfo(itemID)
    if tex then
        -- tex is usually a numeric fileID on retail; convert to string for SetTexture
        return tostring(tex)
    end
    return nil
end

-- ── Button builder helper ─────────────────────────────────────────────────────
-- Creates a button anchored at TOPLEFT of `parent` with QN_X / QN_Y offset.
-- The "createnote" icon button, always the normal look: it sits on Blizzard
-- frames, which have no skin mode. Hover, press (FOR-20) and the reset on hide
-- come from BNB.CreateIconButton (UI/IconButton.lua).
-- onClickFn receives no arguments; it should call CreateQuickNote itself.
local function MakeButton(name, parent, onClickFn)
    local btn = BNB.CreateIconButton(parent, QN_SZ, "createnote", { name = name, skin = false,
        tip = BNB.L["QN_BTN_TIP1"], tipSub = BNB.L["QN_BTN_TIP2"], tipAnchor = "ANCHOR_BOTTOMRIGHT",
        onClick = function() onClickFn() end })
    -- POSITION: adjust QN_X / QN_Y at the top of this file if needed
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", QN_X, QN_Y)
    btn:SetFrameStrata("HIGH")
    btn:SetFrameLevel((parent:GetFrameLevel() or 0) + 10)
    -- Quick Note module off: no button at all, rather than one whose click
    -- does nothing (ALL-380, Dukul 2026-10-07). Read each time the window opens
    btn:SetShown(IsEnabled())
    parent:HookScript("OnShow", function() btn:SetShown(IsEnabled()) end)
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

-- Puts the player's quest-log selection back after we selected questID to read
-- it (DEP-04: moving the selection from addon code and leaving it there moved
-- the player's own pick and has been a taint source for quest-log actions).
local function RestoreQuestSelection(prev, questID)
    if prev and prev ~= 0 and prev ~= questID and C_QuestLog.SetSelectedQuest then
        C_QuestLog.SetSelectedQuest(prev)
    end
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
    if title == "" then title = string.format(BNB.L["QN_QUEST_TITLE_FMT"], questID) end

    local desc = ""
    if GetQuestLogQuestText then
        desc = GetQuestLogQuestText() or ""
    end

    -- Double-space paragraphs for readability
    if desc ~= "" then
        desc = DoubleNewlines(desc)
    end

    return title, desc
end

-- The quest's objective lines, or nil (ALL-634: drawn by CaptureBody).
-- Uses C_QuestLog.GetQuestObjectives (questID-based, reliable on Midnight).
local function QuestObjectives(questID)
    if not questID or questID == 0 then return nil end
    if not (C_QuestLog and C_QuestLog.GetQuestObjectives) then return nil end
    local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, questID)
    if not ok or not objectives or #objectives == 0 then return nil end
    local parts = {}
    for _, obj in ipairs(objectives) do
        if obj and obj.text and obj.text ~= "" then
            parts[#parts + 1] = obj.text
        end
    end
    return #parts > 0 and parts or nil
end

-- Collects quest rewards for a given questID as a list of entries (ALL-634:
-- { kind = "money", copper } / { kind = "xp", n } / { kind = "honor", n } /
-- { kind = "text", text }, drawn by RewardLines), or nil if nothing found.
-- Mirrors DUI's approach: active-frame APIs for money/XP/honor,
-- C_QuestInfoSystem.GetQuestRewardCurrencies for currencies (TWW/Midnight),
-- and C_QuestOffer.GetQuestOfferMajorFactionReputationRewards for warband rep.
-- All paths are pcall-guarded so unknown APIs silently produce nothing.
-- Only called when BigNoteBoxDB.saveQuestRewards is true.
local function FormatRewards(questID)
    if not questID or questID == 0 then return nil end
    local lines = {}

    -- Money (active frame -- same API DUI uses)
    local copper = GetRewardMoney and GetRewardMoney()
    if copper and copper > 0 then lines[#lines + 1] = { kind = "money", copper = copper } end

    -- XP (active frame)
    local xp = GetRewardXP and GetRewardXP()
    if xp and xp > 0 then lines[#lines + 1] = { kind = "xp", n = xp } end

    -- Honor (active frame)
    local honor = GetRewardHonor and GetRewardHonor()
    if honor and honor > 0 then lines[#lines + 1] = { kind = "honor", n = honor } end

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
                        lines[#lines + 1] = { kind = "text", text = name .. ": " .. amount }
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
                    lines[#lines + 1] = { kind = "text", text = name .. ": +" .. rep.rewardAmount .. " rep" }
                end
            end
        end
    end
    -- (A regular-reputation branch read GetNumQuestRewardFactions /
    -- GetQuestRewardFactionInfo, which no client has: removed in batch 11.)

    if #lines == 0 then return nil end
    return lines
end

-- Collects quest rewards for a quest viewed from the quest log as entries
-- (as FormatRewards), or nil if nothing found.
-- Uses quest-log-specific APIs (GetQuestLogRewardMoney, GetQuestLogRewardXP,
-- GetQuestLogRewardInfo) which do NOT rely on the active quest frame globals.
-- Requires C_QuestLog.SetSelectedQuest(questID) to have been called first.
local function FormatQuestLogRewards(questID)
    if not questID or questID == 0 then return nil end
    local lines = {}

    -- Money
    local copper = GetQuestLogRewardMoney and GetQuestLogRewardMoney()
    if copper and copper > 0 then lines[#lines + 1] = { kind = "money", copper = copper } end

    -- XP
    local xp = GetQuestLogRewardXP and GetQuestLogRewardXP()
    if xp and xp > 0 then lines[#lines + 1] = { kind = "xp", n = xp } end

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
                        lines[#lines + 1] = { kind = "text", text = name .. ": " .. amount }
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
                    lines[#lines + 1] = { kind = "text", text = "Item: " .. name }
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
                    lines[#lines + 1] = { kind = "text", text = "Choice: " .. name }
                end
            end
        end
    end

    if #lines == 0 then return nil end
    return lines
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
                local ok2, _, _, _, _, _, itemID = pcall(GetQuestLogRewardInfo, i)
                if ok2 then TryAttach(itemID) end
            end
        end
    end

    -- Choice rewards
    if GetNumQuestLogChoices then
        local ok, numChoices = pcall(GetNumQuestLogChoices, questID)
        if ok and numChoices and numChoices > 0 then
            for i = 1, numChoices do
                local ok2, _, _, _, _, _, itemID = pcall(GetQuestLogChoiceInfo, i)
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
                local ok2, _, tex = pcall(GetQuestLogRewardInfo, i)
                if ok2 and tex then return tostring(tex) end
            end
        end
    end

    if GetNumQuestLogChoices then
        local ok, numChoices = pcall(GetNumQuestLogChoices, questID)
        if ok and numChoices and numChoices > 0 then
            for i = 1, numChoices do
                local ok2, _, tex = pcall(GetQuestLogChoiceInfo, i)
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

-- ── Item-text async page accumulator ─────────────────────────────────────────
-- ItemTextNextPage() is asynchronous: it fires ITEM_TEXT_READY when the new
-- page is ready. We cannot read all pages in a synchronous loop.
-- Strategy: when the button is clicked we start collecting from page 1.
--   • We record which page the reader was on, navigate to page 1, then
--     collect each page as ITEM_TEXT_READY fires.
--   • When there are no more pages we create the note and navigate back to
--     the original page.
--   • A 50-page safety cap prevents runaway loops on unexpectedly large books.
--   • While collecting, the button is temporarily disabled to prevent re-entry.
--   • Closing the book mid-capture cancels it (ITEM_TEXT_CLOSED).

local _itBusy       = false   -- true from the click until the capture ends or is cancelled (BUG-24)
local _itCollecting = false   -- true while ITEM_TEXT_READY pages are being collected
local _itGen        = 0       -- bumped by every start and cancel; stale timers check it
local _itTicker     = nil     -- the page-turning ticker, cancelled with the capture
local _itPages      = {}      -- accumulated page texts
local _itTitle      = ""
local _itTags       = {}
local _itOrigPage   = 1       -- page the reader was on when they clicked
local _itCurrentPage= 0       -- page we have just received
local MAX_PAGES     = 50      -- safety cap

-- ── Capture note layout (ALL-634) ────────────────────────────────────────────
-- Every capture note is put together by CaptureBody, rich or normal (Settings
-- > Modules > Note Capture, one box per kind; Rich Notes module off = normal):
--   Said by <NPC> in <place>             rich: the NPC as a heading, the place under it
--   Accepted <date> - Level 2 - Campaign the info line (QuestInfoLine)
--   Wowhead: <the quest's address>
--   ----------                           rich: a gold divider
--   <the text>
--   Objectives, ----------, Rewards      rich: headings, a divider, coin and XP icons
-- The NPC is an NPC link (Features/NoteLinks.lua), grey until that NPC has a
-- note of its own; the place is a waypoint link (click = waypoint, Alt = map)
-- (Dukul, 2026-11-01).

local DIVIDER    = "{div:gold-plain}"
local PLAIN_RULE = "----------"
local SEP        = " - "
local COIN_ICON  = "{icon:Interface\\MoneyFrame\\UI-%sIcon:13}"   -- Gold / Silver / Copper
local XP_ICON    = "{icon:XP_ICON:16}"

-- kind: "quest" | "book" | "dialogue"
local function RichFor(kind)
    if not (BNB.RichEnabled and BNB.RichEnabled()) then return false end
    local key = (kind == "quest" and "captureRichQuest") or (kind == "book" and "captureRichBook")
             or "captureRichDialogue"
    local db = DB()
    return not db or db[key] ~= false
end

-- tags plus where the player stands (ALL-636): the zone (GetZoneText, the
-- same as the NPC notes' zone tag, so both share it) and, when asked for, the
-- subzone. No continent or world: they would be on nearly every note.
-- Read at click time, before a confirm popup.
local function WithPlaceTags(tags)
    local out = {}
    for i, t in ipairs(tags or {}) do out[i] = t end
    local db = DB()
    local zone = GetZoneText and GetZoneText() or ""
    if (not db or db.captureTagZone ~= false) and zone ~= "" then out[#out + 1] = zone end
    if db and db.captureTagSubZone then
        local sub = GetSubZoneText and GetSubZoneText() or ""
        if sub ~= "" and sub ~= zone then out[#out + 1] = sub end
    end
    return out
end

-- A waypoint link to where the player stands; the zone's name where the map
-- has no position (an instance), nil where there is no map at all
local function PlaceLink()
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return nil end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    local NL = BNB.NoteLinks
    if pos and pos.x and NL and NL.WayLink then
        return NL.WayLink({ mapID = mapID, x = pos.x * 100, y = pos.y * 100 })
    end
    local info = C_Map.GetMapInfo(mapID)
    return info and info.name or nil
end

-- The NPC being talked to: its name and creature id (no id for an object or
-- a player). name / npcID: what the caller already knows (Dialogue UI's text)
local function TalkingNpc(name, npcID)
    if UnitExists("npc") and not UnitIsPlayer("npc") then
        name = name or UnitName("npc")
        if not npcID and BNB.CreatureIDFromGUID then
            local ok, id = pcall(BNB.CreatureIDFromGUID, UnitGUID("npc"))
            if ok then npcID = id end
        end
    end
    if name == "" then name = nil end
    return name, tonumber(npcID)
end

-- Where the quest dialog is, for the info line's first word: the same events
-- reach Blizzard's quest window, Dialogue UI and Immersion
local _questStage
BNB.RegisterEvent("QUEST_DETAIL",   function() _questStage = "accept" end)
BNB.RegisterEvent("QUEST_PROGRESS", function() _questStage = "progress" end)
BNB.RegisterEvent("QUEST_COMPLETE", function() _questStage = "complete" end)
BNB.RegisterEvent("QUEST_FINISHED", function() _questStage = nil end)

-- Enum.QuestClassification names (Retail, Forever) -> locale keys; Normal has none
local QCLASS_KEYS = {
    Important = "QN_QCLASS_IMPORTANT", Legendary = "QN_QCLASS_LEGENDARY", Campaign = "QN_QCLASS_CAMPAIGN",
    Calling = "QN_QCLASS_CALLING", Meta = "QN_QCLASS_META", Recurring = "QN_QCLASS_RECURRING",
    Questline = "QN_QCLASS_QUESTLINE", BonusObjective = "QN_QCLASS_BONUS", Threat = "QN_QCLASS_THREAT",
    WorldQuest = "QN_QCLASS_WORLD",
}
local function QuestClassLabel(questID)
    local QIS, E = C_QuestInfoSystem, Enum and Enum.QuestClassification
    if not (QIS and QIS.GetQuestClassification and E) then return nil end
    local ok, c = pcall(QIS.GetQuestClassification, questID)
    if not ok or c == nil then return nil end
    for name, v in pairs(E) do
        if v == c then return QCLASS_KEYS[name] and BNB.L[QCLASS_KEYS[name]] or nil end
    end
    return nil
end

-- "Accepted <date> - Level 2 - Campaign - Daily - Group (3)". stage: "accept"
-- / "complete" / anything else = Noted. live: the quest dialog is open, so
-- daily / weekly and the group size can be read from it. Level and kind are
-- Retail and Forever only; other clients get the date.
local function QuestInfoLine(questID, stage, live)
    local L = BNB.L
    local word = (stage == "accept" and "QN_INFO_ACCEPTED") or (stage == "complete" and "QN_INFO_TURNED_IN")
              or "QN_INFO_NOTED"
    local parts = { string.format(L[word], BNB.FmtDate()) }
    if questID and questID > 0 then
        if C_QuestLog and C_QuestLog.GetQuestDifficultyLevel then
            local ok, lvl = pcall(C_QuestLog.GetQuestDifficultyLevel, questID)
            if ok and tonumber(lvl) and lvl > 0 then parts[#parts + 1] = string.format(L["QN_INFO_LEVEL"], lvl) end
        end
        local cls = QuestClassLabel(questID)
        if cls then parts[#parts + 1] = cls end
        if C_QuestLog and C_QuestLog.GetQuestTagInfo then
            local ok, tag = pcall(C_QuestLog.GetQuestTagInfo, questID)
            if ok and type(tag) == "table" and type(tag.tagName) == "string" and tag.tagName ~= "" then
                parts[#parts + 1] = tag.tagName
            end
        end
    end
    if live then
        if QuestIsWeekly and QuestIsWeekly() then parts[#parts + 1] = L["QN_INFO_WEEKLY"]
        elseif QuestIsDaily and QuestIsDaily() then parts[#parts + 1] = L["QN_INFO_DAILY"] end
        local size = GetSuggestedGroupSize and GetSuggestedGroupSize()
        if tonumber(size) and size > 1 then parts[#parts + 1] = string.format(L["QN_INFO_GROUP"], size) end
    end
    return table.concat(parts, SEP)
end

-- "Wowhead: <address>": a web link in a rich note (click = the copy box)
local function WowheadLine(questID, rich)
    if not (questID and questID > 0 and BNB.WowheadURL) then return nil end
    local url = BNB.WowheadURL("quest", questID)
    if not url then return nil end
    if rich then
        local shown = url:gsub("^https?://", ""):gsub("^www%.", "")
        return BNB.L["QN_WOWHEAD"] .. ": {link*" .. url .. "*" .. shown .. "}"
    end
    return BNB.L["QN_WOWHEAD"] .. ": " .. url
end

-- 34g 16s 5c; rich: the game's coin pictures after each number
local function MoneyText(copper, rich)
    local out = {}
    local function Add(n, sfx, coin)
        if n > 0 then out[#out + 1] = rich and (n .. string.format(COIN_ICON, coin)) or (n .. sfx) end
    end
    Add(math.floor(copper / 10000), "g", "Gold")
    Add(math.floor((copper % 10000) / 100), "s", "Silver")
    Add(copper % 100, "c", "Copper")
    return table.concat(out, " ")
end

-- The reward entries of FormatRewards / FormatQuestLogRewards as lines
local function RewardLines(entries, rich)
    local L, out = BNB.L, {}
    for _, e in ipairs(entries) do
        if e.kind == "money" then
            out[#out + 1] = rich and MoneyText(e.copper, true) or (L["QN_REW_MONEY"] .. ": " .. MoneyText(e.copper))
        elseif e.kind == "xp" then
            out[#out + 1] = rich and (XP_ICON .. " " .. e.n .. " " .. L["QN_REW_XP"]) or (L["QN_REW_XP"] .. ": " .. e.n)
        elseif e.kind == "honor" then
            out[#out + 1] = L["QN_REW_HONOR"] .. ": " .. e.n
        elseif e.text then
            out[#out + 1] = e.text
        end
    end
    return out
end

-- A page's heading in a book of more than one page
local function PageHeading(i, rich)
    local t = string.format(BNB.L["QN_PAGE_FMT"], i)
    return rich and ("{h3}" .. t .. "{/h3}") or ("--- " .. t .. " ---")
end

-- cap = { rich, npc, npcID, place (true = where the player stands), book
-- (true = "Found in"), info, wowhead, questLink (a heading over the text),
-- quest (true = a quest note's dividers),
-- text, objectives (list), rewards (entries) }
local function CaptureBody(cap)
    local L, rich = BNB.L, cap.rich
    local NL = BNB.NoteLinks
    local npc = cap.npc and ((cap.npcID and NL and NL.NpcLink and NL.NpcLink(cap.npcID, cap.npc)) or cap.npc)
    local place = cap.place and PlaceLink() or nil
    -- In a rich note every line is a paragraph of its own, with space under
    -- it: lines that belong together go in one {p} block (one <P>, <BR/>
    -- between them, AM.ToHTML)
    local function Block(lines)
        local t = table.concat(lines, "\n")
        return rich and ("{p}" .. t .. "{/p}") or t
    end
    local function Heading(t) return rich and ("{h3}" .. t .. "{/h3}") or t end

    local title, head = nil, {}
    if cap.book then
        if place then head[#head + 1] = string.format(L["QN_FOUND_IN_FMT"], place) end
    elseif rich then
        if npc then title = Heading(npc) end
        if place then head[#head + 1] = place end
    elseif npc then
        head[#head + 1] = place and string.format(L["QN_SAID_BY_IN_FMT"], npc, place)
                       or string.format(L["QN_SAID_BY_FMT"], npc)
    elseif place then
        head[#head + 1] = place
    end
    if cap.info then head[#head + 1] = cap.info end
    if cap.wowhead then head[#head + 1] = cap.wowhead end

    local divider = rich and (BNB.DividerTag and BNB.DividerTag("gold-plain") or DIVIDER) or PLAIN_RULE
    local parts = {}
    if title or #head > 0 then
        local top = {}
        if title then top[#top + 1] = title end
        if #head > 0 then top[#top + 1] = Block(head) end
        -- A quest note: the ornate divider under the header, the plain one
        -- over Objectives and Rewards (Dukul's mockup, 2026-11-01)
        top[#top + 1] = (rich and cap.quest and BNB.DividerTag) and BNB.DividerTag("gold-ornate") or divider
        parts[#parts + 1] = table.concat(top, "\n")
    end
    if cap.questLink then parts[#parts + 1] = Heading(cap.questLink) end
    local text = cap.text and cap.text:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if text ~= "" then parts[#parts + 1] = text end
    if cap.objectives then
        local o = {}
        for i, t in ipairs(cap.objectives) do o[i] = "- " .. t end
        parts[#parts + 1] = (rich and cap.quest and (divider .. "\n") or "") .. Heading(L["QN_OBJECTIVES"]) .. "\n" .. Block(o)
    end
    if cap.rewards then
        parts[#parts + 1] = divider .. "\n" .. Heading(L["QN_REWARDS"]) .. "\n" .. Block(RewardLines(cap.rewards, rich))
    end
    -- Every rich capture (quest, book / letter, dialogue) ends on the player's
    -- own Notes part, as the NPC notes do (Dukul, 2026-11-01): the ornate
    -- divider, the heading, an empty line to write on (a bare one: {p}{/p}
    -- offsets the cursor, BuildRichBody)
    if rich and BNB.DividerTag then
        parts[#parts + 1] = BNB.DividerTag("gold-ornate") .. "\n\n{h3}" .. L["TGT_HDR_NOTES"] .. "{/h3}\n"
    end
    return table.concat(parts, "\n\n")
end

-- A quest's link: the game's, else one made from its title (the quest log's,
-- or the open quest window's); nil without a quest id or title
local function QuestLinkFor(questID)
    if not (questID and questID > 0) then return nil end
    local link = GetQuestLink and GetQuestLink(questID)
    if type(link) == "string" and link ~= "" then return link end
    local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)
    if not title or title == "" then title = GetTitleText and GetTitleText() end
    if not title or title == "" then return nil end
    return string.format("|cffffff00|Hquest:%d:0|h[%s]|h|r", questID, title)
end

-- A quest note's whole body, and whether it is rich. questID 0 = no quest id;
-- text = the quest's own words. opts: npc / npcID (what the caller knows;
-- npc = false: none, the quest log), log (read from the quest log), stage
-- ("accept" / "complete", else the last quest event), objectives / rewards
-- / wowhead / questLink (false = leave out)
local function QuestBody(questID, text, opts)
    opts = opts or {}
    local rich = RichFor("quest")
    -- The quest as a link over its text (a heading in a rich note); its
    -- right-click menu copies the Wowhead address, so no Wowhead line then
    -- (Dukul, 2026-11-01: "1. Yes")
    local qlink = opts.questLink ~= false and QuestLinkFor(questID) or nil
    local npc, npcID
    if opts.npc ~= false then npc, npcID = TalkingNpc(opts.npc, opts.npcID) end
    local rewards
    if opts.rewards ~= false and BigNoteBoxDB and BigNoteBoxDB.saveQuestRewards ~= false then
        rewards = opts.log and FormatQuestLogRewards(questID) or FormatRewards(questID)
    end
    return CaptureBody({
        rich = rich, npc = npc, npcID = npcID, place = opts.npc ~= false,
        info = QuestInfoLine(questID, opts.stage or (opts.log and "log") or _questStage, not opts.log),
        wowhead = not qlink and opts.wowhead ~= false and WowheadLine(questID, rich) or nil,
        questLink = qlink, quest = true,
        text = text,
        objectives = opts.objectives ~= false and QuestObjectives(questID) or nil,
        rewards = rewards,
    }), rich
end

-- A dialogue note's body (an object, or Player & NPC Notes off)
local function DialogueBody(npcName, text, npcID)
    local rich = RichFor("dialogue")
    local npc, id = TalkingNpc(npcName, npcID)
    return CaptureBody({ rich = rich, npc = npc, npcID = id, place = true,
        info = BNB.FmtDate(), text = text }), rich
end

-- A book's body: pages = list of page texts (colour codes already stripped)
local function BookBody(pages)
    local rich = RichFor("book")
    local parts = {}
    for i, t in ipairs(pages) do
        parts[i] = (#pages > 1) and (PageHeading(i, rich) .. "\n" .. t) or t
    end
    return CaptureBody({ rich = rich, book = true, place = true, info = BNB.FmtDate(),
        text = table.concat(parts, "\n\n") }), rich
end

local function SetItemTextBtnBusy(busy)
    local btn = _G["BNBQuickNoteItemTextBtn"]
    if btn then btn:SetAlpha(busy and 0.4 or 1); btn:SetEnabled(not busy) end
end

local function StopItemTextTicker()
    if _itTicker then _itTicker:Cancel(); _itTicker = nil end
end

-- Ends the capture, whether it finished or was cancelled.
local function EndItemTextCapture()
    StopItemTextTicker()
    _itBusy, _itCollecting = false, false
    _itPages = {}
    SetItemTextBtnBusy(false)
end

-- ITEM_TEXT_CLOSED: closing the book mid-capture throws the pages away (Dukul,
-- 2026-10-02) and frees the button; it stayed greyed out for the session before.
local function CancelItemTextCapture()
    if not _itBusy then return end
    _itGen = _itGen + 1
    EndItemTextCapture()
end

-- Turns the book back `steps` pages, one per tick (never inside ITEM_TEXT_READY,
-- documented gotcha), then calls onDone. Each PrevPage fires ITEM_TEXT_READY;
-- _itCollecting stays false meanwhile, so the collector ignores those pages.
local function TurnBack(steps, onDone)
    local gen, ticks = _itGen, 0
    StopItemTextTicker()
    _itTicker = C_Timer.NewTicker(0.1, function(ticker)
        if gen ~= _itGen then ticker:Cancel(); return end
        ticks = ticks + 1
        if ticks <= steps and ItemTextPrevPage then
            ItemTextPrevPage()
        else
            ticker:Cancel()
            if _itTicker == ticker then _itTicker = nil end
            onDone()
        end
    end)
end

-- Called once all pages have been gathered.
local function FinishItemTextCapture()
    _itCollecting = false

    -- Colour codes stripped from the pages (not the header: its links keep theirs)
    local pages = {}
    for i, pageText in ipairs(_itPages) do
        pages[i] = pageText:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    end
    local body, rich = BookBody(pages)

    CreateQuickNote(_itTitle, body, RandomIcon(), _itTags, nil, rich)
    _itPages = {}

    -- Navigate back to the original page. We are on the last page; the button
    -- stays busy until the book is back where the reader left it.
    local stepsBack = _itCurrentPage - _itOrigPage
    if stepsBack > 0 then
        TurnBack(stepsBack, EndItemTextCapture)
    else
        EndItemTextCapture()
    end
end

-- Called on each ITEM_TEXT_READY while collecting.
local function OnItemTextReady()
    if not _itCollecting then return end

    local text = ItemTextGetText and ItemTextGetText() or ""
    _itCurrentPage = _itCurrentPage + 1
    _itPages[#_itPages + 1] = text

    local gen = _itGen
    if ItemTextHasNextPage and ItemTextHasNextPage() and _itCurrentPage < MAX_PAGES then
        -- Request next page on the next tick to avoid the documented
        -- synchronisation issue with calling NextPage inside ITEM_TEXT_READY.
        C_Timer.After(0, function()
            if gen == _itGen and ItemTextNextPage then ItemTextNextPage() end
        end)
    else
        -- All pages collected (or cap reached).
        C_Timer.After(0, function()
            if gen == _itGen and _itCollecting then FinishItemTextCapture() end
        end)
    end
end

-- Start collection from whatever page the reader is currently on.
-- We navigate to page 1 first so the note always contains all pages in order.
local function StartItemTextCapture()
    if _itBusy then return end   -- already in progress

    _itGen        = _itGen + 1
    _itBusy       = true
    _itTitle      = ItemTextGetItem and ItemTextGetItem() or ""
    _itTags       = WithPlaceTags(ItemTextTags())   -- ALL-636: where it was read
    _itPages      = {}
    _itCurrentPage= 0
    SetItemTextBtnBusy(true)   -- prevent re-entry

    -- Figure out current page number: ItemTextGetPage() returns the current page.
    _itOrigPage = (ItemTextGetPage and ItemTextGetPage()) or 1

    -- Collect from page 1. ITEM_TEXT_READY will not fire again for the page
    -- already shown, so the first page is read directly.
    local gen = _itGen
    local function BeginCollecting()
        _itCurrentPage = 0
        _itCollecting  = true
        C_Timer.After(0, function()
            if gen == _itGen then OnItemTextReady() end
        end)
    end
    if _itOrigPage > 1 then
        TurnBack(_itOrigPage - 1, BeginCollecting)
    else
        BeginCollecting()
    end
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

        local title, body, icon, rich
        local questID = GetQuestID and GetQuestID() or 0

        -- The quest frame's panels are QuestFrameDetailPanel and
        -- QuestFrameRewardPanel on every client (the API dumps); the old
        -- QuestDetailFrame / QuestRewardFrame names are gone (DEP-05).
        local detailShown = QuestFrameDetailPanel and QuestFrameDetailPanel:IsShown()
        local rewardShown = QuestFrameRewardPanel and QuestFrameRewardPanel:IsShown()

        if detailShown then
            -- Quest accept frame
            local text
            title, text = QuestDetailText()
            body, rich  = QuestBody(questID, text, { stage = "accept" })
            icon        = QuestFrameIcon()
        elseif rewardShown then
            -- Quest turn-in frame: no objectives, they are done
            local text
            title, text = QuestCompleteText()
            body, rich  = QuestBody(questID, text, { stage = "complete", objectives = false })
            icon        = QuestFrameIcon()
        else
            -- Fallback: grab whatever text is in the frame
            title = GetTitleText() or "Quest"
            body, rich = QuestBody(questID, GetQuestText() or GetRewardText() or "",
                { objectives = false, rewards = false })
            icon  = RandomIcon()
        end
        local rewardFn = function(noteID)
            AttachQuestID(noteID, questID)
            AttachQuestRewards(noteID)
        end

        CreateQuickNote(title, body, icon, WithPlaceTags({ "Quest" }), rewardFn, rich)
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
    if not IsEnabled() then _qlBtn:Hide(); return end   -- module off (ALL-380)
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
    -- Classic Era and Anniversary have the old QuestLogFrame and none of these
    -- hooks (ALL-169): no quest-log button there. MoP Classic has hooks 1 and 2.
    local hasTitleHook = type(QuestMapLogTitleButton_OnClick) == "function"
    local hasDetailsHook = type(QuestMapFrame_ShowQuestDetails) == "function"
    if not hasTitleHook and not hasDetailsHook then return end
    -- Create one button, parented initially to UIParent (hidden).
    -- PositionQuestLogBtn() reparents it on each hook call.
    local btn = BNB.CreateIconButton(UIParent, QN_SZ, "createnote", {
        name = "BNBQuickNoteQuestLogBtn", skin = false,
        tip = BNB.L["QN_BTN_TIP1"], tipSub = BNB.L["QN_BTN_TIP2_QUEST"], tipAnchor = "ANCHOR_BOTTOMRIGHT" })
    btn:SetFrameStrata("HIGH")
    btn:SetFrameLevel(100)
    btn:Hide()

    btn:SetScript("OnClick", function()
        if not IsEnabled() then return end

        local questID = _questLogSelectedID or 0
        if questID == 0 then
            BNB:Print("|cffff6666" .. BNB.L["QN_NO_QUEST"] .. "|r")
            return
        end

        -- QuestLogText calls SetSelectedQuest internally, which primes all
        -- quest-log APIs (GetQuestLogQuestText, GetQuestLogRewardMoney, etc.).
        -- The player's own selection is put back afterwards (DEP-04).
        local prevSel = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
        local title, text = QuestLogText(questID)
        -- No NPC and no place: the log is read anywhere (ALL-634)
        local body, rich = QuestBody(questID, text, { npc = false, log = true })

        local icon = QuestLogIcon(questID)
        RestoreQuestSelection(prevSel, questID)
        local rewardFn = function(noteID)
            AttachQuestID(noteID, questID)
            -- Runs later (after the note exists): select the quest again for
            -- the index-based reward reads, then put the selection back
            local prev = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
            if C_QuestLog.SetSelectedQuest then C_QuestLog.SetSelectedQuest(questID) end
            AttachQuestLogRewards(noteID, questID)
            RestoreQuestSelection(prev, questID)
        end
        CreateQuickNote(title, body, icon, { "Quest" }, rewardFn, rich)
    end)

    _qlBtn = btn

    -- Hook 1: quest title clicked in the log list
    if hasTitleHook then
        hooksecurefunc("QuestMapLogTitleButton_OnClick", function(self)
            if self and self.questID then
                _questLogSelectedID = self.questID
            end
            PositionQuestLogBtn()
        end)
    end

    -- Hook 2: quest details shown via map frame (e.g. clicking from world map)
    if hasDetailsHook then
        hooksecurefunc("QuestMapFrame_ShowQuestDetails", function(questID)
            if questID and questID > 0 then
                _questLogSelectedID = questID
            end
            PositionQuestLogBtn()
        end)
    end

    -- Hook 3: popup detail frame shown
    -- QuestLogPopupDetailFrame.questID is populated by Blizzard before this fires
    -- Retail only: Forever has hooks 1 and 2 but not this function (FOR-02).
    if type(QuestLogPopupDetailFrame_Show) == "function" then
        hooksecurefunc("QuestLogPopupDetailFrame_Show", function()
            if QuestLogPopupDetailFrame and QuestLogPopupDetailFrame.questID then
                _questLogSelectedID = QuestLogPopupDetailFrame.questID
            end
            PositionQuestLogBtn()
        end)
    end
end

-- Plain talk (gossip, not a quest) goes into the NPC's own note, the one F6
-- makes (BNB.TargetNote.AddDialogue, ALL-631); where that cannot be (Player &
-- NPC Notes off, an object), a "<name> (Dialogue)" note of its own
-- npcID: Dialogue UI's, when it gave one
local function SaveDialogue(npcName, text, npcID)
    local TN = BNB.TargetNote
    local id, title
    if TN and TN.AddDialogue then id, title = TN.AddDialogue(text, GetAction() == "open") end
    if id then
        BNB:Print(string.format(BNB.L["QN_DIALOGUE_ADDED"], title or npcName or ""))
        return
    end
    -- GossipText's stand-in names ("NPC: 1234") are a title, not a speaker
    local speaker = npcName and not npcName:find("^NPC[: ]") and npcName or nil
    local body, rich = DialogueBody(speaker, text or "", npcID)
    CreateQuickNote(DialogueTitle(npcName or UnitName("npc") or "NPC"), body, RandomIcon(), WithPlaceTags({ "Gossip" }), nil, rich)
end

local function InjectGossipFrame()
    if not GossipFrame then return end

    MakeButton("BNBQuickNoteGossipBtn", GossipFrame, function()
        if not IsEnabled() then return end
        local title, body = GossipText()
        SaveDialogue(title, body)
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

-- On Immersion's text box, hanging over its top-left corner as the icon badge
-- does on a sticky note (Dukul, 2026-10-31). Shift+drag moves it; the spot is
-- kept as an offset from that corner, so it follows the box wherever Immersion
-- puts it. quickNoteImmersionOffX/Y: nil = on the corner.
local IMM_BTN_SZ    = 36
local IMM_BTN_INSET = 6
-- Dukul's art, three states (a missing file draws a green square)
local IMM_TEX = {
    normal = ASSETS .. "UI\\ui-immersion-note",
    hover  = ASSETS .. "UI\\ui-immersion-note-hover",
    press  = ASSETS .. "UI\\ui-immersion-note-press",
}

local function ImmersionBox()
    local imm = _G["ImmersionFrame"]
    local tb = imm and imm.TalkBox
    return tb and (tb.MainFrame or tb)
end

-- Puts the button on the box's corner plus the saved offset
local function AnchorImmersionBtn()
    local btn, box = _immersionBtn, ImmersionBox()
    if not btn or not box then return end
    local db = DB()
    local ox = (db and db.quickNoteImmersionOffX) or 0
    local oy = (db and db.quickNoteImmersionOffY) or 0
    btn:ClearAllPoints()
    btn:SetPoint("TOPLEFT", box, "TOPLEFT", -IMM_BTN_INSET + ox, IMM_BTN_INSET + oy)
end

-- After a Shift+drag: the offset from the box's corner, in the button's own
-- units (Immersion can scale its frame, so both go through screen pixels)
local function SaveImmersionPos()
    local btn, box = _immersionBtn, ImmersionBox()
    if not btn or not box or not DB() then return end
    local bl, bt = btn:GetLeft(), btn:GetTop()
    local xl, xt = box:GetLeft(), box:GetTop()
    if not (bl and bt and xl and xt) then return end
    local bs, xs = btn:GetEffectiveScale(), box:GetEffectiveScale()
    local ox = (bl * bs - xl * xs) / bs + IMM_BTN_INSET
    local oy = (bt * bs - xt * xs) / bs - IMM_BTN_INSET
    DB().quickNoteImmersionOffX = ox
    DB().quickNoteImmersionOffY = oy
    if BNB._debugImmersionPos then
        BNB:Print(string.format(
            "|cff88bbff[BNB Immersion] Saved offset from the box corner: X=%.1f Y=%.1f|r", ox, oy))
    end
end

-- Called from Settings "Reset button position": back on the corner
function BNB.ResetImmersionBtnPos()
    if DB() then
        DB().quickNoteImmersionOffX = nil
        DB().quickNoteImmersionOffY = nil
        -- Screen positions from before the button was attached to the box
        DB().quickNoteImmersionX = nil
        DB().quickNoteImmersionY = nil
    end
    AnchorImmersionBtn()
end

local function BuildImmersionButton()
    if _immersionBtn then return end

    local btn = CreateFrame("Button", "BNBQuickNoteImmersionBtn", UIParent)
    btn:SetSize(IMM_BTN_SZ, IMM_BTN_SZ)
    btn:SetFrameStrata("DIALOG")   -- over Immersion's box (HIGH)
    btn:SetMovable(true)
    btn:EnableMouse(true)
    btn:RegisterForDrag("LeftButton")
    btn:SetClampedToScreen(true)
    -- Immersion fades UIParent alpha to 0 when active — ignore that so we stay visible.
    btn:SetIgnoreParentAlpha(true)
    btn:Hide()
    _immersionBtn = btn
    AnchorImmersionBtn()

    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(btn)
    tex:SetTexture(IMM_TEX.normal)
    local function SetState(state) tex:SetTexture(IMM_TEX[state]) end

    -- Shift+drag to reposition; plain drag does nothing so click still works cleanly
    btn:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() then
            self:StartMoving()
        end
    end)
    btn:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self:SetUserPlaced(false)   -- the client must not keep it at a screen spot
        SaveImmersionPos()
        AnchorImmersionBtn()
    end)

    btn:SetScript("OnEnter", function(self)
        SetState("hover")
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:AddLine(BNB.L["QN_BTN_TIP1"], 1, 1, 1)
        GameTooltip:AddLine(BNB.L["QN_BTN_TIP2_IMM"], 0.78, 0.78, 0.78)
        GameTooltip:AddLine(BNB.L["QN_BTN_TIP_DRAG"], 0.55, 0.55, 0.55)
        -- Ctrl+click line only once it has been moved off the corner
        local db = DB()
        if db and (db.quickNoteImmersionOffX or db.quickNoteImmersionOffY) then
            GameTooltip:AddLine(BNB.L["QN_BTN_TIP_RESET_IMM"], 0.55, 0.55, 0.55)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        SetState("normal")
        GameTooltip:Hide()
    end)

    btn:SetScript("OnMouseDown", function()
        SetState("press")
    end)
    btn:SetScript("OnMouseUp", function(self)
        SetState(self:IsMouseOver() and "hover" or "normal")
    end)

    btn:SetScript("OnClick", function(self)
        -- Ctrl+click: back on the corner of the box (Dukul, 2026-10-31)
        if IsControlKeyDown() then
            BNB.ResetImmersionBtnPos()
            if self:IsMouseOver() then self:GetScript("OnEnter")(self)
            else self:GetScript("OnLeave")(self) end
            return
        end
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
        local body = (immBody and immBody ~= "") and immBody
                  or GetQuestText()
                  or (C_GossipInfo and C_GossipInfo.GetText and C_GossipInfo.GetText())
                  or GetRewardText()
                  or ""
        local questID = GetQuestID and GetQuestID() or 0
        local npcName = (immTitle and immTitle ~= "") and immTitle or nil
        -- Plain talk: into the NPC's own note (ALL-631)
        if questID <= 0 then
            SaveDialogue(npcName, body)
            return
        end
        -- A quest: its own note, titled with the quest (Immersion's name
        -- line shows the NPC)
        local questTitle = GetTitleText()
        local title = (questTitle and questTitle ~= "") and questTitle
                   or DialogueTitle(npcName or UnitName("npc") or "NPC")
        local rewardFn = function(noteID)
            AttachQuestID(noteID, questID)
            AttachQuestRewards(noteID)
        end
        -- At the turn-in the objectives are done: left out, as on the quest window
        local noteBody, rich = QuestBody(questID, body,
            { npc = npcName, objectives = _questStage ~= "complete" })
        CreateQuickNote(title, noteBody, RandomIcon(), WithPlaceTags({ "Quest" }), rewardFn, rich)
        BNB:Print(string.format(BNB.L["QN_NOTE_CREATED"], title or ""))
    end)
end

-- Show/hide the Immersion floating button based on ImmersionFrame visibility
local function SyncImmersionBtn()
    if not _immersionBtn then return end
    local imm = _G["ImmersionFrame"]
    local btnEnabled = DB() and DB().quickNoteImmersionBtn ~= false
    if imm and imm:IsShown() and IsEnabled() and btnEnabled then
        AnchorImmersionBtn()
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

local function ImmersionBypassEnd()
    if not _immBypass then return end
    _immBypass = false
    local imm = _G["ImmersionFrame"]
    if not imm then return end
    for _, ev in ipairs(IMM_EVENTS) do
        imm:RegisterEvent(ev)
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
local _duiQuestTitle = nil   -- cached GetTitleText() for it (the note's title)
local _duiMoney, _duiXP = nil, nil   -- the quest's money / XP reward, to find those lines (DUILinks)

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
    _duiQuestTitle = _duiQuestID and GetTitleText and GetTitleText() or nil
    if _duiQuestTitle == "" then _duiQuestTitle = nil end
    _duiMoney = _duiQuestID and GetRewardMoney and tonumber(GetRewardMoney()) or nil
    _duiXP    = _duiQuestID and GetRewardXP and tonumber(GetRewardXP()) or nil
end

-- Dialogue UI's Copy Text writes ids in brackets ("[Quest: 24469] Hold the
-- Line!", "[ItemID: 131895] Ironstock's Iron Grips x2"): game links instead,
-- and in a rich note the reward's icon in front; its money line (all in
-- copper, "55 Copper" in DUI's own language) and XP line get the coin / XP
-- pictures (Dukul, 2026-11-01). Money and XP are found by the quest's own
-- numbers, so any language works. Formats: DialogueUI.lua Clipboard block,
-- UITemplates.lua GetClipboardOutput.
-- Dialogue UI's section words: the game's OBJECTIVES_LABEL / REWARDS in most
-- of its languages, its own in the rest (its Locales folder: English, French,
-- Spanish, German, Russian, Korean, Chinese), as UTF-8 bytes
local DUI_HEADS = {}
for _, w in ipairs({ "Objectives", "Objectifs", "Objetivos", "Ziele", "Rewards", "Belohnungen", "Recompensas", "R\195\169compenses", "\208\151\208\176\208\180\208\176\209\135\208\184", "\235\170\169\237\145\156", "\228\187\187\229\138\161\231\155\174\230\160\135", "\208\157\208\176\208\179\209\128\208\176\208\180\209\139", "\235\179\180\236\131\129\235\147\164", "\229\165\150\229\138\177" }) do DUI_HEADS[w] = true end
if type(OBJECTIVES_LABEL) == "string" then DUI_HEADS[OBJECTIVES_LABEL] = true end
if type(REWARDS) == "string" then DUI_HEADS[REWARDS] = true end
local function DUIIcon(tex, rich)
    return (rich and tex) and ("{icon:" .. tostring(tex) .. ":16} ") or ""
end
local function DUILine(line, rich)
    local id, rest = line:match("^%[Quest:%s*(%d+)%]%s*(.*)$")
    if id then
        id = tonumber(id)
        local link = GetQuestLink and GetQuestLink(id)
        link = (type(link) == "string" and link ~= "") and link
            or string.format("|cffffff00|Hquest:%d:0|h[%s]|h|r", id, rest)
        return rich and ("{h3}" .. link .. "{/h3}") or link   -- the title heading (Dukul, 2026-11-01)
    end
    if rich and DUI_HEADS[(line:gsub("^%s+", ""):gsub("%s+$", ""))] then
        return BNB.DividerTag("gold-plain") .. "\n\n{h3}" .. (line:gsub("^%s+", ""):gsub("%s+$", "")) .. "{/h3}"
    end
    id, rest = line:match("^%[ItemID:%s*(%d+)%]%s*(.*)$")
    if id then
        id = tonumber(id)
        local name, count = rest:match("^(.-)%s+(x%d+)$")
        name = name or rest
        local link = select(2, C_Item.GetItemInfo(id)) or ("|cffffffff|Hitem:" .. id .. "|h[" .. name .. "]|h|r")
        local tex = ItemIcon(id) or (C_Item.GetItemIconByID and C_Item.GetItemIconByID(id))
        return DUIIcon(tex, rich) .. link .. (count and (" " .. count) or "")
    end
    id, rest = line:match("^%[SpellID:%s*(%d+)%]%s*(.*)$")
    if id then
        id = tonumber(id)
        local link = C_Spell and C_Spell.GetSpellLink and C_Spell.GetSpellLink(id)
        local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
        return DUIIcon(tex, rich) .. (link or rest)
    end
    id, rest = line:match("^%[CurrencyID:%s*(%d+)%]%s*(.*)$")
    if id then
        id = tonumber(id)
        local name, amount = rest:match("^(.-)%s+(%d+)$")
        local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(id)
        local link = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyLink
            and C_CurrencyInfo.GetCurrencyLink(id, tonumber(amount) or 0)
        return DUIIcon(info and info.iconFileID, rich) .. (amount and (amount .. " ") or "") .. (link or name or rest)
    end
    rest = line:match("^%[FactionID:%s*%d+%]%s*(.*)$")
    if rest then return rest end
    if _duiMoney and _duiMoney > 0 then
        local n = line:match("^(%d+)%s*%D+$")
        if tonumber(n) == _duiMoney then
            return rich and MoneyText(_duiMoney, true) or (BNB.L["QN_REW_MONEY"] .. ": " .. MoneyText(_duiMoney))
        end
    end
    if rich and _duiXP and _duiXP > 0 and line:find("^" .. _duiXP .. " XP") then
        return XP_ICON .. " " .. line
    end
    return line
end
local function DUILinks(text, rich)
    local out = {}
    for line in (text:gsub("\r", "") .. "\n"):gmatch("(.-)\n") do
        local ok, conv = pcall(DUILine, line, rich)
        out[#out + 1] = ok and conv or line
    end
    return table.concat(out, "\n")
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
    -- Strip leading "[NPC: XXXX] " and split into title / body; the id is
    -- the NPC link's (ALL-634)
    local npcID, npcName, body = raw:match("^%[NPC:%s*(%d+)%]%s*(.-)%s*\n(.+)$")
    if npcName then
        return npcName, body, tonumber(npcID)
    end
    return UnitName("npc") or "NPC", raw
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
local _duiForceNote = false  -- true while our own button clicks DUI's (note even with duiAutoNote off)
local _duiBookHooked = false -- true once DUI's book Copy Text button is hooked

local function OnDUIDialogueCopy()
    if not DB() or not (DB().duiAutoNote or _duiForceNote) then return end
    if not IsEnabled() then return end
    local npcName, body, npcID = GetDUIText()
    if not npcName or not body or body:match("^%s*$") then return end
    local qid = _duiQuestID
    if not qid then
        -- Plain talk: into the NPC's own note (ALL-631); links only, the
        -- note may be a plain one
        SaveDialogue(npcName, DUILinks(body, false), npcID)
        return
    end
    -- A quest: its own note, titled with the quest
    local rewardFn = function(noteID)
        AttachQuestID(noteID, qid)
        AttachQuestRewards(noteID)
    end
    -- Dialogue UI's text already holds the objectives and rewards: only the
    -- header block is ours (ALL-634). Its first line is now the quest link,
    -- whose right-click menu copies the Wowhead address: no Wowhead line
    -- (Dukul, 2026-11-01)
    local noteBody, rich = QuestBody(qid, DUILinks(body, RichFor("quest")), { npc = npcName, npcID = npcID,
        objectives = false, rewards = false, wowhead = false, questLink = false })
    CreateQuickNote(_duiQuestTitle or DialogueTitle(npcName), noteBody, RandomIcon(), WithPlaceTags({ "Quest" }), rewardFn, rich)
end

local function OnDUIBookCopy()
    if not DB() or not (DB().duiAutoNote or _duiForceNote) then return end
    if not IsEnabled() then return end
    local bookFrame = _G["DUIBookFrame"]
    if not bookFrame or not bookFrame:IsShown() then return end

    local title = (bookFrame.Header and bookFrame.Header.Title
                    and bookFrame.Header.Title:GetText())
               or (ItemTextGetItem and ItemTextGetItem())
               or "Book"

    -- Pages from our accumulated page cache, colour codes stripped
    local pages = {}
    local numPages = 0
    for _ in pairs(_duiBookPages) do numPages = numPages + 1 end
    for i = 1, numPages do
        pages[i] = (_duiBookPages[i] or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    end

    if table.concat(pages) == "" then
        local text = ItemTextGetText and ItemTextGetText() or ""
        pages = { (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) }
    end

    local body, rich = BookBody(pages)
    CreateQuickNote(title, body, RandomIcon(), WithPlaceTags({ "Book" }), nil, rich)
end

-- ── DUI: our note button beside DUI's Copy Text buttons ─────────────────────
-- Beside the Copy Text button of DUIQuestFrame (on its left) and DUIBookFrame
-- (on its right: the book's sits in the top-left corner), same size, no gap,
-- so the two read as one wider button (Dukul, 2026-10-31). Drawn as DUI draws
-- its own icon: one colour per DUI theme at 60 % alpha, full on hover. A click
-- clicks DUI's button (the copy box opens as usual) and always makes a note,
-- even with duiAutoNote off. Parented to DUI's button, so it shows, hides and
-- fades with it. duiNoteBtn = false hides it (Settings > Modules > Note Capture).
local DUI_BTN_SZ   = 24   -- DUI's BUTTON_SIZE (Clipboard.lua)
local DUI_ICON_SZ  = 18   -- DUI's ICON_SIZE is 16; the quill makes ours look smaller
local DUI_ICON_DIM = 0.6  -- DUI's ALPHA_UNFOCUSED
-- Two layers in white, both made from Dukul's ui-dialogueui-normal (kept in
-- _work/backups/dialogueui-art with his hover / press art) and tinted
-- per theme: the line (a little bolder than the source) and the soft edge
-- around it, which DUI's icon has (light on the light themes, dark on the dark)
local DUI_TEX      = ASSETS .. "UI\\ui-dialogueui-mask"
local DUI_TEX_EDGE = ASSETS .. "UI\\ui-dialogueui-glow"
-- DUI's own icon in each theme (CopyTextButton.png, one 1/8 slot each):
-- { line r, g, b, edge r, g, b }
local DUI_THEME_RGB = {
    [1] = { 84, 54, 26,    231, 223, 195 },   -- Brown
    [2] = { 143, 143, 143, 64, 64, 64 },      -- Dark
    [3] = { 132, 86, 48,   234, 224, 196 },
    [4] = { 128, 128, 128, 38, 38, 38 },
}
local _duiNoteBtns = {}   -- [DUI's copy button] = ours

local function DUIBtnWanted()
    return IsEnabled() and DB() and DB().duiNoteBtn ~= false and true or false
end

-- DUI puts its Translator button 4 px left of the quest Copy Text button
-- (LayoutTopWidgets): move it left of ours while ours shows
local function AnchorDUITranslator()
    local qf = _G["DUIQuestFrame"]
    local copy = qf and qf.CopyTextButton
    local tr = qf and qf.TranslatorButton
    if not (copy and tr and tr:IsShown() and copy:IsShown()) then return end
    local ours = _duiNoteBtns[copy]
    tr:ClearAllPoints()
    if ours and ours:IsShown() then
        tr:SetPoint("RIGHT", ours, "LEFT", -4, 0)
    else
        tr:SetPoint("RIGHT", copy, "LEFT", -4, 0)
    end
end

local function SyncDUINoteBtns()
    local want = DUIBtnWanted()
    for _, btn in pairs(_duiNoteBtns) do btn:SetShown(want) end
    AnchorDUITranslator()
end
BNB.SyncDUINoteBtns = SyncDUINoteBtns

-- side "LEFT" = ours on the left of DUI's button, "RIGHT" = on its right
local function AddDUINoteBtn(copy, side)
    if not copy or _duiNoteBtns[copy] then return end

    local btn = CreateFrame("Button", nil, copy)
    btn:SetSize(DUI_BTN_SZ, DUI_BTN_SZ)
    if side == "LEFT" then
        btn:SetPoint("RIGHT", copy, "LEFT", 0, 0)
    else
        btn:SetPoint("LEFT", copy, "RIGHT", 0, 0)
    end
    btn:SetFrameLevel(copy:GetFrameLevel() + 1)
    _duiNoteBtns[copy] = btn

    local tex = btn:CreateTexture(nil, "OVERLAY")
    tex:SetSize(DUI_ICON_SZ, DUI_ICON_SZ)
    tex:SetPoint("CENTER")
    tex:SetTexture(DUI_TEX)
    local edge = btn:CreateTexture(nil, "ARTWORK")
    edge:SetAllPoints(tex)   -- follows the line, press sink included
    edge:SetTexture(DUI_TEX_EDGE)
    local function SetIconAlpha(a)
        tex:SetAlpha(a)
        edge:SetAlpha(a)
    end
    SetIconAlpha(DUI_ICON_DIM)

    local function SetTheme(themeID)
        local c = DUI_THEME_RGB[themeID] or DUI_THEME_RGB[1]
        tex:SetVertexColor(c[1] / 255, c[2] / 255, c[3] / 255)
        edge:SetVertexColor(c[4] / 255, c[5] / 255, c[6] / 255)
    end
    -- The theme DUI's icon shows now: its tex coord starts at 0.125 * (theme - 1)
    local left = copy.Icon and copy.Icon:GetTexCoord()
    SetTheme(left and (math.floor(left / 0.125 + 0.5) + 1) or 1)
    if copy.SetTheme then
        hooksecurefunc(copy, "SetTheme", function(_, themeID) SetTheme(themeID or 1) end)
    end

    -- One button: hovering either half lights both
    local function Lit(on)
        SetIconAlpha(on and 1 or DUI_ICON_DIM)
        if copy.Icon then copy.Icon:SetAlpha(on and 1 or DUI_ICON_DIM) end
    end
    -- Tooltip: DUI hides UIParent, and GameTooltip with it, so ours goes
    -- through DUI's own button functions and its tooltip (they read
    -- self.Icon and self.tooltipText), the same look as its Copy Text tip
    btn.Icon = tex
    btn.tooltipText = BNB.L["QN_BTN_TIP_DUI"]
    btn:SetScript("OnEnter", function(self)
        if copy.OnEnter then pcall(copy.OnEnter, self) end
        Lit(true)
    end)
    btn:SetScript("OnLeave", function(self)
        if copy.OnLeave then pcall(copy.OnLeave, self) end
        if not copy:IsMouseOver() then Lit(false) end
    end)
    -- Pressed: the icon sinks a pixel
    btn:SetScript("OnMouseDown", function()
        tex:SetPoint("CENTER", 1, -1)
    end)
    btn:SetScript("OnMouseUp", function()
        tex:SetPoint("CENTER", 0, 0)
    end)
    copy:HookScript("OnEnter", function() SetIconAlpha(1) end)
    copy:HookScript("OnLeave", function()
        if not btn:IsMouseOver() then SetIconAlpha(DUI_ICON_DIM) end
    end)

    btn:SetScript("OnClick", function()
        if not IsEnabled() then return end
        _duiForceNote = true
        pcall(copy.Click, copy)
        _duiForceNote = false
    end)

    btn:SetShown(DUIBtnWanted())
end

-- DUI makes each Copy Text button only while its own setting is on, so this
-- runs again on every dialogue / book open
local _duiLayoutHooked = false
local function BuildDUINoteBtns()
    local qf = _G["DUIQuestFrame"]
    if qf and qf.CopyTextButton then
        AddDUINoteBtn(qf.CopyTextButton, "LEFT")
        if not _duiLayoutHooked and qf.LayoutTopWidgets then
            _duiLayoutHooked = true
            hooksecurefunc(qf, "LayoutTopWidgets", AnchorDUITranslator)
        end
    end
    local bf = _G["DUIBookFrame"]
    if bf and bf.CopyTextButton then
        AddDUINoteBtn(bf.CopyTextButton, "RIGHT")
    end
    SyncDUINoteBtns()
end

function BNB.ApplyDUIAutoNote()
    BuildDUINoteBtns()
    if _duiHooked then return end

    local questFrame = _G["DUIQuestFrame"]
    if questFrame and questFrame.SendContentToClipboard then
        hooksecurefunc(questFrame, "SendContentToClipboard", OnDUIDialogueCopy)
        _duiHooked = true
    end

    local function HookBookCopyBtn(bf)
        if _duiBookHooked then return end
        _duiBookHooked = true
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
            BuildDUINoteBtns()
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
            local gen = _itGen
            C_Timer.After(0, function()
                if gen == _itGen then OnItemTextReady() end
            end)
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
            C_Timer.After(0, BuildDUINoteBtns)
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
        _duiQuestTitle = nil
        _duiMoney, _duiXP = nil, nil
        _duiBookPages = {}   -- clear stale book page cache
        if event == "ITEM_TEXT_CLOSED" then CancelItemTextCapture() end
        ImmersionBypassEnd()
        return
    end
end)

-- Also hook ImmersionFrame OnShow/OnHide if it exists at login time
-- (Immersion may load after PLAYER_LOGIN if it's an optional dep)
local _immHooked   -- our own flag, not a field on another addon's frame (GLB-04)
local function HookImmersionFrame()
    local imm = _G["ImmersionFrame"]
    if not imm or _immHooked then return end
    _immHooked = true
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
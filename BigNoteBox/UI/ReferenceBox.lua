-- BigNoteBox UI/ReferenceBox.lua — Reference Box side panel
--
-- Anchors to the RIGHT of BNB.mainFrame, same height.
-- Shows item/spell attachments for the currently selected note.
-- Toggled from the editor bottom toolbar (right of Save button).
--
-- Input methods:
--   • Drag & drop (items, spells) onto the panel
--   • Shift-click any item/spell (Baganator-safe via hooksecurefunc)
--   • Manual entry: bare number = itemID, i:N or item:N = item, s:N or spell:N = spell
--
-- Public API:
--   BNB.ToggleReferenceBox()
--   BNB.OpenReferenceBox(noteID)
--   BNB.CloseReferenceBox()
--   BNB.SyncReferenceBox(noteID)   -- called by SelectNote; auto-opens if configured
--   BNB.RefreshReferenceBox()

local BNB = BigNoteBox
local L   = BNB.L

-- ── Constants ─────────────────────────────────────────────────────────────────
local RBW        = 290       -- wider to keep content width after scrollbar clearance
local TITLE_H    = 32        -- ButtonFrameTemplate title area
local PAD        = 10        -- outer padding between frame edges and cards
local SCROLL_PAD = 22        -- right clearance for ScrollFrameTemplate scrollbar
local CARD_PAD   = 6         -- icon left inset inside a card
local ROW_H_NORM = 52
local ROW_H_COMP = 28
local ROW_GAP    = 4
local ICON_SZ_N  = 32
local ICON_SZ_C  = 16
local MANUAL_H   = 28
local MANUAL_GAP = 4
local COUNT_H    = 20
local BOTTOM_PAD = 4

local ASSETS = "Interface\\AddOns\\BigNoteBox\\Assets\\"

-- ── Model viewer constants (inspect notes only) ──────────────────────────────
local MODEL_SPLIT_DEFAULT = 0.30   -- items get 30%, model gets 70% of scroll area
local MODEL_SPLIT_MIN_PX  = 60     -- minimum item area height in px
local MODEL_MIN_H         = 150    -- minimum model frame height in px

-- ── Skin-mode title height (must be file-scoped for ApplyTaskLayout/splitter) ─
local SK_RB_TITLE_H         = 28

-- ── Task panel constants ──────────────────────────────────────────────────────
local TASK_HDR_H            = 24     -- height of the task panel header row
local TASK_ROW_H            = 24     -- height of each task row
local TASK_SUBROW_H         = 22     -- height of sub-task rows
local TASK_SPLIT_MIN_PX     = 60     -- minimum px for either task or attachment pane
local TASK_CB_SCALE         = 0.65   -- UICheckButtonTemplate scale ~17px
local ADD_TASKS_H           = 40     -- reserved strip height for the wide Add Tasks button

local QUALITY_COLORS = {
    [0]={r=0.62,g=0.62,b=0.62}, [1]={r=1.00,g=1.00,b=1.00},
    [2]={r=0.12,g=1.00,b=0.00}, [3]={r=0.00,g=0.44,b=0.87},
    [4]={r=0.64,g=0.21,b=0.93}, [5]={r=1.00,g=0.50,b=0.00},
    [6]={r=0.90,g=0.80,b=0.50}, [7]={r=0.00,g=0.80,b=1.00},
}
local function QualityColor(q) return QUALITY_COLORS[q or 1] or QUALITY_COLORS[1] end

-- ── Module state ──────────────────────────────────────────────────────────────
local rbFrame       = nil
local _noteID       = nil
local _rowPool      = {}
local _activeRows   = {}
local _pendingItems  = {}   -- itemID  → true
local _pendingSpells = {}   -- spellID → true
local _pendingQuests = {}   -- questID → true
local _modelHidden   = {}   -- noteID  → true (session-only, resets on /reload)
local _gearViewTmog  = {}   -- noteID  → true = showing transmog, false/nil = regular

-- ── Task panel state ──────────────────────────────────────────────────────────
-- "attachments" = show attachments pane (default when no tasks)
-- "model"       = show model viewer (option C toggle, inspect notes only)
local _rbMode        = "attachments"
local _taskRows      = {}   -- pool of task row frames
local _taskCallbackRegistered = false  -- ensures TasksChanged callback is registered once

local RenderList               -- forward declaration
local SyncRefBoxHeight         -- forward declaration (defined near PositionFrame)
local EnsureSpellDataListener  -- forward declaration (defined after EnsureItemInfoListener)
local EnsureQuestDataListener  -- forward declaration
local GetQuestTitle            -- forward declaration
local UpdateModelViewer        -- forward declaration
local BuildModelViewer         -- forward declaration
local ApplyModelLayout         -- forward declaration
local RenderTaskPanel          -- forward declaration
local ApplyTaskLayout          -- forward declaration
local UpdateDynamicTitle       -- forward declaration
local UpdateModeStrip          -- forward declaration
local RegisterTaskCallback     -- forward declaration

-- ── DB helpers ────────────────────────────────────────────────────────────────
local function DB()  return BigNoteBoxDB     end
local function NDB() return BigNoteBoxNotesDB end

local function GetAttachments(id)
    local note = id and NDB() and NDB().notes and NDB().notes[id]
    return note and note.attachments or nil
end
local function GetMaxItems() return DB().refboxMaxItems or 20 end
local function IsCompact()   return DB().refboxDisplayStyle == "compact" end

-- Returns true if the note has model viewer data (inspect notes or target notes with npcID)
local function IsInspectNote(id)
    local note = id and NDB() and NDB().notes and NDB().notes[id]
    if not note then return false end
    if note.source == "inspect" and note.inspectRaceID ~= nil then return true end
    if note.source == "target" and note.targetNpcID ~= nil and not note.targetIsPet then return true end
    return false
end
local function IsLocked(id)
    local note = id and NDB() and NDB().notes and NDB().notes[id]
    if not note then return false end
    if note.locked == true  then return true end
    if note.locked == false then return false end
    return DB().lockNotes == true
end

-- ── Attachment persistence ────────────────────────────────────────────────────
local function AddAttachment(noteID, att)
    if not noteID then return end
    if IsLocked(noteID) then
        BNB:Print(L["REFBOX_LOCKED"])
        return
    end
    local note = NDB().notes[noteID]
    if not note then return end
    if not note.attachments then note.attachments = {} end
    if #note.attachments >= GetMaxItems() then
        BNB:Print(string.format(L["REFBOX_FULL"], GetMaxItems()))
        return
    end
    for _, ex in ipairs(note.attachments) do
        if ex.type == att.type and ex.id == att.id then return end
    end
    table.insert(note.attachments, att)
    if BNB.RefreshNoteList then BNB.RefreshNoteList() end   -- update badge
    if BNB.RefreshReferenceBox then BNB.RefreshReferenceBox() end
end

local function RemoveAttachment(noteID, index)
    if not noteID then return end
    local note = NDB().notes[noteID]
    if not note or not note.attachments then return end
    table.remove(note.attachments, index)
    if BNB.RefreshNoteList then BNB.RefreshNoteList() end
    if BNB.RefreshReferenceBox then BNB.RefreshReferenceBox() end
end

local function CopyAttachment(fromNoteID, attIndex, toNoteID)
    if not fromNoteID or not toNoteID then return end
    local fromNote = NDB().notes[fromNoteID]
    if not fromNote or not fromNote.attachments then return end
    local att = fromNote.attachments[attIndex]
    if not att then return end
    -- Build a fresh copy and add to target
    local copy = {}; for k, v in pairs(att) do copy[k] = v end
    AddAttachment(toNoteID, copy)
end

local function MoveAttachment(fromNoteID, attIndex, toNoteID)
    if not fromNoteID or not toNoteID then return end
    local fromNote = NDB().notes[fromNoteID]
    if not fromNote or not fromNote.attachments then return end
    local att = fromNote.attachments[attIndex]
    if not att then return end
    -- Check dest capacity before removing from source
    local toNote = NDB().notes[toNoteID]
    if not toNote then return end
    if not toNote.attachments then toNote.attachments = {} end
    if #toNote.attachments >= GetMaxItems() then
        BNB:Print(L["REFBOX_MOVE_FULL"])
        return
    end
    table.remove(fromNote.attachments, attIndex)
    local copy = {}; for k, v in pairs(att) do copy[k] = v end
    table.insert(toNote.attachments, copy)
    if BNB.RefreshNoteList then BNB.RefreshNoteList() end
    if BNB.RefreshReferenceBox then BNB.RefreshReferenceBox() end
end

-- ── Data resolution ───────────────────────────────────────────────────────────
local function ResolveAttachment(att)
    if att.type == "item" then
        local name, _, quality, _, _, _, _, _, _, iconTex = GetItemInfo(att.id)
        if not name then
            C_Item.RequestLoadItemDataByID(att.id)
            _pendingItems[att.id] = true
            -- Timeout: if still pending after 10s, the ID is invalid — remove it
            local pendingID = att.id
            C_Timer.After(1, function()
                if not _pendingItems[pendingID] then return end
                _pendingItems[pendingID] = nil
                -- Remove all attachments with this ID from the current note
                local note = _noteID and NDB() and NDB().notes and NDB().notes[_noteID]
                if note and note.attachments then
                    local removed = false
                    for i = #note.attachments, 1, -1 do
                        local a = note.attachments[i]
                        if a.type == "item" and a.id == pendingID then
                            table.remove(note.attachments, i)
                            removed = true
                        end
                    end
                    if removed then
                        BNB:Print(string.format(L["REFBOX_INVALID_ITEM"], tostring(pendingID)))
                        if BNB.RefreshNoteList    then BNB.RefreshNoteList()    end
                        if BNB.RefreshReferenceBox then BNB.RefreshReferenceBox() end
                    end
                end
            end)
            return nil
        end
        _pendingItems[att.id] = nil
        local qc = QualityColor(quality)
        return { name=name, icon=iconTex or "Interface\\Icons\\INV_Misc_QuestionMark",
                 qr=qc.r, qg=qc.g, qb=qc.b, typeLabel=L["REFBOX_TYPE_GEAR"], quality=quality }
    elseif att.type == "spell" then
        -- C_Spell.GetSpellInfo returns nil for spells not yet in the client cache
        -- (e.g. freshly dragged from the spellbook). We request a load and retry,
        -- mirroring the item pending pattern.
        local name, icon
        local info = C_Spell.GetSpellInfo(att.id)
        if info then name = info.name; icon = info.iconID end
        if not name then
            -- Not cached yet — request a load and mark as pending
            if C_Spell and C_Spell.RequestLoadSpellData then
                C_Spell.RequestLoadSpellData(att.id)
            end
            _pendingSpells[att.id] = true
            EnsureSpellDataListener()
            -- Timeout: if still pending after 5s the ID is invalid — remove it
            local pendingID = att.id
            C_Timer.After(5, function()
                if not _pendingSpells[pendingID] then return end
                _pendingSpells[pendingID] = nil
                local note = _noteID and NDB() and NDB().notes and NDB().notes[_noteID]
                if note and note.attachments then
                    local removed = false
                    for i = #note.attachments, 1, -1 do
                        local a = note.attachments[i]
                        if a.type == "spell" and a.id == pendingID then
                            table.remove(note.attachments, i)
                            removed = true
                        end
                    end
                    if removed then
                        BNB:Print(string.format(L["REFBOX_INVALID_ITEM"], tostring(pendingID)))
                        if BNB.RefreshNoteList     then BNB.RefreshNoteList()     end
                        if BNB.RefreshReferenceBox then BNB.RefreshReferenceBox() end
                    end
                end
            end)
            return nil
        end
        _pendingSpells[att.id] = nil
        -- icon from C_Spell is a fileDataID number; SetTexture accepts both paths and IDs
        return { name=name, icon=icon or "Interface\\Icons\\INV_Misc_QuestionMark",
                 qr=0.40, qg=0.70, qb=1.00, typeLabel=L["REFBOX_TYPE_SPELL"], quality=-1 }
    elseif att.type == "quest" then
        local title = GetQuestTitle(att.id)
        local unknown = not title or title == ""
        if unknown then
            -- Request async server fetch — re-render on QUEST_DATA_LOAD_RESULT
            if C_QuestLog and C_QuestLog.RequestLoadQuestByID then
                C_QuestLog.RequestLoadQuestByID(att.id)
            end
            _pendingQuests[att.id] = true
            EnsureQuestDataListener()
            -- Use stored title hint (from wowhead URL slug) if available
            title = (att.title and att.title ~= "") and att.title or nil
        end
        local questIcon = "Interface\\GossipFrame\\AvailableQuestIcon"
        local typeLabel = (unknown and not att.title)
            and (L["REFBOX_TYPE_QUEST"] .. " (unknown)")
            or L["REFBOX_TYPE_QUEST"]
        return {
            name      = title or ("Quest " .. att.id),
            icon      = questIcon,
            qr        = 1.00, qg = 0.82, qb = 0.00,
            typeLabel = typeLabel,
            quality   = -1,
            unknown   = unknown and not att.title,
        }
    elseif att.type == "npc" then
        -- NPC pseudo-attachment from target note creation
        local typeStr = att.creatureType or "Creature"
        if att.level then
            typeStr = "Lv " .. tostring(att.level) .. " " .. typeStr
        end
        return {
            name      = att.name or "Unknown",
            icon      = att.icon or "Interface\\Icons\\INV_Misc_QuestionMark",
            qr        = 0.75, qg = 0.60, qb = 0.40,  -- warm brown
            typeLabel = typeStr,
            quality   = -1,
            isSubject = true,  -- marks as non-deletable note subject
        }
    elseif att.type == "player" then
        -- Player pseudo-attachment from target note creation
        local typeStr = att.className or "Player"
        if att.race then typeStr = att.race .. " " .. typeStr end
        if att.level then typeStr = "Lv " .. tostring(att.level) .. " " .. typeStr end
        -- Use class colour if available
        local cc = RAID_CLASS_COLORS and att.classFile and RAID_CLASS_COLORS[att.classFile]
        local qr = cc and cc.r or 0.60
        local qg = cc and cc.g or 0.60
        local qb = cc and cc.b or 0.60
        return {
            name      = att.name or "Unknown",
            icon      = att.icon or "Interface\\Icons\\INV_Misc_QuestionMark",
            qr        = qr, qg = qg, qb = qb,
            typeLabel = typeStr,
            quality   = -1,
            isSubject = true,
        }
    end
end

-- ── GET_ITEM_INFO_RECEIVED — re-render on cache fill, remove on failure ───────
local _itemInfoFrame
local function EnsureItemInfoListener()
    if _itemInfoFrame then return end
    _itemInfoFrame = CreateFrame("Frame")
    _itemInfoFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    _itemInfoFrame:SetScript("OnEvent", function(_, _, itemID, success)
        if not _pendingItems[itemID] then return end
        _pendingItems[itemID] = nil
        if success then
            if rbFrame and rbFrame:IsShown() then RenderList() end
        else
            -- Invalid ID — remove all attachments with this itemID and notify
            local note = _noteID and NDB().notes[_noteID]
            if note and note.attachments then
                for i = #note.attachments, 1, -1 do
                    local a = note.attachments[i]
                    if a.type == "item" and a.id == itemID then
                        table.remove(note.attachments, i)
                        BNB:Print(string.format(L["REFBOX_INVALID_ITEM"], tostring(itemID)))
                    end
                end
                if BNB.RefreshNoteList then BNB.RefreshNoteList() end
                if rbFrame and rbFrame:IsShown() then RenderList() end
            end
        end
    end)
end

-- ── SPELL_DATA_LOAD_RESULT — re-render on spell cache fill ───────────────────
local _spellDataFrame
EnsureSpellDataListener = function()
    if _spellDataFrame then return end
    _spellDataFrame = CreateFrame("Frame")
    _spellDataFrame:RegisterEvent("SPELL_DATA_LOAD_RESULT")
    _spellDataFrame:SetScript("OnEvent", function(_, _, spellID, success)
        if not _pendingSpells[spellID] then return end
        _pendingSpells[spellID] = nil
        if success then
            if rbFrame and rbFrame:IsShown() then RenderList() end
        else
            -- Invalid spell ID — remove matching attachments from current note
            local note = _noteID and NDB() and NDB().notes and NDB().notes[_noteID]
            if note and note.attachments then
                for i = #note.attachments, 1, -1 do
                    local a = note.attachments[i]
                    if a.type == "spell" and a.id == spellID then
                        table.remove(note.attachments, i)
                        BNB:Print(string.format(L["REFBOX_INVALID_ITEM"], tostring(spellID)))
                    end
                end
                if BNB.RefreshNoteList then BNB.RefreshNoteList() end
                if rbFrame and rbFrame:IsShown() then RenderList() end
            end
        end
    end)
end

-- ── Quest title lookup — with async server fetch ──────────────────────────────
-- C_QuestLog.GetTitleForQuestID (added Patch 9.0.1) works for any quest ID,
-- not just those in the log. Returns nil if data not yet cached — in that case
-- we request a server fetch and re-render when QUEST_DATA_LOAD_RESULT fires.
GetQuestTitle = function(questID)
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        return C_QuestLog.GetTitleForQuestID(questID)
    elseif C_QuestLog and C_QuestLog.GetQuestInfo then
        return C_QuestLog.GetQuestInfo(questID)
    end
    return nil
end

-- ── QUEST_DATA_LOAD_RESULT — re-render when server returns quest data ─────────
local _questDataFrame
EnsureQuestDataListener = function()
    if _questDataFrame then return end
    _questDataFrame = CreateFrame("Frame")
    _questDataFrame:RegisterEvent("QUEST_DATA_LOAD_RESULT")
    _questDataFrame:SetScript("OnEvent", function(_, _, questID, success)
        if not _pendingQuests[questID] then return end
        _pendingQuests[questID] = nil
        if success then
            if rbFrame and rbFrame:IsShown() then RenderList() end
        else
            local note = _noteID and NDB() and NDB().notes and NDB().notes[_noteID]
            if note and note.attachments then
                for i = #note.attachments, 1, -1 do
                    local a = note.attachments[i]
                    if a.type == "quest" and a.id == questID then
                        table.remove(note.attachments, i)
                        BNB:Print(string.format(L["REFBOX_INVALID_ITEM"], tostring(questID)))
                    end
                end
                if BNB.RefreshNoteList then BNB.RefreshNoteList() end
                if rbFrame and rbFrame:IsShown() then RenderList() end
            end
        end
    end)
end

local function ShowTooltip(anchor, att)
    GameTooltip:SetOwner(anchor, "ANCHOR_LEFT")
    if att.type == "item" then
        GameTooltip:SetHyperlink("item:" .. att.id)
    elseif att.type == "spell" then
        GameTooltip:SetSpellByID(att.id)
    elseif att.type == "quest" then
        local title = GetQuestTitle(att.id)
        if title and title ~= "" then
            GameTooltip:SetHyperlink("quest:" .. att.id .. ":0")
        else
            -- Quest not in log — show manual info tooltip
            GameTooltip:AddLine(att.title or ("Quest " .. att.id), 1, 0.82, 0)
            GameTooltip:AddLine("Quest ID: " .. att.id, 0.78, 0.78, 0.78)
            GameTooltip:AddLine("Not in your quest log.", 0.55, 0.55, 0.55)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Right-click to copy Wowhead URL.", 0.55, 0.82, 0.55)
        end
    end
    GameTooltip:Show()
end

-- ── Send attachment link to chat ──────────────────────────────────────────────
-- Gets the fully colour-coded hyperlink for an attachment.
-- For items: GetItemInfo's second return is the complete |cff...|r hyperlink.
-- For spells: construct the standard light-blue spell link manually.
local function BuildAttachmentLink(att)
    if att.type == "item" then
        local _, itemLink = GetItemInfo(att.id)
        return itemLink
    elseif att.type == "spell" then
        local name
        local info = C_Spell.GetSpellInfo(att.id)
        name = info and info.name
        if name then
            return "|cff71d5ff|Hspell:" .. att.id .. "|h[" .. name .. "]|h|r"
        end
    elseif att.type == "quest" then
        local title = GetQuestTitle(att.id)
        title = (title and title ~= "") and title
            or (att.title and att.title ~= "") and att.title
            or ("Quest " .. att.id)
        return "|cffffff00|Hquest:" .. att.id .. ":0|h[" .. title .. "]|h|r"
    end
    return nil
end

-- Returns the Wowhead URL for an attachment (all types supported).
local function BuildWowheadURL(att)
    if att.type == "item"  then return "https://www.wowhead.com/item="  .. att.id end
    if att.type == "spell" then return "https://www.wowhead.com/spell=" .. att.id end
    if att.type == "quest" then return "https://www.wowhead.com/quest=" .. att.id end
    return nil
end

-- Insert the attachment link at the text cursor in the active note body editor.
local function InsertAttachmentIntoNote(att, noteID)
    if IsLocked(noteID) then
        BNB:Print(L["REFBOX_LOCKED"])
        return
    end
    local link = BuildAttachmentLink(att)
    if not link then
        BNB:Print(L["REFBOX_LINK_FAIL"])
        return
    end
    local eb = nil
    if BNB._focusEditorBody and BNB._focusEditorBody:HasFocus() then
        eb = BNB._focusEditorBody
    elseif BNB._editorBody then
        eb = BNB._editorBody
    end
    if not eb then return end
    eb:Insert(link)
end

-- Insert link into chat.
-- If BCB is installed: show BCB frame + call BigChatBox.InsertLinkIntoBCB directly
-- (avoids the ChatFrame1EditBox pipeline delay that causes a one-step lag).
-- If no BCB: activate the default Blizzard editbox + ChatEdit_InsertLink.
local function SendAttachmentToChat(att)
    local link = BuildAttachmentLink(att)
    if not link then
        BNB:Print(L["REFBOX_LINK_FAIL"])
        return
    end

    if BigChatBox and BigChatBox.frame and BigChatBox.editBox then
        -- BCB present: show its frame, focus its editbox, then insert directly.
        -- BCB exposes InsertLinkIntoBCB which writes straight into its editbox
        -- without going through ChatFrame1EditBox's pipeline (avoids the one-step lag).
        BigChatBox.frame:Show()
        BigChatBox.editBox:SetFocus()
        if BigChatBox.InsertLinkIntoBCB then
            BigChatBox.InsertLinkIntoBCB(link)
        else
            -- Fallback if the function isn't exposed (future BCB version)
            _suppressShiftHook = true
            ChatEdit_InsertLink(link)
            C_Timer.After(0.1, function() _suppressShiftHook = false end)
        end
    else
        -- No BCB: activate the standard Blizzard chat editbox and insert directly.
        local editBox = DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox
        if editBox then
            ChatEdit_ActivateChat(editBox)
        end
        _suppressShiftHook = true
        ChatEdit_InsertLink(link)
        C_Timer.After(0.1, function() _suppressShiftHook = false end)
    end
end

-- ── Move/Copy picker window ───────────────────────────────────────────────────
local _pickerFrame  = nil
local _pickerNoteID = nil
local _pickerAttIdx = nil

local function BuildPickerWindow()
    local PW, PH   = 320, 380
    local TITLE_HP = 28
    local PAD_P    = 8

    local f = BNB.CreateBackdropFrame("Frame", "BNBRefBoxMovePickerFrame", UIParent)
    BNB.SetBackdropDark(f)
    f:SetSize(PW, PH)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self)
        self:StopMovingOrSizing()
        PositionModeStrip()
    end)
    f:SetScript("OnKeyDown",   function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            self:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    f:EnableKeyboard(true)

    -- Title bar
    local titleBar = f:CreateTexture(nil, "ARTWORK")
    titleBar:SetHeight(TITLE_HP)
    titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  1, -1)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    titleBar:SetColorTexture(0.10, 0.10, 0.14, 0.95)

    -- Attachment icon in title bar (set dynamically in OpenPicker)
    local titleIcon = f:CreateTexture(nil, "OVERLAY")
    titleIcon:SetSize(18, 18)
    titleIcon:SetPoint("LEFT", f, "LEFT", PAD_P, 0)
    titleIcon:SetPoint("TOP",  f, "TOP",  0, -5)
    titleIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f._titleIcon = titleIcon

    -- Title label (set dynamically in OpenPicker)
    -- Right anchor keeps clear of the 18px close button at TOPRIGHT +2 offset.
    local titleLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleLbl:SetPoint("LEFT",  titleIcon, "RIGHT", 4, 0)
    titleLbl:SetPoint("RIGHT", f, "RIGHT", -36, 0)
    titleLbl:SetPoint("TOP",   f, "TOP",   0, -7)
    titleLbl:SetJustifyH("LEFT")
    titleLbl:SetMaxLines(1); titleLbl:SetWordWrap(false)
    titleLbl:SetText(L["REFBOX_PICKER_TITLE"])
    f._titleLbl = titleLbl

    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1); sep:SetColorTexture(0.28, 0.28, 0.32, 1)
    sep:SetPoint("TOPLEFT",  f, "TOPLEFT",  1, -TITLE_HP)
    sep:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -TITLE_HP)

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetSize(18, 18)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", 2, -4)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local sf = CreateFrame("ScrollFrame", nil, f, "ScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     f, "TOPLEFT",    1,           -(TITLE_HP + 4))
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -SCROLL_PAD,  4)

    if sf.ScrollBar then
        sf.ScrollBar:SetAlpha(0)
        sf:HookScript("OnScrollRangeChanged", function(_, _, yr)
            sf.ScrollBar:SetAlpha((yr or 0) > 1 and 1.0 or 0)
        end)
    end

    local sc = CreateFrame("Frame", nil, sf)
    sc:SetWidth(sf:GetWidth()); sc:SetHeight(1)
    sf:SetScrollChild(sc)
    sf:SetScript("OnSizeChanged", function(self) sc:SetWidth(self:GetWidth()) end)

    f._sf = sf; f._sc = sc
    f:Hide()
    return f
end

local function OpenPicker(anchorFrame, noteID, attIndex)
    if not _pickerFrame then _pickerFrame = BuildPickerWindow() end
    _pickerNoteID = noteID
    _pickerAttIdx = attIndex

    -- Update title bar: icon + name of the attachment being moved/copied
    local att = (NDB() and NDB().notes and NDB().notes[noteID]
        and NDB().notes[noteID].attachments
        and NDB().notes[noteID].attachments[attIndex])
    if att and _pickerFrame._titleIcon and _pickerFrame._titleLbl then
        local data = ResolveAttachment(att)
        if data then
            _pickerFrame._titleIcon:SetTexture(data.icon)
            _pickerFrame._titleIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            _pickerFrame._titleLbl:SetText(string.format(L["REFBOX_PICKER_PREFIX"], data.name))
        else
            _pickerFrame._titleIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            _pickerFrame._titleLbl:SetText(L["REFBOX_PICKER_TITLE"])
        end
    end

    local sc = _pickerFrame._sc
    -- Hide all old child frames
    for i = sc:GetNumChildren(), 1, -1 do
        local child = select(i, sc:GetChildren())
        if child then child:Hide() end
    end

    -- Notes sorted A-Z, excluding the current note
    local notes = BNB.GetOrderedNotes and
        BNB.GetOrderedNotes(nil, nil, false, true) or {}
    table.sort(notes, function(a, b)
        return (a.title or ""):lower() < (b.title or ""):lower()
    end)

    local ROW_H = 36
    local BTN_H = 26
    local BTN_W = 52
    local ICON_W = 20   -- note icon in each row
    local y = 0

    for _, entry in ipairs(notes) do
        if entry.id ~= noteID then
            local targetID = entry.id
            local title    = (entry.title ~= "" and entry.title) or "(untitled)"

            local row = CreateFrame("Frame", nil, sc)
            row:SetHeight(ROW_H)
            row:SetPoint("TOPLEFT",  sc, "TOPLEFT",  0, y)
            row:SetPoint("TOPRIGHT", sc, "TOPRIGHT", 0, y)

            -- Alternating tint
            if math.floor(math.abs(y) / ROW_H) % 2 == 1 then
                local rowBg = row:CreateTexture(nil, "BACKGROUND")
                rowBg:SetAllPoints()
                rowBg:SetColorTexture(1, 1, 1, 0.03)
            end

            -- Note icon
            local noteIcon = row:CreateTexture(nil, "ARTWORK")
            noteIcon:SetSize(ICON_W, ICON_W)
            noteIcon:SetPoint("LEFT",   row, "LEFT",   6, 0)
            noteIcon:SetPoint("CENTER", row, "CENTER", 0, 0)
            noteIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            if entry.icon then
                noteIcon:SetTexture(entry.icon)
            else
                noteIcon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
            end

            -- Title label
            local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            lbl:SetPoint("LEFT",   row, "LEFT",   ICON_W + 10, 0)
            lbl:SetPoint("RIGHT",  row, "RIGHT",  -(BTN_W * 2 + 10), 0)
            lbl:SetPoint("CENTER", row, "CENTER", 0, 0)
            lbl:SetJustifyH("LEFT")
            lbl:SetMaxLines(1); lbl:SetWordWrap(false)
            lbl:SetText(title)

            -- Move button
            local moveBtn = BNB.CreateButton(nil, row, L["REFBOX_PICKER_MOVE"], BTN_W, BTN_H)
            moveBtn:SetPoint("RIGHT",  row,     "RIGHT",  -(BTN_W + 6), 0)
            moveBtn:SetPoint("CENTER", row,     "CENTER", 0, 0)
            moveBtn:SetScript("OnClick", function()
                MoveAttachment(noteID, attIndex, targetID)
                _pickerFrame:Hide()
            end)
            moveBtn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(string.format(L["REFBOX_MOVE_TO"], title), 1, 1, 1)
                GameTooltip:AddLine(L["REFBOX_MOVE_SUB"], 0.78, 0.78, 0.78)
                GameTooltip:Show()
            end)
            moveBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

            -- Copy button
            local copyBtn = BNB.CreateButton(nil, row, L["REFBOX_PICKER_COPY"], BTN_W, BTN_H)
            copyBtn:SetPoint("RIGHT",  row, "RIGHT",  -2, 0)
            copyBtn:SetPoint("CENTER", row, "CENTER",  0,  0)
            copyBtn:SetScript("OnClick", function()
                CopyAttachment(noteID, attIndex, targetID)
                _pickerFrame:Hide()
            end)
            copyBtn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(string.format(L["REFBOX_COPY_TO"], title), 1, 1, 1)
                GameTooltip:AddLine(L["REFBOX_COPY_SUB"], 0.78, 0.78, 0.78)
                GameTooltip:Show()
            end)
            copyBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

            -- Row separator
            if y < 0 then
                local rowSep = row:CreateTexture(nil, "ARTWORK")
                rowSep:SetHeight(1); rowSep:SetColorTexture(0.20, 0.20, 0.22, 0.8)
                rowSep:SetPoint("TOPLEFT"); rowSep:SetPoint("TOPRIGHT")
            end

            y = y - ROW_H
        end
    end
    sc:SetHeight(math.max(math.abs(y), _pickerFrame._sf:GetHeight()))

    -- Centre on the RefBox frame
    _pickerFrame:ClearAllPoints()
    if rbFrame and rbFrame:IsShown() then
        _pickerFrame:SetPoint("CENTER", rbFrame, "CENTER", 0, 0)
    else
        _pickerFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    _pickerFrame:Show()
    _pickerFrame:Raise()
end

-- ── Context menu ─────────────────────────────────────────────────────────────
local _ctxDropdown     = nil
local _gearCtxDropdown = nil

local function OpenContextMenu(anchorRow, noteID, attIndex)
    if not _ctxDropdown then
        _ctxDropdown = CreateFrame("DropdownButton", "BNBRefBoxCtxDropdown",
            UIParent, "WowStyle1DropdownTemplate")
        _ctxDropdown:SetSize(1, 1); _ctxDropdown:SetAlpha(0)
    end
    _ctxDropdown:ClearAllPoints()
    _ctxDropdown:SetPoint("TOPLEFT", anchorRow, "TOPRIGHT", 0, 0)
    _ctxDropdown:SetupMenu(function(_, root)
        root:CreateButton(L["REFBOX_CTX_SEND"], function()
            local note = NDB() and NDB().notes and NDB().notes[noteID]
            local att2 = note and note.attachments and note.attachments[attIndex]
            if att2 then SendAttachmentToChat(att2) end
        end)
        root:CreateButton(L["REFBOX_CTX_INSERT"], function()
            local note = NDB() and NDB().notes and NDB().notes[noteID]
            local att2 = note and note.attachments and note.attachments[attIndex]
            if att2 then InsertAttachmentIntoNote(att2, noteID) end
        end)
        root:CreateButton(L["REFBOX_CTX_WOWHEAD"], function()
            local note = NDB() and NDB().notes and NDB().notes[noteID]
            local att2 = note and note.attachments and note.attachments[attIndex]
            if not att2 then return end
            local url = BuildWowheadURL(att2)
            if url then BNB.ShowClipboardHint(url) end
        end)
        -- Dressing room — items only
        local noteCheck = NDB() and NDB().notes and NDB().notes[noteID]
        local attCheck  = noteCheck and noteCheck.attachments and noteCheck.attachments[attIndex]
        if attCheck and attCheck.type == "item" then
            root:CreateButton(L["REFBOX_CTX_DRESSUP"], function()
                local note2 = NDB() and NDB().notes and NDB().notes[noteID]
                local att2  = note2 and note2.attachments and note2.attachments[attIndex]
                if not att2 then return end
                local _, link = GetItemInfo(att2.id)
                if link then DressUpItemLink(link) end
            end)
        end
        root:CreateButton(L["REFBOX_CTX_MOVE_COPY"], function()
            local note = NDB() and NDB().notes and NDB().notes[noteID]
            local att2 = note and note.attachments and note.attachments[attIndex]
            if att2 then OpenPicker(anchorRow, noteID, attIndex) end
        end)
        root:CreateDivider()
        root:CreateButton(L["REFBOX_CTX_REMOVE"], function()
            RemoveAttachment(noteID, attIndex)
        end)
    end)
    _ctxDropdown:OpenMenu()
end

local function OpenGearContextMenu(anchorRow, noteID, gearEntry, listRef, listIdx)
    if not _gearCtxDropdown then
        _gearCtxDropdown = CreateFrame("DropdownButton", "BNBRefBoxGearCtxDropdown",
            UIParent, "WowStyle1DropdownTemplate")
        _gearCtxDropdown:SetSize(1, 1); _gearCtxDropdown:SetAlpha(0)
    end
    _gearCtxDropdown:ClearAllPoints()
    _gearCtxDropdown:SetPoint("TOPLEFT", anchorRow, "TOPRIGHT", 0, 0)
    _gearCtxDropdown:SetupMenu(function(_, root)
        -- Send to chat
        root:CreateButton(L["REFBOX_CTX_SEND"], function()
            local att = {type = "item", id = gearEntry.id}
            SendAttachmentToChat(att)
        end)

        -- Insert at text cursor — greyed out in rich note view mode
        local inViewMode = BNB._editorInViewMode == true
        local insertLabel = inViewMode
            and ("|cff888888" .. L["REFBOX_CTX_INSERT"] .. "|r")
            or  L["REFBOX_CTX_INSERT"]
        root:CreateButton(insertLabel, function()
            if inViewMode then return end
            local att = {type = "item", id = gearEntry.id}
            InsertAttachmentIntoNote(att, noteID)
        end)

        -- Copy Wowhead URL
        root:CreateButton(L["REFBOX_CTX_WOWHEAD"], function()
            local att = {type = "item", id = gearEntry.id}
            local url = BuildWowheadURL(att)
            if url then BNB.ShowClipboardHint(url) end
        end)

        -- Try in dressing room
        root:CreateButton(L["REFBOX_CTX_DRESSUP"], function()
            local _, link = GetItemInfo(gearEntry.id)
            if link then DressUpItemLink(link) end
        end)

        root:CreateDivider()

        -- Remove from gear list
        root:CreateButton(L["REFBOX_CTX_REMOVE"], function()
            if listRef and listIdx then
                table.remove(listRef, listIdx)
                BNB.UpdateNote(noteID, {})
                RenderList()
            end
        end)
    end)
    _gearCtxDropdown:OpenMenu()
end

-- ── Shift-click hook (Baganator-safe) ────────────────────────────────────────
local _shiftHookInstalled = false
local _lastAddedLink = nil
local _suppressShiftHook = false   -- set true while SendAttachmentToChat is inserting

local function TryAddLink(link)
    if _suppressShiftHook then return end
    if not rbFrame or not rbFrame:IsShown() then return end
    if not IsShiftKeyDown() then return end
    if not _noteID then return end
    if not link or link == "" then return end
    if _lastAddedLink == link then return end

    local itemID  = link:match("item:(%d+)")
    local spellID = link:match("spell:(%d+)")
    local questID = link:match("quest:(%d+)")
    if itemID then
        _lastAddedLink = link
        C_Timer.After(0.1, function() _lastAddedLink = nil end)
        AddAttachment(_noteID, { type="item",  id=tonumber(itemID)  })
    elseif spellID then
        _lastAddedLink = link
        C_Timer.After(0.1, function() _lastAddedLink = nil end)
        AddAttachment(_noteID, { type="spell", id=tonumber(spellID) })
    elseif questID then
        _lastAddedLink = link
        C_Timer.After(0.1, function() _lastAddedLink = nil end)
        AddAttachment(_noteID, { type="quest", id=tonumber(questID) })
    end
end

local function InstallShiftHooks()
    if _shiftHookInstalled then return end
    _shiftHookInstalled = true
    hooksecurefunc("ChatEdit_InsertLink", function(link) TryAddLink(link) end)
    if HandleModifiedItemClick then
        hooksecurefunc("HandleModifiedItemClick", function(link) TryAddLink(link) end)
    end
end

-- ── Manual entry — prefix syntax ──────────────────────────────────────────────
-- s:N or spell:N → spell
-- i:N or item:N  → item
-- bare number    → item (default)
-- item/spell link pasted → parsed automatically
local function ParseManualEntry(text)
    if not text or text == "" then return nil end
    text = text:match("^%s*(.-)%s*$")

    -- Wowhead URL: https://www.wowhead.com/item=2529/zweihander
    --              https://www.wowhead.com/quest=93932/legendary-prosperity
    --              https://www.wowhead.com/spell=7328/redemption
    local whType, whID, whSlug = text:match("wowhead%.com/([a-z]+)=(%d+)/?([^%s]*)")
    if whType and whID then
        local id = tonumber(whID)
        if whType == "item"  then return "item",  id end
        if whType == "spell" then return "spell", id end
        if whType == "quest" then
            -- Extract human-readable title from slug (replace hyphens with spaces, title-case)
            local title = nil
            if whSlug and whSlug ~= "" then
                title = whSlug:gsub("-", " "):gsub("(%a)([%w_']*)", function(a, b)
                    return a:upper() .. b:lower()
                end)
            end
            return "quest", id, title  -- third return: title hint
        end
    end

    -- Hyperlink pasted (item:N:... or spell:N or quest:N)
    local itemLink  = text:match("item:(%d+)")
    local spellLink = text:match("spell:(%d+)")
    local questLink = text:match("quest:(%d+)")
    if itemLink  then return "item",  tonumber(itemLink)  end
    if spellLink then return "spell", tonumber(spellLink) end
    if questLink then return "quest", tonumber(questLink) end

    -- Prefix syntax
    local spellPfx = text:match("^[Ss]:(%d+)$") or text:match("^[Ss]pell:(%d+)$")
    if spellPfx then return "spell", tonumber(spellPfx) end
    local itemPfx  = text:match("^[Ii]:(%d+)$") or text:match("^[Ii]tem:(%d+)$")
    if itemPfx  then return "item",  tonumber(itemPfx)  end
    local questPfx = text:match("^[Qq]:(%d+)$") or text:match("^[Qq]uest:(%d+)$")
    if questPfx then return "quest", tonumber(questPfx) end

    -- Bare number → item
    local num = tonumber(text)
    if num then return "item", num end

    return nil, nil
end

local function CommitManualEntry(text)
    if not _noteID or not text or text == "" then return end
    local attType, id, titleHint = ParseManualEntry(text)
    if attType and id then
        local att = { type=attType, id=id }
        if titleHint then att.title = titleHint end
        AddAttachment(_noteID, att)
    else
        BNB:Print(string.format(L["REFBOX_RESOLVE_MANUAL"], text))
    end
end

-- ── Row pool ──────────────────────────────────────────────────────────────────
local function ReleaseAllRows()
    for _, row in ipairs(_activeRows) do
        row:Hide()
        -- Clear gear-row state so pooled rows don't carry stale flags.
        row._gearSlot  = nil
        row._isGearRow = nil
        row._isTmog    = nil
        table.insert(_rowPool, row)
    end
    _activeRows = {}
    -- Hide gear section headers from previous render.
    local sc = rbFrame and rbFrame._scrollChild
    if sc and sc._activeGearHdrs then
        for _, hdr in ipairs(sc._activeGearHdrs) do
            hdr:Hide()
            sc._gearHdrs = sc._gearHdrs or {}
            table.insert(sc._gearHdrs, hdr)
        end
        sc._activeGearHdrs = {}
    end
end

local function AcquireRow(parent)
    local row = table.remove(_rowPool)
    if row then row:SetParent(parent); row:ClearAllPoints(); return row end

    row = BNB.CreateBackdropFrame("Button", nil, parent)
    row:EnableMouse(true)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row._icon = icon

    local iconBorder = row:CreateTexture(nil, "OVERLAY")
    iconBorder:SetTexture("Interface\\Common\\WhiteIconFrame")
    row._iconBorder = iconBorder

    local typeLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    typeLabel:SetJustifyH("LEFT"); typeLabel:SetTextColor(0.55, 0.55, 0.60)
    row._typeLabel = typeLabel

    local nameLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetJustifyH("LEFT"); nameLabel:SetWordWrap(false); nameLabel:SetMaxLines(1)
    row._nameLabel = nameLabel

    local pendingLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pendingLabel:SetJustifyH("LEFT"); pendingLabel:SetTextColor(0.45, 0.45, 0.50)
    pendingLabel:SetText(L["REFBOX_LOADING"]); pendingLabel:Hide()
    row._pendingLabel = pendingLabel

    -- Slot label: shown on gear cards (normal mode = top-right; compact = right-aligned).
    local slotLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    slotLabel:SetJustifyH("RIGHT"); slotLabel:SetTextColor(0.55, 0.55, 0.60)
    slotLabel:Hide()
    row._slotLabel = slotLabel

    -- Transmog watermark texture: right-side, low alpha, transmog cards only.
    local wmTex = row:CreateTexture(nil, "BACKGROUND")
    wmTex:SetTexture(ASSETS .. "UI\\ui-transmog")
    wmTex:Hide()
    row._wmTex = wmTex

    -- X close button: UIPanelCloseButton style, no background at rest
    local xBtn = CreateFrame("Button", nil, row, "UIPanelCloseButton")
    xBtn:SetSize(16, 16)
    xBtn:SetPoint("TOPRIGHT", row, "TOPRIGHT", -2, -2)
    xBtn:SetFrameLevel(row:GetFrameLevel() + 5)
    xBtn:SetAlpha(0)
    xBtn:EnableMouse(true)
    xBtn:SetScript("OnEnter", function(self) self:SetAlpha(1) end)
    xBtn:SetScript("OnLeave", function(self)
        if not row:IsMouseOver() then self:SetAlpha(0) end
    end)
    row._xBtn = xBtn

    row:SetScript("OnEnter", function(self)
        local qr = self._qr or 0; local qg = self._qg or 0; local qb = self._qb or 0
        self:SetBackdropColor(qr*0.20+0.06, qg*0.20+0.06, qb*0.20+0.08, 0.90)
        xBtn:SetAlpha(1)
        if self._att then ShowTooltip(self, self._att) end
    end)
    row:SetScript("OnLeave", function(self)
        local qr = self._qr or 0; local qg = self._qg or 0; local qb = self._qb or 0
        self:SetBackdropColor(qr*0.08, qg*0.08, qb*0.08, 0.55)
        xBtn:SetAlpha(0); GameTooltip:Hide()
    end)
    return row
end

local function SetupRow(row, att, data, index, compact, locked)
    row._att = att; row._index = index

    local iconSz   = compact and ICON_SZ_C or ICON_SZ_N
    local rowH     = compact and ROW_H_COMP or ROW_H_NORM
    local textLeft = CARD_PAD + iconSz + 8

    row:SetHeight(rowH)
    row._icon:SetSize(iconSz, iconSz)
    row._iconBorder:SetSize(iconSz+2, iconSz+2)
    row._icon:SetPoint("LEFT", row, "LEFT", CARD_PAD, 0)
    row._iconBorder:SetPoint("CENTER", row._icon, "CENTER", 0, 0)

    row._typeLabel:ClearAllPoints()
    row._nameLabel:ClearAllPoints()
    row._pendingLabel:ClearAllPoints()
    if row._slotLabel then row._slotLabel:ClearAllPoints() end

    -- isGearRow: gear card from inspectGearItems / inspectTransmogItems.
    local isGearRow = row._isGearRow
    local isTmog    = row._isTmog
    local slotText  = row._gearSlot or ""

    -- Compact: slot right-aligned; name constrained to avoid overlap.
    -- Normal:  type label = "Transmog: Head" or "Regular: Head"; name below.
    local SLOT_W = 50  -- reserved width for slot label in compact mode

    if compact then
        row._typeLabel:Hide()
        local vOff = -math.floor((rowH - 14) / 2)
        if isGearRow and row._slotLabel and slotText ~= "" then
            -- In compact mode the watermark sits at -5 from RIGHT (24px wide).
            -- Slot label goes to the left of it; name label stops before slot label.
            local wmClearance = isTmog and (5 + (rowH - 4) + 4) or 20
            row._slotLabel:SetPoint("RIGHT", row, "RIGHT", -wmClearance, 0)
            row._slotLabel:SetPoint("TOP",   row, "TOP",   0, vOff)
            row._slotLabel:SetText(slotText)
            row._slotLabel:Show()
            row._nameLabel:SetPoint("LEFT",  row, "LEFT",  textLeft, 0)
            row._nameLabel:SetPoint("RIGHT", row, "RIGHT", -(wmClearance + SLOT_W), 0)
            row._nameLabel:SetPoint("TOP",   row, "TOP",   0, vOff)
        else
            if row._slotLabel then row._slotLabel:Hide() end
            row._nameLabel:SetPoint("LEFT",  row, "LEFT",  textLeft, 0)
            row._nameLabel:SetPoint("RIGHT", row, "RIGHT", -20, 0)
            row._nameLabel:SetPoint("TOP",   row, "TOP",   0, vOff)
        end
        row._pendingLabel:SetPoint("LEFT", row, "LEFT", textLeft, 0)
        row._pendingLabel:SetPoint("TOP",  row, "TOP",  0, vOff)
    else
        if row._slotLabel then row._slotLabel:Hide() end
        row._typeLabel:Show()
        row._typeLabel:SetPoint("TOPLEFT",  row, "TOPLEFT",  textLeft, -8)
        row._typeLabel:SetPoint("TOPRIGHT", row, "TOPRIGHT", -20, -8)
        row._nameLabel:SetPoint("TOPLEFT",  row, "TOPLEFT",  textLeft, -22)
        row._nameLabel:SetPoint("TOPRIGHT", row, "TOPRIGHT", -20, -22)
        row._pendingLabel:SetPoint("TOPLEFT",  row, "TOPLEFT",  textLeft, -22)
        row._pendingLabel:SetPoint("TOPRIGHT", row, "TOPRIGHT", -20, -22)
    end

    -- Locked: desaturate icon and darken
    local desat = locked or false
    pcall(function() row._icon:SetDesaturated(desat) end)
    local alpha = locked and 0.55 or 1.0
    row._icon:SetAlpha(alpha)
    row._iconBorder:SetAlpha(alpha)
    row._nameLabel:SetAlpha(alpha)
    row._typeLabel:SetAlpha(alpha)
    -- Hide X on locked rows (can't remove)
    row._xBtn:SetAlpha(0)
    row._xBtn:EnableMouse(not locked)

    if data then
        local qr, qg, qb = data.qr, data.qg, data.qb
        row._qr, row._qg, row._qb = qr, qg, qb
        row._icon:SetTexture(data.icon)
        row._iconBorder:SetVertexColor(qr, qg, qb, 1)
        BNB.SetBackdrop(row, qr*0.08, qg*0.08, qb*0.08, 0.55, qr*0.50, qg*0.50, qb*0.50, 0.85)
        row._nameLabel:SetText(data.name)
        row._nameLabel:SetTextColor(qr, qg, qb, 1)
        if not compact then
            -- Gear rows: type label = "Transmog: Slot" or "Regular: Slot"
            if isGearRow and slotText ~= "" then
                local prefix = isTmog and L["REFBOX_GEAR_TYPE_TMOG"] or L["REFBOX_GEAR_TYPE_REG"]
                row._typeLabel:SetText(prefix .. ": " .. slotText)
            else
                row._typeLabel:SetText(data.typeLabel)
            end
        end
        row._nameLabel:Show(); row._pendingLabel:Hide()
    else
        row._qr, row._qg, row._qb = 0, 0, 0
        row._icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        row._iconBorder:SetVertexColor(0.40, 0.40, 0.40, 1)
        BNB.SetBackdrop(row, 0.07, 0.07, 0.09, 0.55, 0.22, 0.22, 0.26, 0.85)
        row._nameLabel:SetText("")
        if not compact then
            if isGearRow and slotText ~= "" then
                local prefix = isTmog and L["REFBOX_GEAR_TYPE_TMOG"] or L["REFBOX_GEAR_TYPE_REG"]
                row._typeLabel:SetText(prefix .. ": " .. slotText)
            else
                local typeLabel = att.type == "spell" and L["REFBOX_TYPE_SPELL"]
                    or att.type == "quest" and L["REFBOX_TYPE_QUEST"]
                    or L["REFBOX_TYPE_GEAR"]
                row._typeLabel:SetText(typeLabel)
            end
        end
        row._nameLabel:Hide(); row._pendingLabel:Show()
    end

    -- Watermark: show on transmog gear rows only.
    -- Size clamped to row height so it never overflows in compact mode.
    -- Right-aligned with enough clearance to avoid the slot label and X button.
    if row._wmTex then
        if isGearRow and isTmog then
            local wmSz = math.min(rowH - 4, 32)
            row._wmTex:ClearAllPoints()
            row._wmTex:SetSize(wmSz, wmSz)
            row._wmTex:SetPoint("RIGHT", row, "RIGHT", -5, 0)
            row._wmTex:SetAlpha(0.70)
            row._wmTex:Show()
        else
            row._wmTex:Hide()
        end
    end
end

-- ── Drag-and-drop ─────────────────────────────────────────────────────────────
local function WireDragDrop(frame)
    frame:SetScript("OnReceiveDrag", function()
        if not _noteID then return end
        -- On retail TWW/Midnight, GetCursorInfo for a spellbook drag returns:
        --   "spell", slotIndex, bookType, spellID
        -- The 4th return is the actual spellID; arg2 is the slot index.
        local cursorType, id, _, spellIDArg = GetCursorInfo()
        if cursorType == "item" then
            ClearCursor(); AddAttachment(_noteID, {type="item",  id=id})
        elseif cursorType == "spell" then
            local spellID = spellIDArg or id
            ClearCursor(); AddAttachment(_noteID, {type="spell", id=spellID})
        end
    end)
    frame:SetScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" then
            local ct = GetCursorInfo()
            if ct and ct ~= "" then self:GetScript("OnReceiveDrag")(self) end
        end
    end)
end

-- ── Core render ───────────────────────────────────────────────────────────────
RenderList = function()
    if not rbFrame or not rbFrame:IsShown() then return end

    local sc         = rbFrame._scrollChild
    local emptyLabel = rbFrame._emptyLabel
    local countLabel = rbFrame._countLabel
    local addBtn     = rbFrame._addBtn
    local manualBox  = rbFrame._manualBox

    ReleaseAllRows()

    local attachments = GetAttachments(_noteID) or {}
    local count       = #attachments
    local maxItems    = GetMaxItems()
    local modelVisible = IsInspectNote(_noteID) and not (_noteID and _modelHidden[_noteID])
    local compact     = IsCompact() or modelVisible  -- compact when model viewer is shown
    local locked      = IsLocked(_noteID)

    countLabel:SetText(string.format(L["REFBOX_COUNT"], count, maxItems))

    -- Lock state on add controls
    if addBtn then
        addBtn:SetEnabled(not locked)
        addBtn:SetAlpha(locked and 0.4 or 1.0)
        pcall(function() addBtn._tx:SetDesaturated(locked) end)
    end
    if manualBox then
        manualBox:SetEnabled(not locked)
        manualBox:SetAlpha(locked and 0.4 or 1.0)
    end

    if count == 0 then emptyLabel:Show() else emptyLabel:Hide() end

    local y = 0
    for i, att in ipairs(attachments) do
        local data = ResolveAttachment(att)
        local row  = AcquireRow(sc)
        row:SetPoint("TOPLEFT",  sc, "TOPLEFT",  PAD, y)
        row:SetPoint("TOPRIGHT", sc, "TOPRIGHT", -PAD, y)
        SetupRow(row, att, data, i, compact, locked)

        local idx  = i
        local att2 = att   -- capture for closures

        -- Subject cards (npc/player pseudo-attachments) are not interactive
        local isSubject = data and data.isSubject

        -- Left-click: send item/spell link to the active chat editbox
        -- Ctrl+left-click on items: open WoW dressing room
        if not isSubject then
            row:SetScript("OnClick", function(self, btn)
                if btn == "LeftButton" then
                    if IsControlKeyDown() and att2.type == "item" then
                        local _, link = GetItemInfo(att2.id)
                        if link then DressUpItemLink(link) end
                    else
                        SendAttachmentToChat(att2)
                    end
                end
            end)
        else
            row:SetScript("OnClick", nil)
        end

        if not locked and not isSubject then
            row._xBtn:SetScript("OnClick", function() RemoveAttachment(_noteID, idx) end)
            row:SetScript("OnMouseUp", function(self, btn)
                if btn == "RightButton" then OpenContextMenu(self, _noteID, idx) end
            end)
        else
            row._xBtn:SetScript("OnClick", nil)
            row:SetScript("OnMouseUp", nil)
        end

        -- Subject cards never show the X button
        if isSubject then
            row._xBtn:SetAlpha(0)
            row._xBtn:EnableMouse(false)
        end

        row:Show()
        table.insert(_activeRows, row)
        y = y - (compact and ROW_H_COMP or ROW_H_NORM) - ROW_GAP
    end

    -- ── Inspect gear sections (Transmog gear / Regular gear) ─────────────────
    -- These lists live on the note separately from note.attachments and do not
    -- count toward refboxMaxItems. They only appear for inspect notes.
    -- When attachments are empty the empty label sits at y=0 in the scroll child
    -- (~48px tall). Advance y to clear it so gear headers don't overlap.
    if count == 0 then y = y - 48 end
    local note = _noteID and BNB.GetNote(_noteID)
    if note and note.source == "inspect" and _rbMode == "model" then
        local gearShow    = (BigNoteBoxDB and BigNoteBoxDB.inspectNoteGearShow) or "both"
        local tmogItems   = note.inspectTransmogItems
        local regItems    = note.inspectGearItems
        local showTmog    = (gearShow == "both" or gearShow == "transmog") and tmogItems and #tmogItems > 0
        local showReg     = (gearShow == "both" or gearShow == "regular")  and regItems  and #regItems  > 0

        -- Helper: renders a header label at current y, returns new y.
        local function RenderGearHeader(text)
            if not sc._gearHdrs then sc._gearHdrs = {} end
            local hdr = table.remove(sc._gearHdrs)
            if not hdr then
                hdr = sc:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                hdr:SetHeight(16); hdr:SetJustifyH("LEFT")
                hdr:SetTextColor(0.55, 0.55, 0.55)
            end
            hdr:ClearAllPoints()
            hdr:SetPoint("TOPLEFT",  sc, "TOPLEFT",  PAD, y)
            hdr:SetPoint("TOPRIGHT", sc, "TOPRIGHT", -PAD, y)
            hdr:SetText(text)
            hdr:Show()
            -- Store so ReleaseAllRows can hide them next render.
            sc._activeGearHdrs = sc._activeGearHdrs or {}
            table.insert(sc._activeGearHdrs, hdr)
            return y - 18
        end

        -- Helper: renders one gear card row. isTmog controls watermark + type label.
        local function RenderGearRow(gearEntry, listRef, listIdx, isTmog)
            local att = { type = "item", id = gearEntry.id }
            local data = ResolveAttachment(att)
            local row = AcquireRow(sc)
            row:SetPoint("TOPLEFT",  sc, "TOPLEFT",  PAD, y)
            row:SetPoint("TOPRIGHT", sc, "TOPRIGHT", -PAD, y)
            -- Pass slot label and transmog flag through the row for SetupRow.
            row._gearSlot  = gearEntry.slot
            row._isGearRow = true
            row._isTmog    = isTmog
            SetupRow(row, att, data, nil, compact, false)

            local cap = gearEntry    -- capture for closures
            local capList = listRef
            local capIdx  = listIdx

            row:SetScript("OnClick", function(self, btn)
                if btn == "LeftButton" then
                    if IsControlKeyDown() then
                        -- Ctrl+click: open WoW dressing room with this item.
                        local link = GetItemInfo(gearEntry.id) and select(2, GetItemInfo(gearEntry.id))
                        if link then DressUpItemLink(link) end
                    else
                        SendAttachmentToChat(att)
                    end
                end
            end)
            row:SetScript("OnMouseUp", function(self, btn)
                if btn == "RightButton" then
                    OpenGearContextMenu(self, _noteID, gearEntry, capList, capIdx)
                end
            end)
            row._xBtn:SetScript("OnClick", function()
                if capList and capIdx then
                    table.remove(capList, capIdx)
                    -- Persist: update note directly then re-render.
                    BNB.UpdateNote(_noteID, {})  -- touch note to trigger save
                    RenderList()
                end
            end)
            row._xBtn:EnableMouse(true)

            row:Show()
            table.insert(_activeRows, row)
            return y - (compact and ROW_H_COMP or ROW_H_NORM) - ROW_GAP
        end

        if showTmog then
            y = RenderGearHeader("|cff888888-- " .. L["REFBOX_GEAR_HEADER_TMOG"] .. " --|r")
            for i, g in ipairs(tmogItems) do
                y = RenderGearRow(g, tmogItems, i, true)
            end
        end
        if showReg then
            y = RenderGearHeader("|cff888888-- " .. L["REFBOX_GEAR_HEADER_REG"] .. " --|r")
            for i, g in ipairs(regItems) do
                y = RenderGearRow(g, regItems, i, false)
            end
        end
    end

    local sf = rbFrame._scrollFrame
    sc:SetHeight(math.max(math.abs(y), sf:GetHeight()))

    -- Resize the window to fit content (clamped to main window height)
    SyncRefBoxHeight()

    -- Render task panel and reposition layout panes.
    -- Apply layout immediately so attachment rows don't overflow into the task
    -- panel, then apply again one tick later once rbFrame:GetHeight() has settled.
    if RenderTaskPanel then RenderTaskPanel() end
    ApplyTaskLayout(rbFrame)
    UpdateDynamicTitle()
    C_Timer.After(0, function()
        if rbFrame and rbFrame:IsShown() then
            ApplyTaskLayout(rbFrame)
            UpdateDynamicTitle()
            UpdateModelViewer()
        end
    end)
end

-- ── External Model/Tasks toggle strip ────────────────────────────────────────
-- Sits BELOW the RefBox frame, outside it. Only shown for inspect/target notes.
-- Mirrors the Editor/View tab strip pattern from NoteEditor.lua.
local _modeStrip = nil   -- the external strip frame

local function BuildExternalModeStrip()
    if _modeStrip then return _modeStrip end

    local strip = CreateFrame("Frame", "BigNoteBoxRefboxModeStrip", UIParent)
    strip:SetHeight(28)
    strip:Hide()

    local function OnModeClick(mode)
        _rbMode = mode
        if rbFrame then
            RenderTaskPanel()
            ApplyTaskLayout(rbFrame)
            UpdateModelViewer()
            UpdateDynamicTitle()
            UpdateModeStrip()
        end
    end

    local modelBtn = BNB.CreateButton(nil, strip, "Model", 1, 24)
    modelBtn:SetPoint("TOPLEFT",  strip, "TOPLEFT",  0, -2)
    modelBtn:SetPoint("TOPRIGHT", strip, "TOPLEFT",  math.floor(RBW / 2) - 1, -2)
    modelBtn:SetScript("OnClick", function() OnModeClick("model") end)

    local tasksBtn = BNB.CreateButton(nil, strip, "Tasks", 1, 24)
    tasksBtn:SetPoint("TOPLEFT",  strip, "TOPLEFT",  math.floor(RBW / 2) + 1, -2)
    tasksBtn:SetPoint("TOPRIGHT", strip, "TOPRIGHT", 0, -2)
    tasksBtn:SetScript("OnClick", function() OnModeClick("attachments") end)

    strip._modelBtn = modelBtn
    strip._tasksBtn = tasksBtn
    _modeStrip = strip
    return strip
end

-- Reposition the external strip below rbFrame.
local function PositionModeStrip()
    if not _modeStrip or not rbFrame then return end
    _modeStrip:ClearAllPoints()
    _modeStrip:SetPoint("TOPLEFT",  rbFrame, "BOTTOMLEFT",  0, 0)
    _modeStrip:SetPoint("TOPRIGHT", rbFrame, "BOTTOMRIGHT", 0, 0)
end

-- Update button alpha to reflect active mode.
-- Active button is fully visible; inactive button is dimmed.
function UpdateModeStrip()
    if not _modeStrip then return end
    local hasModel = IsInspectNote(_noteID)
    _modeStrip:SetShown(hasModel)
    if not hasModel then return end
    local mb = _modeStrip._modelBtn
    local tb = _modeStrip._tasksBtn
    if mb then
        mb:SetEnabled(_rbMode ~= "model")
        mb:SetAlpha(_rbMode == "model" and 1.0 or 0.45)
    end
    if tb then
        tb:SetEnabled(_rbMode ~= "attachments")
        tb:SetAlpha(_rbMode == "attachments" and 1.0 or 0.45)
    end
end

-- ApplyTaskLayout: positions all panes based on note content and _rbMode.
-- UpdateModelViewer must be called AFTER this when model is involved.
ApplyTaskLayout = function(f)
    if not f then return end
    local sf      = f._scrollFrame
    local taskPnl = f._taskPanel
    local sp      = f._taskSplitter
    local addWide = f._addTasksWide

    local hasTasks   = BNB.Task and BNB.Task.HasTasks(_noteID)
    local hasModel   = IsInspectNote(_noteID)
    local hasAtts    = _noteID and (function()
        local note = BNB.GetNote(_noteID)
        if not note then return false end
        if note.attachments and #note.attachments > 0 then return true end
        -- Inspect notes store gear separately — treat those as "has attachments"
        if note.inspectGearItems and #note.inspectGearItems > 0 then return true end
        if note.inspectTransmogItems and #note.inspectTransmogItems > 0 then return true end
        return false
    end)()
    local isSkin     = BigNoteBoxDB and BigNoteBoxDB.skinMode
    local titleH     = isSkin and SK_RB_TITLE_H or TITLE_H
    local contentTop = -(titleH + 4 + MANUAL_H + MANUAL_GAP + COUNT_H + 4)
    local botPad     = BOTTOM_PAD

    -- Update external mode strip button states
    UpdateModeStrip()

    -- Hide wide add-tasks button by default
    if addWide then addWide:Hide() end

    -- ── STATE: inspect/target note, model mode ────────────────────────────────
    if hasModel and _rbMode == "model" then
        if taskPnl then taskPnl:Hide() end
        if sp      then sp:Hide()      end
        if sf then
            sf:ClearAllPoints()
            sf:SetPoint("TOPLEFT",     f, "TOPLEFT",    0, contentTop)
            sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -SCROLL_PAD, botPad)
        end
        return  -- UpdateModelViewer runs after and splits the scroll area
    end

    -- ── STATE: no tasks exist ─────────────────────────────────────────────────
    if not hasTasks then
        if taskPnl then taskPnl:Hide() end
        if sp      then sp:Hide()      end
        -- Scroll frame leaves room for the Add Tasks button at the bottom
        if sf then
            sf:ClearAllPoints()
            sf:SetPoint("TOPLEFT",     f, "TOPLEFT",    0, contentTop)
            sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -SCROLL_PAD, botPad + ADD_TASKS_H)
        end
        -- Wide "Add Tasks" button pinned just above the bottom edge
        if addWide then
            addWide:ClearAllPoints()
            addWide:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  PAD,  botPad + 4)
            addWide:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, botPad + 4)
            addWide:SetHeight(26)
            addWide:Show()
        end
        return
    end

    -- ── Tasks exist: splitter only when attachments also present ──────────────
    local useSplitter = hasAtts

    local db    = BigNoteBoxDB
    local ratio = (db and db.taskSplitRatio and _noteID and db.taskSplitRatio[_noteID])
        or 0.5

    local SPLITTER_H = 12   -- must match sp:SetHeight() in BuildTaskPanel

    -- Use mainFrame height directly since we always sync rbFrame to it.
    -- f:GetHeight() can return a stale value before the first SyncRefBoxHeight.
    local fH = (BNB.mainFrame and BNB.mainFrame:GetHeight())
        or (f:GetHeight())
        or 300

    -- Total usable height, minus the splitter gap when both panels are shown
    local totalH = math.max(1,
        fH - math.abs(contentTop) - botPad
        - (useSplitter and SPLITTER_H or 0))

    -- Clamp ratio so each panel gets at least TASK_SPLIT_MIN_PX
    local minRatio = TASK_SPLIT_MIN_PX / math.max(1, totalH)
    ratio = math.max(minRatio, math.min(1.0 - minRatio, ratio))

    local taskH, attH
    if useSplitter then
        taskH = math.max(TASK_SPLIT_MIN_PX,
            math.min(totalH - TASK_SPLIT_MIN_PX,
                math.floor(totalH * (1.0 - ratio))))
        attH  = totalH - taskH
    else
        taskH = totalH
        attH  = 0
    end

    -- taskTop: below the attachment area and the splitter
    local taskTop = contentTop - attH - (useSplitter and SPLITTER_H or 0)

    if taskPnl then
        taskPnl:Show()
        taskPnl:ClearAllPoints()
        taskPnl:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, taskTop)
        taskPnl:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, taskTop)
        taskPnl:SetHeight(taskH)
    end

    -- Attachment empty-state strip height (shown even with no attachments)
    local ATT_EMPTY_H = 60   -- tall enough for "Drag items here" message

    if useSplitter then
        if sp then
            sp:ClearAllPoints()
            -- Splitter sits at the boundary: below attachments, above tasks
            sp:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, contentTop - attH)
            sp:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, contentTop - attH)
            sp:Show()
        end
        if sf then
            sf:ClearAllPoints()
            sf:SetPoint("TOPLEFT",     f, "TOPLEFT",    0, contentTop)
            sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -SCROLL_PAD,
                botPad + taskH + SPLITTER_H)
        end
    else
        -- No attachments: give a fixed strip at the top for the empty label,
        -- task panel takes the rest below it.
        if sp then sp:Hide() end
        local attStripH = ATT_EMPTY_H
        if sf then
            sf:ClearAllPoints()
            sf:SetPoint("TOPLEFT",     f, "TOPLEFT",    0, contentTop)
            sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -SCROLL_PAD,
                botPad + taskH)
            sf:SetHeight(attStripH)
        end
        -- Reposition task panel to sit below the attachment strip
        if taskPnl then
            taskPnl:ClearAllPoints()
            taskPnl:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, contentTop - attStripH)
            taskPnl:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, contentTop - attStripH)
            taskPnl:SetHeight(totalH - attStripH)
        end
    end
end

-- BuildTaskPanel: creates the task panel frame + splitter. Called once per build.
local function BuildTaskPanel(f)
    -- Task panel container (sits at the BOTTOM, below attachment scroll)
    local pnl = CreateFrame("Frame", nil, f)
    pnl:SetFrameLevel(f:GetFrameLevel() + 50)  -- above attachment rows and gear
    pnl:Hide()
    f._taskPanel = pnl

    -- Opaque background so attachment content behind doesn't bleed through.
    -- Inset 3px on left/right so it doesn't overlap the refbox window borders.
    local bg = pnl:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT",     pnl, "TOPLEFT",      3, 0)
    bg:SetPoint("BOTTOMRIGHT", pnl, "BOTTOMRIGHT",  -3, 0)
    local isSkin = BigNoteBoxDB and BigNoteBoxDB.skinMode
    if isSkin then
        local preset = BNB.GetSkinPreset()
        local r, g, b = BNB.SkinColourOf(preset, false)
        bg:SetColorTexture(r, g, b, BNB.GetSkinBgAlpha())
    else
        -- Match ButtonFrameTemplate body
        bg:SetColorTexture(0.07, 0.07, 0.07, 0.97)
    end
    pnl._bg = bg

    -- Inner scroll frame for task rows
    local tsf = CreateFrame("ScrollFrame", nil, pnl, "ScrollFrameTemplate")
    tsf:SetPoint("TOPLEFT",     pnl, "TOPLEFT",    0, 0)
    tsf:SetPoint("BOTTOMRIGHT", pnl, "BOTTOMRIGHT", -SCROLL_PAD, 0)
    if tsf.ScrollBar then
        tsf.ScrollBar:SetAlpha(0)
        tsf:HookScript("OnScrollRangeChanged", function(_, _, yr)
            tsf.ScrollBar:SetAlpha((yr or 0) > 1 and 1.0 or 0)
        end)
    end
    local tsc = CreateFrame("Frame", nil, tsf)
    tsc:SetWidth(tsf:GetWidth()); tsc:SetHeight(1)
    tsf:SetScrollChild(tsc)
    tsf:SetScript("OnSizeChanged", function(self) tsc:SetWidth(self:GetWidth()) end)
    f._taskScrollFrame = tsf
    f._taskScrollChild = tsc

    -- Wide "Add Tasks" button — shown when note has no tasks yet (states 1, 4)
    local addWide = BNB.CreateButton(nil, f, "+ Add Tasks", RBW - PAD * 2, 26)
    addWide:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  PAD, BOTTOM_PAD + 4)
    addWide:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, BOTTOM_PAD + 4)
    addWide:SetFrameLevel(f:GetFrameLevel() + 70)  -- above task panel (f+50) and splitter (f+60)
    addWide:Hide()
    addWide:SetScript("OnClick", function()
        if not _noteID or not BNB.Task then return end
        BNB.Task.AddTask(_noteID, "")
        RenderTaskPanel()
        ApplyTaskLayout(rbFrame)
        UpdateModelViewer()
        UpdateDynamicTitle()
        UpdateModeStrip()
        for _, row in ipairs(_taskRows) do
            if row._editBox then
                row._editBox:SetFocus()
                break
            end
        end
    end)
    f._addTasksWide = addWide

    -- Splitter drag bar (between attachments above and tasks below).
    -- Matches the MainWindow vertical splitter exactly: three 3x3 grip dots,
    -- no line, no SetCursor (produces black box on some clients).
    local sp = CreateFrame("Button", nil, f)
    sp:SetHeight(12)   -- taller hit area, dots centred inside
    sp:SetFrameLevel(f:GetFrameLevel() + 60)
    sp:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
    sp:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    sp:Hide()

    local dotSize = 3
    local dotGap  = 5
    local dots    = {}
    for i = -1, 1 do
        local dot = sp:CreateTexture(nil, "OVERLAY")
        dot:SetSize(dotSize, dotSize)
        dot:SetPoint("CENTER", sp, "CENTER", i * dotGap, 0)  -- horizontal
        dot:SetColorTexture(0.65, 0.65, 0.65, 0.9)
        dots[#dots + 1] = dot
    end

    -- 1px line behind dots — hidden (alpha 0) for a cleaner look
    local spLine = sp:CreateTexture(nil, "ARTWORK")
    spLine:SetHeight(1)
    spLine:SetPoint("TOPLEFT",  sp, "TOPLEFT",  0, -6)
    spLine:SetPoint("TOPRIGHT", sp, "TOPRIGHT", 0, -6)
    spLine:SetColorTexture(0.65, 0.65, 0.65, 0)

    sp:SetScript("OnEnter", function()
        for _, d in ipairs(dots) do d:SetColorTexture(1, 0.82, 0, 1) end
    end)
    sp:SetScript("OnLeave", function()
        for _, d in ipairs(dots) do d:SetColorTexture(0.65, 0.65, 0.65, 0.9) end
    end)

    local dragging = false

    -- Mouse capture frame: covers the screen during drag so releasing the mouse
    -- anywhere stops the drag. Parented to UIParent so it sits above game world.
    local captureFrame = CreateFrame("Frame", nil, UIParent)
    captureFrame:SetAllPoints(UIParent)
    captureFrame:SetFrameStrata("TOOLTIP")
    captureFrame:EnableMouse(true)
    captureFrame:Hide()
    captureFrame:SetScript("OnMouseUp", function(self)
        dragging = false
        sp:SetScript("OnUpdate", nil)
        self:Hide()
    end)

    sp:SetScript("OnMouseDown", function(self, btn)
        if btn ~= "LeftButton" then return end
        dragging = true
        captureFrame:Show()
        self:SetScript("OnUpdate", function()
            if not dragging then self:SetScript("OnUpdate", nil); return end
            local _, cy = GetCursorPosition()
            local scale = f:GetEffectiveScale()
            cy = cy / scale
            local fTop = f:GetTop()
            local fBot = f:GetBottom()
            if not fTop or not fBot then return end
            local isSkin = BigNoteBoxDB and BigNoteBoxDB.skinMode
            local titleH = isSkin and SK_RB_TITLE_H or TITLE_H
            local contentTop = fTop -
                math.abs(titleH + 4 + MANUAL_H + MANUAL_GAP + COUNT_H + 4)
            local hasModel  = IsInspectNote(_noteID)
            local footerH   = BOTTOM_PAD
            local totalH    = contentTop - fBot - footerH
            if totalH < 1 then return end
            -- ratio = attachment fraction (1 - task fraction)
            local SP_H = 12  -- splitter height
            local attH  = math.max(TASK_SPLIT_MIN_PX,
                math.min(totalH - TASK_SPLIT_MIN_PX - SP_H, contentTop - cy))
            local ratio = attH / totalH   -- attachment fraction stored
            local db = BigNoteBoxDB
            if db and db.taskSplitRatio and _noteID then
                db.taskSplitRatio[_noteID] = ratio
            end
            ApplyTaskLayout(f)
        end)
    end)
    sp:SetScript("OnMouseUp", function(self)
        dragging = false
        sp:SetScript("OnUpdate", nil)
        captureFrame:Hide()
    end)
    f._taskSplitter = sp
end

-- Register the TasksChanged callback once, regardless of which build path
-- created the frame. Both OpenReferenceBox and SyncReferenceBox call this
-- after building rbFrame.
RegisterTaskCallback = function()
    if _taskCallbackRegistered then return end
    if not BNB.Task or not BNB.Task.RegisterCallback then return end
    _taskCallbackRegistered = true
    BNB.Task.RegisterCallback("TasksChanged", function(changedNoteID)
        if rbFrame and rbFrame:IsShown() and changedNoteID == _noteID then
            RenderTaskPanel()
            ApplyTaskLayout(rbFrame)
            UpdateDynamicTitle()
        end
    end)
end

-- ── Task panel renderer ───────────────────────────────────────────────────────
-- Renders task rows into f._taskScrollChild. Called from RenderList.
RenderTaskPanel = function()
    if not rbFrame then return end
    local tsc = rbFrame._taskScrollChild
    if not tsc then return end

    -- Release existing task row widgets — hide frames and fontstrings alike
    for _, tr in ipairs(_taskRows) do tr:Hide() end
    _taskRows = {}
    -- Also hide any orphaned children/regions from previous renders to prevent
    -- accumulation (FontStrings created on tsc can't be destroyed, only hidden).
    for _, child in ipairs({ tsc:GetChildren() }) do child:Hide() end
    for _, region in ipairs({ tsc:GetRegions() }) do region:Hide() end

    local hasTasks = BNB.Task and BNB.Task.HasTasks(_noteID)
    local taskPnl  = rbFrame._taskPanel

    -- No tasks: hide task panel, ApplyTaskLayout shows the wide button instead
    if not hasTasks then
        if taskPnl then taskPnl:Hide() end
        return
    end

    -- Tasks exist: ensure panel is visible (ApplyTaskLayout positions it)
    if taskPnl then taskPnl:Show() end

    local db           = BigNoteBoxDB
    local completedPos = (db and db.taskCompletedPosition) or "bottom"
    local T            = BNB.Task
    local done, total  = T.GetCompletionCount(_noteID)

    -- ── Header row ──────────────────────────────────────────────────────────
    -- "Tasks" label + completion badge + add button + clear completed button
    local hdr = tsc:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hdr:SetPoint("TOPLEFT",  tsc, "TOPLEFT",  PAD, -4)
    hdr:SetPoint("TOPRIGHT", tsc, "TOPRIGHT", -40, -4)
    hdr:SetHeight(TASK_HDR_H - 4)
    hdr:SetJustifyH("LEFT")
    hdr:SetText("Tasks")
    _taskRows[#_taskRows + 1] = hdr

    local badgeClr = T.GetBadgeColor(_noteID)
    local badge = tsc:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    badge:SetTextColor(badgeClr.r, badgeClr.g, badgeClr.b)
    badge:SetText(total > 0 and (done .. "/" .. total) or "")
    _taskRows[#_taskRows + 1] = badge

    -- Add task (+) button — top-right of header
    local addBtn = CreateFrame("Button", nil, tsc)
    addBtn:SetSize(18, 18)
    addBtn:SetPoint("TOPRIGHT", tsc, "TOPRIGHT", -4, -3)
    local addN = addBtn:CreateTexture(nil, "ARTWORK"); addN:SetAllPoints()
    addN:SetTexture(ASSETS .. "Buttons\\bt-plus-normal")
    local addH = addBtn:CreateTexture(nil, "ARTWORK"); addH:SetAllPoints()
    addH:SetTexture(ASSETS .. "Buttons\\bt-plus-hover"); addH:Hide()
    local addP = addBtn:CreateTexture(nil, "ARTWORK"); addP:SetAllPoints()
    addP:SetTexture(ASSETS .. "Buttons\\bt-plus-press"); addP:Hide()
    addBtn:SetScript("OnEnter", function() addH:Show(); addN:Hide() end)
    addBtn:SetScript("OnLeave", function() addH:Hide(); addN:Show() end)
    addBtn:SetScript("OnMouseDown", function() addP:Show(); addN:Hide(); addH:Hide() end)
    addBtn:SetScript("OnMouseUp",   function() addP:Hide(); addN:Show() end)
    addBtn:SetScript("OnClick", function()
        if not _noteID then return end
        local taskID = BNB.Task.AddTask(_noteID, "")
        if taskID then
            RenderTaskPanel()
            ApplyTaskLayout(rbFrame)
            for _, row in ipairs(_taskRows) do
                if row._taskID == taskID and row._editBox then
                    row._editBox:SetFocus()
                    break
                end
            end
        end
    end)
    _taskRows[#_taskRows + 1] = addBtn

    -- Badge sits to the left of the add button, vertically centred with hdr
    badge:SetPoint("RIGHT", addBtn, "LEFT", -4, 0)
    badge:SetPoint("TOP",   tsc,   "TOP",   0, -4)

    -- "Clear completed" button — only when any tasks are done
    local hasDone = done > 0
    if hasDone then
        local clrBtn = BNB.CreateButton(nil, tsc, "Clear done", 72, 16)
        clrBtn:SetPoint("RIGHT", addBtn, "LEFT", -26, 0)
        clrBtn:SetPoint("TOP",   tsc,   "TOP",  0, -4)
        clrBtn:SetScript("OnClick", function()
            if _noteID then T.ClearCompleted(_noteID) end
        end)
        _taskRows[#_taskRows + 1] = clrBtn
    end

    -- ── Task rows ────────────────────────────────────────────────────────────
    local y       = -(TASK_HDR_H + 2)
    local indent  = T.SUBTASK_INDENT or 14
    local contentW = (rbFrame:GetWidth() or RBW) - SCROLL_PAD - PAD * 2

    -- Gather top-level tasks, sort completed to bottom if configured
    local topLevel = T.GetTopLevel(_noteID)
    if completedPos == "bottom" then
        local active, completed = {}, {}
        for _, t in ipairs(topLevel) do
            if t.completed then completed[#completed + 1] = t
            else                active[#active + 1] = t end
        end
        topLevel = {}
        for _, t in ipairs(active)    do topLevel[#topLevel + 1] = t end
        for _, t in ipairs(completed) do topLevel[#topLevel + 1] = t end
    end

    local function RenderTaskRow(task, isSubTask)
        local rowH  = isSubTask and TASK_SUBROW_H or TASK_ROW_H
        local xOff  = isSubTask and indent or 0
        local clr   = T.GetTaskColor(task)

        local row = CreateFrame("Button", nil, tsc)
        row:SetPoint("TOPLEFT",  tsc, "TOPLEFT",  PAD + xOff, y)
        row:SetPoint("TOPRIGHT", tsc, "TOPRIGHT", -PAD, y)
        row:SetHeight(rowH)
        row._taskID = task.id
        _taskRows[#_taskRows + 1] = row

        -- Checkbox (scaled UICheckButtonTemplate)
        local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        cb:SetScale(TASK_CB_SCALE)
        cb:SetChecked(task.completed)
        cb:SetPoint("LEFT", row, "LEFT", 0, 0)
        cb:SetScript("OnClick", function(self)
            if _noteID then T.ToggleTask(_noteID, task.id) end
        end)
        -- Route right-clicks on the checkbox to the context menu
        cb:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        cb:HookScript("OnClick", function(_, btn)
            if btn == "RightButton" then
                cb:SetChecked(task.completed)  -- undo the toggle
                BNB.ShowTaskContextMenu(row, _noteID, task.id)
            end
        end)
        row._cb = cb

        -- Task text / inline editbox
        local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("LEFT",  cb,  "RIGHT", 2,  0)
        lbl:SetPoint("RIGHT", row, "RIGHT", -22, 0)
        lbl:SetHeight(rowH)
        lbl:SetJustifyH("LEFT")
        lbl:SetWordWrap(false)
        lbl:SetTextColor(clr.r, clr.g, clr.b)
        lbl:SetText(task.text ~= "" and task.text or "(empty)")

        -- Inline edit box (hidden until clicked)
        local eb = CreateFrame("EditBox", nil, row, "BackdropTemplate")
        BNB.EnsureBackdrop(eb)
        BNB.SetBackdrop(eb, 0.06, 0.06, 0.08, 0.95, 0.20, 0.20, 0.25, 1)
        eb:SetPoint("LEFT",  cb,  "RIGHT", 2,  0)
        eb:SetPoint("RIGHT", row, "RIGHT", -22, 0)
        eb:SetHeight(rowH - 2)
        eb:SetAutoFocus(false)
        eb:SetMultiLine(false)
        eb:SetMaxLetters(500)
        eb:SetFontObject("GameFontNormalSmall")
        eb:SetTextInsets(4, 4, 1, 1)
        eb:Hide()
        row._editBox = eb

        lbl:SetScript("OnMouseDown", function(_, btn)
            if btn == "RightButton" then
                BNB.ShowTaskContextMenu(row, _noteID, task.id)
                return
            end
            lbl:Hide()
            eb:SetText(task.text)
            eb:Show()
            eb:SetFocus()
        end)
        eb:SetScript("OnEnterPressed", function(self)
            local newText = self:GetText()
            if newText == "" then
                -- Delete task if committed with empty text
                BNB.Task.DeleteTask(_noteID, task.id)
            else
                T.UpdateTask(_noteID, task.id, { text = newText })
                task.text = newText
                lbl:SetText(newText)
                self:Hide(); lbl:Show()
            end
            self:ClearFocus()
        end)
        eb:SetScript("OnEscapePressed", function(self)
            if task.text == "" then
                -- Escape on a never-saved empty task removes it
                BNB.Task.DeleteTask(_noteID, task.id)
            else
                self:Hide(); lbl:Show()
            end
            self:ClearFocus()
        end)
        eb:SetScript("OnEditFocusLost", function(self)
            if self:IsShown() then
                -- Focus lost without Enter/Escape — save if non-empty, delete if empty
                local newText = self:GetText()
                if newText == "" then
                    BNB.Task.DeleteTask(_noteID, task.id)
                else
                    T.UpdateTask(_noteID, task.id, { text = newText })
                    task.text = newText
                    lbl:SetText(newText)
                    self:Hide(); lbl:Show()
                end
            end
        end)
        eb:SetScript("OnMouseUp", function(_, btn)
            if btn == "RightButton" then
                BNB.ShowTaskContextMenu(row, _noteID, task.id)
            end
        end)

        -- Sub-task expand toggle (bt-right = collapsed, bt-down = expanded)
        local subTasks = T.GetSubTasks(_noteID, task.id)
        if not isSubTask then
            local togBtn = CreateFrame("Button", nil, row)
            togBtn:SetSize(14, 14)
            togBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            local togN = togBtn:CreateTexture(nil, "ARTWORK"); togN:SetAllPoints()
            togN:SetTexture(ASSETS .. "Buttons\\bt-right-normal")
            row._expanded = #subTasks > 0
            if row._expanded then
                togN:SetTexture(ASSETS .. "Buttons\\bt-down-normal")
            end
            togBtn:SetAlpha(#subTasks > 0 and 1.0 or 0.3)
            togBtn:SetScript("OnClick", function()
                row._expanded = not row._expanded
                togN:SetTexture(ASSETS .. "Buttons\\" ..
                    (row._expanded and "bt-down-normal" or "bt-right-normal"))
                RenderTaskPanel()
                ApplyTaskLayout(rbFrame)
            end)
            togBtn:SetScript("OnMouseUp", function(_, btn)
                if btn == "RightButton" then
                    BNB.ShowTaskContextMenu(row, _noteID, task.id)
                end
            end)
            row._togBtn = togBtn
        end

        -- Right-click context menu (OnMouseUp — same pattern as attachment rows;
        -- RegisterForClicks+OnClick on Buttons inside ScrollFrameTemplate scroll
        -- children does not reliably receive right-clicks on retail).
        row:SetScript("OnMouseUp", function(_, btn)
            if btn == "RightButton" then
                BNB.ShowTaskContextMenu(row, _noteID, task.id)
            end
        end)

        y = y - rowH - 2

        -- Sub-tasks (one level only, only if expanded)
        if not isSubTask and row._expanded then
            for _, sub in ipairs(subTasks) do
                RenderTaskRow(sub, true)
            end
        end
    end

    for _, task in ipairs(topLevel) do
        RenderTaskRow(task, false)
    end

    -- Set scroll child height
    local tsf = rbFrame._taskScrollFrame
    tsc:SetHeight(math.max(math.abs(y) + 4, tsf and tsf:GetHeight() or 60))
end

-- ── Task context menu (WowStyle1DropdownTemplate — matches attachment rows) ──
local _taskCtxDropdown
function BNB.ShowTaskContextMenu(anchor, noteID, taskID)
    if not noteID or not taskID then return end
    local T = BNB.Task
    if not T then return end
    local task = T.FindTask(noteID, taskID)
    if not task then return end

    if not _taskCtxDropdown then
        _taskCtxDropdown = CreateFrame("DropdownButton", "BNBTaskCtxDropdown",
            UIParent, "WowStyle1DropdownTemplate")
        _taskCtxDropdown:SetSize(1, 1); _taskCtxDropdown:SetAlpha(0)
    end
    _taskCtxDropdown:ClearAllPoints()
    _taskCtxDropdown:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 0, 0)

    local isTopLevel = not task.parentID
    local L = BNB.L or {}

    _taskCtxDropdown:SetupMenu(function(_, root)
        -- Edit task...
        root:CreateButton(L["TASK_CTX_EDIT"] or "Edit task...", function()
            if BNB.TaskEditWindow and BNB.TaskEditWindow.Open then
                BNB.TaskEditWindow.Open(noteID, taskID, anchor)
            end
        end)

        -- Add sub-task (top-level only, one nesting level)
        if isTopLevel then
            root:CreateButton(L["TASK_CTX_ADD_SUB"] or "Add sub-task", function()
                local subID = T.AddTask(noteID, "", taskID)
                if subID and RenderTaskPanel then
                    RenderTaskPanel()
                    ApplyTaskLayout(rbFrame)
                    -- Focus the new empty sub-task's inline editbox
                    for _, tr in ipairs(_taskRows) do
                        if tr._taskID == subID and tr._editBox then
                            local lbl2 = ({ tr:GetRegions() })[1]
                            if lbl2 and lbl2.Hide then lbl2:Hide() end
                            tr._editBox:SetText("")
                            tr._editBox:Show()
                            tr._editBox:SetFocus()
                            break
                        end
                    end
                end
            end)
        end

        -- Duplicate
        root:CreateButton(L["TASK_CTX_DUPLICATE"] or "Duplicate", function()
            local newID = T.AddTask(noteID, task.text, task.parentID)
            if newID then
                local changes = {}
                if task.resetType then changes.resetType = task.resetType end
                if task.resetEvery then changes.resetEvery = task.resetEvery end
                if task.situation then changes.situation = task.situation end
                if next(changes) then T.UpdateTask(noteID, newID, changes) end
                if RenderTaskPanel then
                    RenderTaskPanel()
                    ApplyTaskLayout(rbFrame)
                end
            end
        end)

        root:CreateDivider()

        -- Set reset (radio submenu)
        local resetSub = root:CreateButton(L["TASK_CTX_RESET"] or "Set reset")
        local RESETS = {
            { label = L["TASK_CTX_RESET_NONE"]   or "None",   value = nil    },
            { label = L["TASK_CTX_RESET_DAILY"]  or "Daily",  value = "daily"  },
            { label = L["TASK_CTX_RESET_WEEKLY"] or "Weekly", value = "weekly" },
        }
        for _, entry in ipairs(RESETS) do
            resetSub:CreateRadio(entry.label,
                function() return task.resetType == entry.value end,
                function()
                    if entry.value then
                        T.UpdateTask(noteID, taskID, { resetType = entry.value })
                    else
                        T.UpdateTask(noteID, taskID, { _clear = {"resetType", "resetEvery", "lastReset"} })
                    end
                end)
        end

        -- Set situation (radio submenu with live-detected values)
        local sitSub = root:CreateButton(L["TASK_CTX_SITUATION"] or "Set situation")
        sitSub:CreateRadio(L["TASK_CTX_SIT_NONE"] or "None (global)",
            function() return not task.situation end,
            function()
                T.UpdateTask(noteID, taskID, { _clear = {"situation"} })
            end)

        local curZone = GetZoneText and GetZoneText() or ""
        if curZone ~= "" then
            sitSub:CreateRadio("Zone: " .. curZone,
                function() return task.situation == ("zone:" .. curZone) end,
                function()
                    T.UpdateTask(noteID, taskID, { situation = "zone:" .. curZone })
                end)
        end

        local curSub = GetSubZoneText and GetSubZoneText() or ""
        if curSub ~= "" then
            sitSub:CreateRadio("Sub-zone: " .. curSub,
                function() return task.situation == ("subzone:" .. curSub) end,
                function()
                    T.UpdateTask(noteID, taskID, { situation = "subzone:" .. curSub })
                end)
        end

        local curInst = GetInstanceInfo and select(1, GetInstanceInfo()) or ""
        local isInstance = GetInstanceInfo and select(2, GetInstanceInfo())
        if curInst ~= "" and isInstance and isInstance ~= "none" then
            sitSub:CreateRadio("Instance: " .. curInst,
                function() return task.situation == ("instance:" .. curInst) end,
                function()
                    T.UpdateTask(noteID, taskID, { situation = "instance:" .. curInst })
                end)
        end

        local targetName = UnitName("target")
        if targetName and UnitIsPlayer("target") then
            sitSub:CreateRadio("Player: " .. targetName,
                function() return task.situation == ("player:" .. targetName) end,
                function()
                    T.UpdateTask(noteID, taskID, { situation = "player:" .. targetName })
                end)
        end

        root:CreateDivider()

        -- Delete
        local delLabel = "|cffFF6666" .. (L["TASK_CTX_DELETE"] or "Delete") .. "|r"
        root:CreateButton(delLabel, function()
            T.DeleteTask(noteID, taskID)
            if RenderTaskPanel then
                RenderTaskPanel()
                ApplyTaskLayout(rbFrame)
            end
        end)
    end)
    _taskCtxDropdown:OpenMenu()
end

-- ── Build window (ButtonFrameTemplate — matches TrashWindow/NoteConfig) ────────
local function BuildReferenceBox()
    local f = CreateFrame("Frame", "BigNoteBoxReferenceBoxFrame", UIParent,
        "ButtonFrameTemplate")
    f:SetWidth(RBW)
    f:SetToplevel(true)
    f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self)
        self:StopMovingOrSizing()
        PositionModeStrip()
    end)

    ButtonFrameTemplate_HidePortrait(f)
    ButtonFrameTemplate_HideButtonBar(f)
    if f.Inset then f.Inset:Hide() end
    f:SetTitle(L["REFBOX_TITLE"])

    if f.CloseButton then
        f.CloseButton:SetScript("OnClick", function() BNB.CloseReferenceBox() end)
    end

    -- ── Manual entry strip ───────────────────────────────────────────────────
    local manualStrip = CreateFrame("Frame", nil, f)
    manualStrip:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, -(TITLE_H + 4))
    manualStrip:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -(TITLE_H + 4))
    manualStrip:SetHeight(MANUAL_H)

    local eb = CreateFrame("EditBox", nil, manualStrip, "BackdropTemplate")
    BNB.EnsureBackdrop(eb)
    BNB.SetBackdrop(eb, 0.04, 0.04, 0.06, 0.90, 0.18, 0.18, 0.22, 1)
    eb:SetPoint("TOPLEFT",  manualStrip, "TOPLEFT",  0, 0)
    eb:SetPoint("TOPRIGHT", manualStrip, "TOPRIGHT", -68, 0)
    eb:SetHeight(MANUAL_H)
    eb:SetAutoFocus(false); eb:SetMultiLine(false); eb:SetMaxLetters(256)
    eb:SetFontObject("GameFontNormalSmall"); eb:SetTextInsets(6, 6, 2, 2)
    BNB.AddPlaceholder(eb, L["REFBOX_PLACEHOLDER"], 0.4, 0.4, 0.45)
    eb:SetScript("OnEnterPressed", function(self)
        CommitManualEntry(self:GetRealText()); self:SetRealText(""); self:ClearFocus()
    end)
    eb:SetScript("OnEscapePressed", function(self)
        self:SetRealText(""); self:ClearFocus()
    end)
    f._manualBox = eb

    local addBtn = BNB.CreateButton(nil, manualStrip, L["REFBOX_ADD_BTN"], 40, MANUAL_H)
    addBtn:SetPoint("TOPRIGHT", manualStrip, "TOPRIGHT", -24, 0)
    addBtn:SetScript("OnClick", function()
        if IsLocked(_noteID) then BNB:Print(L["REFBOX_LOCKED"]); return end
        CommitManualEntry(eb:GetRealText()); eb:SetRealText(""); eb:ClearFocus()
    end)
    f._addBtn = addBtn

    local helpBtn = CreateFrame("Button", nil, manualStrip)
    helpBtn:SetSize(20, MANUAL_H)
    helpBtn:SetPoint("TOPRIGHT", manualStrip, "TOPRIGHT", 0, 0)
    local helpTex = helpBtn:CreateTexture(nil, "ARTWORK")
    helpTex:SetSize(20, 20)
    helpTex:SetPoint("CENTER", helpBtn, "CENTER", 0, 0)
    helpTex:SetTexture(ASSETS .. "UI\\ui-info")
    helpBtn:SetAlpha(0.55)
    helpBtn:SetScript("OnEnter", function(self)
        self:SetAlpha(1.0)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(L["REFBOX_INFO_TITLE"], 1, 0.82, 0)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["REFBOX_INFO_BARE"],  0.85, 0.85, 0.85)
        GameTooltip:AddLine(L["REFBOX_INFO_SPELL"], 0.85, 0.85, 0.85)
        GameTooltip:AddLine(L["REFBOX_INFO_QUEST"], 0.85, 0.85, 0.85)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["REFBOX_INFO_ALSO"],  1, 0.82, 0)
        GameTooltip:AddLine(L["REFBOX_INFO_DRAG"],  0.78, 0.78, 0.78)
        GameTooltip:AddLine(L["REFBOX_INFO_SHIFT"], 0.78, 0.78, 0.78)
        GameTooltip:Show()
    end)
    helpBtn:SetScript("OnLeave", function(self)
        self:SetAlpha(0.55); GameTooltip:Hide()
    end)

    local countY = -(TITLE_H + 4 + MANUAL_H + MANUAL_GAP + 2)
    local countLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countLabel:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, countY)
    countLabel:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, countY)
    countLabel:SetJustifyH("LEFT"); countLabel:SetTextColor(0.50, 0.50, 0.55)
    countLabel:SetText(string.format(L["REFBOX_COUNT"], 0, 0))
    f._countLabel = countLabel

    local scrollTop = -(TITLE_H + 4 + MANUAL_H + MANUAL_GAP + COUNT_H + 4)
    local sf = CreateFrame("ScrollFrame", nil, f, "ScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     f, "TOPLEFT",    0,           scrollTop)
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -SCROLL_PAD, BOTTOM_PAD)

    if sf.ScrollBar then
        sf.ScrollBar:SetAlpha(0)
        sf:HookScript("OnScrollRangeChanged", function(_, _, yr)
            sf.ScrollBar:SetAlpha((yr or 0) > 1 and 1.0 or 0)
        end)
    end

    local sc = CreateFrame("Frame", nil, sf)
    sc:SetWidth(sf:GetWidth()); sc:SetHeight(1)
    sf:SetScrollChild(sc)
    sf:SetScript("OnSizeChanged", function(self) sc:SetWidth(self:GetWidth()) end)

    -- Empty label lives inside the scroll child so it scrolls with gear sections.
    local emptyLabel = sc:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    emptyLabel:SetPoint("TOPLEFT",  sc, "TOPLEFT",  PAD, -8)
    emptyLabel:SetPoint("TOPRIGHT", sc, "TOPRIGHT", -PAD, -8)
    emptyLabel:SetJustifyH("CENTER")
    emptyLabel:SetTextColor(0.38, 0.38, 0.42)
    emptyLabel:SetText(L["REFBOX_EMPTY"])
    f._emptyLabel = emptyLabel


    WireDragDrop(f); WireDragDrop(sc)

    f._scrollFrame = sf; f._scrollChild = sc

    BuildModelViewer(f)
    BuildTaskPanel(f)
    BuildExternalModeStrip()

    f:SetScript("OnShow", function()
        EnsureItemInfoListener(); InstallShiftHooks(); RenderList()
    end)
    f:SetScript("OnHide", function()
        ReleaseAllRows()
        if _pickerFrame and _pickerFrame:IsShown() then _pickerFrame:Hide() end
        if f._manualBox then f._manualBox:SetRealText("") end
    end)

    f:Hide()
    return f
end

-- ── Build window (SKIN VERSION) ───────────────────────────────────────────────

local function BuildReferenceBoxSkin()
    local f = BNB.CreateSkinFrame(UIParent, false, "BigNoteBoxReferenceBoxFrame", false)
    _G["BigNoteBoxReferenceBoxFrame"] = f
    f:SetWidth(RBW)
    f:SetToplevel(true)
    f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self)
        self:StopMovingOrSizing()
        PositionModeStrip()
    end)

    -- Title strip
    local titleBar = BNB.CreateSkinStrip(f, true, false)
    titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    titleBar:SetHeight(SK_RB_TITLE_H)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
    titleBar:SetScript("OnDragStop",  function()
        f:StopMovingOrSizing()
        PositionModeStrip()
    end)

    local titleLbl = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleLbl:SetPoint("LEFT",  titleBar, "LEFT",  8, 0)
    titleLbl:SetPoint("RIGHT", titleBar, "RIGHT", -30, 0)
    titleLbl:SetJustifyH("LEFT")
    titleLbl:SetTextColor(1, 0.82, 0)
    titleLbl:SetText(L["REFBOX_TITLE"])
    f._titleLbl = titleLbl  -- used by SetTitle()

    local closeBtn = BNB.CreateSkinCloseButton(titleBar, function() BNB.CloseReferenceBox() end)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -3, 0)

    -- ── Manual entry strip ───────────────────────────────────────────────────
    local manualStrip = CreateFrame("Frame", nil, f)
    manualStrip:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, -(SK_RB_TITLE_H + 4))
    manualStrip:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -(SK_RB_TITLE_H + 4))
    manualStrip:SetHeight(MANUAL_H)

    local eb = CreateFrame("EditBox", nil, manualStrip, "BackdropTemplate")
    BNB.EnsureBackdrop(eb)
    BNB.SetBackdrop(eb, 0.04, 0.04, 0.06, 0.90, 0.18, 0.18, 0.22, 1)
    eb:SetPoint("TOPLEFT",  manualStrip, "TOPLEFT",  0, 0)
    eb:SetPoint("TOPRIGHT", manualStrip, "TOPRIGHT", -68, 0)
    eb:SetHeight(MANUAL_H)
    eb:SetAutoFocus(false); eb:SetMultiLine(false); eb:SetMaxLetters(256)
    eb:SetFontObject("GameFontNormalSmall"); eb:SetTextInsets(6, 6, 2, 2)
    BNB.AddPlaceholder(eb, L["REFBOX_PLACEHOLDER"], 0.4, 0.4, 0.45)
    eb:SetScript("OnEnterPressed", function(self)
        CommitManualEntry(self:GetRealText()); self:SetRealText(""); self:ClearFocus()
    end)
    eb:SetScript("OnEscapePressed", function(self)
        self:SetRealText(""); self:ClearFocus()
    end)
    f._manualBox = eb

    local addBtn = BNB.CreateButton(nil, manualStrip, L["REFBOX_ADD_BTN"], 40, MANUAL_H)
    addBtn:SetPoint("TOPRIGHT", manualStrip, "TOPRIGHT", -24, 0)
    addBtn:SetScript("OnClick", function()
        if IsLocked(_noteID) then BNB:Print(L["REFBOX_LOCKED"]); return end
        CommitManualEntry(eb:GetRealText()); eb:SetRealText(""); eb:ClearFocus()
    end)
    f._addBtn = addBtn

    local helpBtn = CreateFrame("Button", nil, manualStrip)
    helpBtn:SetSize(20, MANUAL_H)
    helpBtn:SetPoint("TOPRIGHT", manualStrip, "TOPRIGHT", 0, 0)
    local helpTex = helpBtn:CreateTexture(nil, "ARTWORK")
    helpTex:SetSize(20, 20)
    helpTex:SetPoint("CENTER", helpBtn, "CENTER", 0, 0)
    helpTex:SetTexture(ASSETS .. "UI\\ui-info")
    helpBtn:SetAlpha(0.55)
    helpBtn:SetScript("OnEnter", function(self)
        self:SetAlpha(1.0)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(L["REFBOX_INFO_TITLE"], 1, 0.82, 0)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["REFBOX_INFO_BARE"],  0.85, 0.85, 0.85)
        GameTooltip:AddLine(L["REFBOX_INFO_SPELL"], 0.85, 0.85, 0.85)
        GameTooltip:AddLine(L["REFBOX_INFO_QUEST"], 0.85, 0.85, 0.85)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["REFBOX_INFO_ALSO"],  1, 0.82, 0)
        GameTooltip:AddLine(L["REFBOX_INFO_DRAG"],  0.78, 0.78, 0.78)
        GameTooltip:AddLine(L["REFBOX_INFO_SHIFT"], 0.78, 0.78, 0.78)
        GameTooltip:Show()
    end)
    helpBtn:SetScript("OnLeave", function(self)
        self:SetAlpha(0.55); GameTooltip:Hide()
    end)

    local countY = -(SK_RB_TITLE_H + 4 + MANUAL_H + MANUAL_GAP + 2)
    local countLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countLabel:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, countY)
    countLabel:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, countY)
    countLabel:SetJustifyH("LEFT"); countLabel:SetTextColor(0.50, 0.50, 0.55)
    countLabel:SetText(string.format(L["REFBOX_COUNT"], 0, 0))
    f._countLabel = countLabel

    local scrollTop = -(SK_RB_TITLE_H + 4 + MANUAL_H + MANUAL_GAP + COUNT_H + 4)
    local sf = CreateFrame("ScrollFrame", nil, f, "ScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     f, "TOPLEFT",    0,           scrollTop)
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -SCROLL_PAD, BOTTOM_PAD)

    if sf.ScrollBar then
        sf.ScrollBar:SetAlpha(0)
        sf:HookScript("OnScrollRangeChanged", function(_, _, yr)
            sf.ScrollBar:SetAlpha((yr or 0) > 1 and 1.0 or 0)
        end)
    end

    local sc = CreateFrame("Frame", nil, sf)
    sc:SetWidth(sf:GetWidth()); sc:SetHeight(1)
    sf:SetScrollChild(sc)
    sf:SetScript("OnSizeChanged", function(self) sc:SetWidth(self:GetWidth()) end)

    -- Empty label lives inside the scroll child so it scrolls with gear sections.
    local emptyLabel = sc:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    emptyLabel:SetPoint("TOPLEFT",  sc, "TOPLEFT",  PAD, -8)
    emptyLabel:SetPoint("TOPRIGHT", sc, "TOPRIGHT", -PAD, -8)
    emptyLabel:SetJustifyH("CENTER")
    emptyLabel:SetTextColor(0.38, 0.38, 0.42)
    emptyLabel:SetText(L["REFBOX_EMPTY"])
    f._emptyLabel = emptyLabel


    WireDragDrop(f); WireDragDrop(sc)

    f._scrollFrame = sf; f._scrollChild = sc

    BuildModelViewer(f)
    BuildTaskPanel(f)
    BuildExternalModeStrip()

    f:SetScript("OnShow", function()
        EnsureItemInfoListener(); InstallShiftHooks(); RenderList()
        if BNB.ApplyMainWindowSkin then BNB.ApplyMainWindowSkin() end
    end)
    f:SetScript("OnHide", function()
        ReleaseAllRows()
        if _pickerFrame and _pickerFrame:IsShown() then _pickerFrame:Hide() end
        if f._manualBox then f._manualBox:SetRealText("") end
    end)

    f:Hide()
    return f
end

-- ── Position / size ───────────────────────────────────────────────────────────
-- ── Content-height calculation ─────────────────────────────────────────────────
-- Called after RenderList so the window shrinks/grows with item count.
-- Height = title + manual strip + gap + count label + scroll content, clamped
-- to the main window height (same cap as ConfigWindow).
SyncRefBoxHeight = function()
    if not rbFrame then return end

    -- Always match the main window height — gives room for tasks, model, and attachments.
    local maxH = (BNB.mainFrame and BNB.mainFrame:GetHeight())
    local desired = (maxH and maxH > 100) and maxH or 700
    local cur = rbFrame:GetHeight()
    if cur and math.abs(cur - desired) > 2 then
        rbFrame:SetHeight(desired)
    end
end
BNB._SyncRefBoxHeight = SyncRefBoxHeight  -- exposed for RenderList hook

-- ── Model Viewer (inspect notes only) ─────────────────────────────────────────
-- Creates the model frame. Shared between both BuildReferenceBox and
-- BuildReferenceBoxSkin — called once after the scroll frame is created.
-- Components are hidden by default and shown by UpdateModelViewer.

BuildModelViewer = function(f)
    -- DressUpModel frame (below the item list, fills bottom portion of refbox)
    local model = CreateFrame("DressUpModel", nil, f)
    model:SetFrameLevel(f:GetFrameLevel() + 2)
    model:EnableMouseWheel(true)
    model:EnableMouse(true)
    model:Hide()

    -- Parchment background texture (stretched, 70% transparent)
    local bgTex = model:CreateTexture(nil, "BACKGROUND")
    bgTex:SetAllPoints(model)
    bgTex:SetTexture(ASSETS .. "UI\\ui-bg-parchment")
    bgTex:SetAlpha(0.30)
    model._bgTex = bgTex

    -- Mouse drag: left = rotate, right = pan X/Y
    local rotating = false
    local panning  = false
    local lastX, lastY = 0, 0
    model:SetScript("OnMouseDown", function(self, btn)
        local cx, cy = GetCursorPosition()
        local scale = self:GetEffectiveScale()
        cx, cy = cx / scale, cy / scale
        if btn == "LeftButton" then
            rotating = true
            lastX = cx
        elseif btn == "RightButton" then
            panning = true
            lastX, lastY = cx, cy
        end
    end)
    model:SetScript("OnMouseUp", function(self, btn)
        if btn == "LeftButton" then rotating = false end
        if btn == "RightButton" then panning = false end
    end)
    model:SetScript("OnUpdate", function(self)
        local cx, cy = GetCursorPosition()
        local scale = self:GetEffectiveScale()
        cx, cy = cx / scale, cy / scale
        if rotating then
            local dx = (cx - lastX) * 0.01
            lastX = cx
            local facing = self:GetFacing() or 0
            self:SetFacing(facing + dx)
        end
        if panning then
            local dx = (cx - lastX) * 0.01
            local dy = (cy - lastY) * 0.01
            lastX, lastY = cx, cy
            local px, py, pz = self:GetPosition()
            self:SetPosition(px, py + dx, pz + dy)
        end
    end)

    -- Scroll wheel to zoom
    model:SetScript("OnMouseWheel", function(self, delta)
        local scale = self:GetModelScale() or 1
        if delta > 0 then
            scale = math.min(scale * 1.1, 4.0)
        else
            scale = math.max(scale * 0.9, 0.3)
        end
        self:SetModelScale(scale)
    end)

    -- Placeholder label for when target is out of range
    local placeholder = model:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    placeholder:SetPoint("CENTER", model, "CENTER", 0, 0)
    placeholder:SetWidth(RBW - 40)
    placeholder:SetJustifyH("CENTER")
    placeholder:SetTextColor(0.55, 0.55, 0.60)
    placeholder:SetText("Target this player again\nto view their character model")
    placeholder:Hide()

    -- "Live" indicator label
    local liveLabel = model:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    liveLabel:SetPoint("TOPLEFT", model, "TOPLEFT", 6, -4)
    liveLabel:SetTextColor(0.3, 1.0, 0.3, 0.8)
    liveLabel:SetText("LIVE")
    liveLabel:Hide()

    -- ── Model hide/show toggle buttons ───────────────────────────────────────
    -- "Hide model" button (bt-down) — top-right corner of the model viewer frame.
    -- Clicking hides the model, restores scroll area to full height.
    local BTN_SZ = 24
    local hideBtn = CreateFrame("Button", nil, model)
    hideBtn:SetSize(BTN_SZ, BTN_SZ)
    hideBtn:SetPoint("TOPRIGHT", model, "TOPRIGHT", -4, -4)
    hideBtn:SetFrameLevel(model:GetFrameLevel() + 4)
    hideBtn:SetHighlightTexture(""); hideBtn:SetPushedTexture("")
    local hbN = hideBtn:CreateTexture(nil, "ARTWORK"); hbN:SetAllPoints()
    hbN:SetTexture(ASSETS .. "Buttons\\bt-down-normal")
    local hbH = hideBtn:CreateTexture(nil, "ARTWORK"); hbH:SetAllPoints()
    hbH:SetTexture(ASSETS .. "Buttons\\bt-down-hover"); hbH:Hide()
    local hbP = hideBtn:CreateTexture(nil, "ARTWORK"); hbP:SetAllPoints()
    hbP:SetTexture(ASSETS .. "Buttons\\bt-down-press"); hbP:Hide()
    hideBtn:SetScript("OnMouseDown", function(self) if self:IsEnabled() then hbP:Show(); hbN:Hide(); hbH:Hide() end end)
    hideBtn:SetScript("OnMouseUp",   function(self) hbP:Hide(); if self:IsEnabled() then hbH:Show() else hbN:Show() end end)
    hideBtn:SetScript("OnEnter", function(self)
        if self:IsEnabled() then hbN:Hide(); hbH:Show() end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Hide Model Viewer", 1, 1, 1)
        GameTooltip:AddLine("Click to collapse the 3D model", 0.78, 0.78, 0.78)
        GameTooltip:Show()
    end)
    hideBtn:SetScript("OnLeave", function() hbP:Hide(); hbH:Hide(); hbN:Show(); GameTooltip:Hide() end)
    hideBtn:SetScript("OnClick", function()
        if _noteID then _modelHidden[_noteID] = true end
        if rbFrame then RenderList() end
    end)
    hideBtn:Hide()  -- shown by UpdateModelViewer when model is visible

    -- "Show model" button (bt-up) — bottom-right corner of the refbox scroll area.
    -- Only visible when model data exists but the user has hidden the viewer.
    local showBtn = CreateFrame("Button", nil, f)
    showBtn:SetSize(BTN_SZ, BTN_SZ)
    showBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -18, BOTTOM_PAD + 4)
    showBtn:SetFrameLevel(f:GetFrameLevel() + 20)
    showBtn:SetHighlightTexture(""); showBtn:SetPushedTexture("")
    local sbN = showBtn:CreateTexture(nil, "ARTWORK"); sbN:SetAllPoints()
    sbN:SetTexture(ASSETS .. "Buttons\\bt-up-normal")
    local sbH = showBtn:CreateTexture(nil, "ARTWORK"); sbH:SetAllPoints()
    sbH:SetTexture(ASSETS .. "Buttons\\bt-up-hover"); sbH:Hide()
    local sbP = showBtn:CreateTexture(nil, "ARTWORK"); sbP:SetAllPoints()
    sbP:SetTexture(ASSETS .. "Buttons\\bt-up-press"); sbP:Hide()
    showBtn:SetScript("OnMouseDown", function(self) if self:IsEnabled() then sbP:Show(); sbN:Hide(); sbH:Hide() end end)
    showBtn:SetScript("OnMouseUp",   function(self) sbP:Hide(); if self:IsEnabled() then sbH:Show() else sbN:Show() end end)
    showBtn:SetScript("OnEnter", function(self)
        if self:IsEnabled() then sbN:Hide(); sbH:Show() end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Show Model Viewer", 1, 1, 1)
        GameTooltip:AddLine("Click to restore the 3D model", 0.78, 0.78, 0.78)
        GameTooltip:Show()
    end)
    showBtn:SetScript("OnLeave", function() sbP:Hide(); sbH:Hide(); sbN:Show(); GameTooltip:Hide() end)
    showBtn:SetScript("OnClick", function()
        if _noteID then _modelHidden[_noteID] = nil end
        if rbFrame then RenderList() end
    end)
    showBtn:Hide()  -- shown by UpdateModelViewer when model is hidden but available

    -- ── Gear view toggle button (bt-gearview) ────────────────────────────────
    -- Visible in reconstructed mode: toggles dress-up between transmog and
    -- base gear. Visible but disabled in live mode (live already shows transmog).
    local gearBtn = CreateFrame("Button", nil, model)
    gearBtn:SetSize(BTN_SZ, BTN_SZ)
    gearBtn:SetPoint("BOTTOMLEFT", model, "BOTTOMLEFT", 4, 4)
    gearBtn:SetFrameLevel(model:GetFrameLevel() + 4)
    gearBtn:SetHighlightTexture(""); gearBtn:SetPushedTexture("")
    local gbN = gearBtn:CreateTexture(nil, "ARTWORK"); gbN:SetAllPoints()
    gbN:SetTexture(ASSETS .. "Buttons\\bt-gearview-normal")
    local gbH = gearBtn:CreateTexture(nil, "ARTWORK"); gbH:SetAllPoints()
    gbH:SetTexture(ASSETS .. "Buttons\\bt-gearview-hover"); gbH:Hide()
    local gbP = gearBtn:CreateTexture(nil, "ARTWORK"); gbP:SetAllPoints()
    gbP:SetTexture(ASSETS .. "Buttons\\bt-gearview-press"); gbP:Hide()
    gearBtn:SetScript("OnMouseDown", function(self)
        if self:IsEnabled() then gbP:Show(); gbN:Hide(); gbH:Hide() end
    end)
    gearBtn:SetScript("OnMouseUp", function(self)
        gbP:Hide()
        if self:IsEnabled() then gbH:Show() else gbN:Show() end
    end)
    gearBtn:SetScript("OnEnter", function(self)
        if self:IsEnabled() then gbN:Hide(); gbH:Show() end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        local isTmog = _noteID and (_gearViewTmog[_noteID] ~= false)
        if self:IsEnabled() then
            GameTooltip:AddLine(isTmog and L["REFBOX_MV_GEAR_TMOG"] or L["REFBOX_MV_GEAR_REG"], 1, 1, 1)
            GameTooltip:AddLine("Click to switch to " .. (isTmog and L["REFBOX_MV_GEAR_REG"] or L["REFBOX_MV_GEAR_TMOG"]), 0.78, 0.78, 0.78)
        else
            GameTooltip:AddLine(L["REFBOX_MV_GEAR_TMOG"], 1, 1, 1)
            GameTooltip:AddLine("Live mode shows actual appearance", 0.78, 0.78, 0.78)
        end
        GameTooltip:Show()
    end)
    gearBtn:SetScript("OnLeave", function() gbP:Hide(); gbH:Hide(); gbN:Show(); GameTooltip:Hide() end)
    gearBtn:SetScript("OnClick", function()
        if not _noteID then return end
        -- Toggle: nil/true = transmog, false = regular.
        local wasTmog = (_gearViewTmog[_noteID] ~= false)
        _gearViewTmog[_noteID] = not wasTmog
        UpdateModelViewer()
    end)
    gearBtn:Hide()
    f._modelGearBtn = gearBtn

    -- Secondary label: "Transmog gear" / "Regular gear" — shown below the LIVE/RECONSTRUCTED label.
    local gearLabel = model:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    gearLabel:SetPoint("TOPLEFT", liveLabel, "BOTTOMLEFT", 0, -2)
    gearLabel:SetTextColor(0.75, 0.75, 0.75, 0.8)
    gearLabel:Hide()
    f._modelGearLabel = gearLabel

    f._modelFrame        = model
    f._modelPlaceholder  = placeholder
    f._modelLiveLabel    = liveLabel
    f._modelHideBtn      = hideBtn
    f._modelShowBtn      = showBtn
    f._modelGearBtn      = gearBtn
    f._modelGearLabel    = gearLabel
    f._modelSplit        = MODEL_SPLIT_DEFAULT
end

-- Apply the fixed split ratio to the scroll frame and model positions
ApplyModelLayout = function(f)
    if not f or not f._scrollFrame or not f._modelFrame then return end
    local sf  = f._scrollFrame
    local mdl = f._modelFrame

    -- Total available height = from scroll frame top to frame bottom
    local sfTop = sf:GetTop()
    local fBot  = f:GetBottom()
    if not sfTop or not fBot then return end
    local totalH = sfTop - fBot - BOTTOM_PAD
    if totalH < 1 then return end

    local split = f._modelSplit or MODEL_SPLIT_DEFAULT
    local itemH = math.max(MODEL_SPLIT_MIN_PX, math.floor(totalH * split))
    local modelH = math.max(MODEL_MIN_H, totalH - itemH)
    -- Recalculate itemH in case modelH was clamped
    itemH = totalH - modelH

    -- Scroll frame: anchor top is unchanged, set bottom above the model
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -SCROLL_PAD, BOTTOM_PAD + modelH)

    -- Model: fills the bottom, inset to stay inside the frame border
    local isSkin = BigNoteBoxDB and BigNoteBoxDB.skinMode
    local insetL = isSkin and 5 or 7
    local insetR = isSkin and 2 or 4
    local insetB = isSkin and 0 or 0
    mdl:ClearAllPoints()
    mdl:SetPoint("TOPLEFT",     f, "BOTTOMLEFT",   insetL, BOTTOM_PAD + modelH)
    mdl:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -insetR, BOTTOM_PAD + insetB)

    -- Update scroll child width
    local sc = f._scrollChild
    if sc then sc:SetWidth(sf:GetWidth()) end
end

-- Show/hide model viewer based on current note; load model if needed
UpdateModelViewer = function()
    if not rbFrame then return end
    local isInspect = IsInspectNote(_noteID)

    local mdl      = rbFrame._modelFrame
    local ph       = rbFrame._modelPlaceholder
    local ll       = rbFrame._modelLiveLabel
    local hideBtn  = rbFrame._modelHideBtn
    local showBtn  = rbFrame._modelShowBtn
    local gearBtn  = rbFrame._modelGearBtn
    local gearLbl  = rbFrame._modelGearLabel

    if not mdl then return end

    -- Suppress model whenever we're in tasks/attachments mode on an inspect note
    if isInspect and _rbMode == "attachments" then
        mdl:Hide()
        if ph      then ph:Hide()      end
        if ll      then ll:Hide()      end
        if hideBtn then hideBtn:Hide() end
        if showBtn then showBtn:Hide() end
        if gearBtn then gearBtn:Hide() end
        if gearLbl then gearLbl:Hide() end
        return
    end

    -- Not an inspect/target-model note — hide everything, restore scroll frame
    if not isInspect then
        mdl:Hide()
        if ph      then ph:Hide()      end
        if ll      then ll:Hide()      end
        if hideBtn then hideBtn:Hide() end
        if showBtn then showBtn:Hide() end
        if gearBtn then gearBtn:Hide() end
        if gearLbl then gearLbl:Hide() end
        local sf = rbFrame._scrollFrame
        if sf then
            sf:SetPoint("BOTTOMRIGHT", rbFrame, "BOTTOMRIGHT", -SCROLL_PAD, BOTTOM_PAD)
        end
        return
    end

    -- Note has model data — check if the user has hidden the viewer for this note
    if _noteID and _modelHidden[_noteID] then
        mdl:Hide()
        if ph      then ph:Hide()      end
        if ll      then ll:Hide()      end
        if hideBtn then hideBtn:Hide() end
        if showBtn then showBtn:Show() end
        if gearBtn then gearBtn:Hide() end
        if gearLbl then gearLbl:Hide() end
        local sf = rbFrame._scrollFrame
        if sf then
            sf:SetPoint("BOTTOMRIGHT", rbFrame, "BOTTOMRIGHT", -SCROLL_PAD, BOTTOM_PAD)
        end
        return
    end

    -- Show model, hide the "show" button, show the "hide" button
    mdl:Show()
    if hideBtn then hideBtn:Show() end
    if showBtn then showBtn:Hide() end

    -- Apply layout
    ApplyModelLayout(rbFrame)

    -- Try live mode first: check if the inspected player is our current target
    local note = BNB.GetNote(_noteID)
    local inspName  = note and note.inspectName
    local tgtName = UnitName("target")

    local isLive = false
    if tgtName and inspName and tgtName == inspName then
        if UnitIsPlayer("target") then
            isLive = true
        end
    end

    if isLive then
        -- Live mode: show the actual target model (includes transmog appearance).
        -- Gear view toggle is visible but disabled — live already shows real transmog.
        pcall(function() mdl:SetUnit("target") end)
        mdl:SetPosition(0, 0, 0)
        mdl:SetModelScale(1)
        mdl:SetFacing(0)
        if ph then ph:Hide() end
        if ll then
            ll:SetText("LIVE")
            ll:SetTextColor(0.3, 1.0, 0.3, 0.8)
            ll:Show()
        end
        if gearBtn then
            gearBtn:SetEnabled(false)
            gearBtn:SetAlpha(0.35)
            gearBtn:Show()
        end
        if gearLbl then
            gearLbl:SetText(L["REFBOX_MV_GEAR_TMOG"])
            gearLbl:Show()
        end
    elseif note and note.inspectRaceID and note.inspectSexID ~= nil then
        -- Reconstructed mode: build model from stored race + gear.
        -- Gear view toggle switches between transmog appearances and base item IDs.
        local showTmog = (_noteID == nil) or (_gearViewTmog[_noteID] ~= false)

        -- Attempt 1: SetUnit("none") + SetCustomRace for correct race model
        local modelLoaded = false
        pcall(function()
            mdl:SetUnit("none")
            mdl:SetCustomRace(note.inspectRaceID, note.inspectSexID)
            local fileID = mdl:GetModelFileID()
            if fileID and fileID ~= 0 then modelLoaded = true end
        end)

        -- Attempt 2: if that produced nothing, fall back to player model undressed
        if not modelLoaded then
            pcall(function()
                mdl:SetUnit("player")
                mdl:Undress()
            end)
        end

        -- Dress up based on gear view toggle state.
        local tmog = note.inspectTransmogAppearances
        if showTmog and tmog and next(tmog) then
            -- Transmog view: use stored appearance IDs.
            for _, appearanceID in pairs(tmog) do
                pcall(function() mdl:TryOn(appearanceID) end)
            end
        elseif not showTmog and note.inspectGearItems and #note.inspectGearItems > 0 then
            -- Regular view: use base item IDs from inspectGearItems.
            for _, g in ipairs(note.inspectGearItems) do
                if g.id then
                    pcall(function() mdl:TryOn("item:" .. g.id) end)
                end
            end
        elseif not showTmog then
            -- Fallback for old notes: use attachments as base gear.
            local attachments = GetAttachments(_noteID) or {}
            for _, att in ipairs(attachments) do
                if att.type == "item" and att.id then
                    pcall(function() mdl:TryOn("item:" .. att.id) end)
                end
            end
        else
            -- No transmog data at all (old note captured before transmog feature).
            local attachments = GetAttachments(_noteID) or {}
            for _, att in ipairs(attachments) do
                if att.type == "item" and att.id then
                    pcall(function() mdl:TryOn("item:" .. att.id) end)
                end
            end
        end

        mdl:SetPosition(0, 0, 0)
        mdl:SetModelScale(1)
        mdl:SetFacing(0)
        if ph then ph:Hide() end
        if ll then
            if not (tmog and next(tmog)) and showTmog then
                ll:SetText("RECONSTRUCTED\n(Target this player to see their transmog)")
            else
                ll:SetText("RECONSTRUCTED")
            end
            ll:SetTextColor(0.75, 0.75, 0.75, 0.8)
            ll:Show()
        end
        -- Gear toggle button: enabled only when transmog data is available.
        if gearBtn then
            local hasTmog = tmog and next(tmog)
            gearBtn:SetEnabled(hasTmog ~= nil)
            gearBtn:SetAlpha(hasTmog and 1.0 or 0.35)
            gearBtn:Show()
        end
        if gearLbl then
            gearLbl:SetText(showTmog and L["REFBOX_MV_GEAR_TMOG"] or L["REFBOX_MV_GEAR_REG"])
            gearLbl:Show()
        end
    elseif note and note.targetNpcID then
        -- Target note: NPC / mob / boss rendered via SetCreature(npcID).
        -- npcID is the creature ID extracted from the GUID at note creation.
        -- SetCreature works offline without a live unit present.
        -- Note: combat pets are excluded by IsInspectNote (targetIsPet check).
        local creatureID = tonumber(note.targetNpcID)
        if creatureID then
            pcall(function()
                mdl:SetCreature(creatureID)
            end)
            mdl:SetPosition(0, 0, 0)
            mdl:SetModelScale(1)
            mdl:SetFacing(0)
            if ph then ph:Hide() end
            if ll then ll:Hide() end
        else
            -- Invalid creature ID — show placeholder
            mdl:SetUnit("none")
            mdl:SetFacing(0)
            if ph then ph:Show() end
            if ll then ll:Hide() end
        end
        if gearBtn then gearBtn:Hide() end
        if gearLbl then gearLbl:Hide() end
    else
        -- No model data — show placeholder
        mdl:SetUnit("none")
        mdl:SetFacing(0)
        if ph then ph:Show() end
        if ll then ll:Hide() end
        if gearBtn then gearBtn:Hide() end
        if gearLbl then gearLbl:Hide() end
    end
end
local function PositionFrame()
    if not rbFrame then return end
    rbFrame:ClearAllPoints()
    local side = (BigNoteBoxDB and BigNoteBoxDB.refboxSide) or "left"
    if BNB.mainFrame and BNB.mainFrame:IsShown() then
        if side == "right" then
            rbFrame:SetPoint("TOPLEFT", BNB.mainFrame, "TOPRIGHT", 8, 0)
        else
            rbFrame:SetPoint("TOPRIGHT", BNB.mainFrame, "TOPLEFT", -8, 0)
        end
    else
        rbFrame:SetPoint("CENTER", UIParent, "CENTER", -200, 0)
    end
    SyncRefBoxHeight()
    PositionModeStrip()
end

local function HookMainWindowResize()
    if not BNB.mainFrame then return end
    BNB.mainFrame:HookScript("OnSizeChanged", function(self)
        if rbFrame and rbFrame:IsShown() then SyncRefBoxHeight() end
    end)
    -- Keep the external mode strip anchored below rbFrame after any move/resize
    if rbFrame then
        rbFrame:HookScript("OnSizeChanged", function()
            PositionModeStrip()
        end)
    end
end

-- Returns the dynamic title string based on what the current note contains.
UpdateDynamicTitle = function()
    if not rbFrame then return end
    local hasTasks   = BNB.Task and BNB.Task.HasTasks(_noteID)
    local hasModel   = IsInspectNote(_noteID)
    local note       = _noteID and BNB.GetNote(_noteID)
    local hasAtts    = note and note.attachments and #note.attachments > 0

    local title
    if hasTasks and hasModel then
        if _rbMode == "model" then
            title = "Tasks + Model"
        else
            title = "Tasks + Reference"
        end
    elseif hasTasks and hasAtts then
        title = "Tasks + Reference"
    elseif hasTasks then
        title = "Tasks"
    elseif hasModel then
        title = "Reference + Model"
    else
        title = L["REFBOX_TITLE"]
    end

    if rbFrame.SetTitle then
        rbFrame:SetTitle(title)
    elseif rbFrame._titleLbl then
        rbFrame._titleLbl:SetText(title)
    end
end

local function SetTitle(noteID)
    -- Kept for compatibility — just delegates to UpdateDynamicTitle.
    UpdateDynamicTitle()
end

-- ── Public API ────────────────────────────────────────────────────────────────
function BNB.OpenReferenceBox(noteID)
    if DB().referenceBoxEnabled == false then return end
    if not rbFrame then
        if BigNoteBoxDB and BigNoteBoxDB.skinMode then
            rbFrame = BuildReferenceBoxSkin()
        else
            rbFrame = BuildReferenceBox()
        end
        HookMainWindowResize()
        RegisterTaskCallback()
    end
    _noteID = noteID or BNB._currentNoteID
    -- Reset to model mode on every note switch for inspect notes
    _rbMode = IsInspectNote(_noteID) and "model" or "attachments"
    SetTitle(_noteID)
    PositionFrame()
    BuildExternalModeStrip()
    PositionModeStrip()
    UpdateModeStrip()
    if not rbFrame:IsShown() then rbFrame:Show() else RenderList() end
end

function BNB.CloseReferenceBox()
    if rbFrame then rbFrame:Hide() end
    if _modeStrip then _modeStrip:Hide() end
end

function BNB.ToggleReferenceBox()
    if DB().referenceBoxEnabled == false then
        BNB:Print(L["REFBOX_DISABLED"])
        return
    end
    if rbFrame and rbFrame:IsShown() then
        BNB.CloseReferenceBox()
    else
        BNB.OpenReferenceBox(BNB._currentNoteID)
    end
end

-- Called by SelectNote on every note switch.
-- Auto-opens if configured and note has attachments. Never auto-closes.
function BNB.SyncReferenceBox(noteID)
    if not noteID then
        if rbFrame and rbFrame:IsShown() then rbFrame:Hide() end
        return
    end
    -- Reset gear view to transmog (default) whenever the note changes.
    if _noteID ~= noteID then
        _gearViewTmog[noteID] = nil
    end
    _noteID = noteID

    -- Auto-open: notes with attachments (inspect notes with gear), or target notes
    -- with a stored NPC ID (model viewer via SetCreature, no attachments needed).
    local note = NDB() and NDB().notes and NDB().notes[noteID]
    local isTargetWithModel = note and note.source == "target" and note.targetNpcID ~= nil and not note.targetIsPet
    -- Inspect notes always warrant opening: they have a model viewer and gear sections
    -- even when note.attachments is empty (gear lives in inspectGearItems now).
    local isInspectModel = note and note.source == "inspect" and note.inspectRaceID ~= nil

    local hasTasks = BNB.Task and BNB.Task.HasTasks(noteID)

    if DB().refboxAutoOpen and DB().referenceBoxEnabled ~= false
       and BNB.mainFrame and BNB.mainFrame:IsShown() then
        local atts = GetAttachments(noteID)
        local shouldOpen = (atts and #atts > 0) or isTargetWithModel or isInspectModel or hasTasks
        if shouldOpen then
            if not rbFrame then
                if BigNoteBoxDB and BigNoteBoxDB.skinMode then
                    rbFrame = BuildReferenceBoxSkin()
                else
                    rbFrame = BuildReferenceBox()
                end
                HookMainWindowResize()
                RegisterTaskCallback()
            end
            if not rbFrame:IsShown() then
                _rbMode = IsInspectNote(noteID) and "model" or "attachments"
                SetTitle(noteID)
                PositionFrame()
                rbFrame:Show()
                return   -- OnShow fires RenderList
            end
        end
    end

    -- Already open: update title + content, or close if the new note has nothing
    if rbFrame and rbFrame:IsShown() then
        local atts = GetAttachments(noteID)
        if DB().refboxAutoOpen and (not atts or #atts == 0) and not isTargetWithModel and not isInspectModel and not hasTasks then
            rbFrame:Hide()
            if _modeStrip then _modeStrip:Hide() end
            return
        end
        -- Reset mode for new note
        _rbMode = IsInspectNote(noteID) and "model" or "attachments"
        UpdateModeStrip()
        SetTitle(noteID)
        RenderList()
    end
end

function BNB.RefreshReferenceBox()
    if not rbFrame or not rbFrame:IsShown() then return end
    RenderList()
end

-- Update model viewer when target changes (live mode toggle)
BNB.RegisterEvent("PLAYER_TARGET_CHANGED", function()
    if not rbFrame or not rbFrame:IsShown() then return end
    if IsInspectNote(_noteID) then
        C_Timer.After(0.1, UpdateModelViewer)
    end
end)

-- Wrap CloseCompanionWindows
local _origClose = BNB.CloseCompanionWindows
BNB.CloseCompanionWindows = function()
    if rbFrame and rbFrame:IsShown() then rbFrame:Hide() end
    if _origClose then _origClose() end
end

--------------------------------------------------------------------------------
-- Public: add an attachment to a note from outside this module (e.g. QuickNote)
--------------------------------------------------------------------------------
function BNB.RBAddAttachment(noteID, att)
    AddAttachment(noteID, att)
end

--------------------------------------------------------------------------------
-- Feature B: show ItemID / SpellID / QuestID in the game's native tooltip.
-- Controlled by BigNoteBoxDB.refboxShowIDs (default false).
-- Adds a single "BNB: <id>" line in BNB green to the bottom of the tooltip.
-- This is a standalone QoL feature — it fires for every item/spell/quest
-- tooltip, not just those present in any note's attachments.
-- Uses TooltipDataProcessor.AddTooltipPostCall (retail API since 10.0.2).
--
-- All three callbacks use data.id (numeric) which is the canonical field
-- provided by the TooltipDataProcessor system for Item, Spell, and Quest
-- types. tooltip:Show() is called after AddDoubleLine to force the tooltip
-- to resize and display the added line.
--------------------------------------------------------------------------------
do
    local function ShouldShowIDs()
        return BigNoteBoxDB and BigNoteBoxDB.refboxShowIDs == true
    end

    local BNB_GREEN_R, BNB_GREEN_G, BNB_GREEN_B = 0.55, 0.82, 0.55

    -- Shared helper: add a blank line, then a labelled BNB ID line
    -- The blank line above gives visual separation from the game's own tooltip text.
    local _idBlockStarted = false  -- track if we've added the leading blank for this tooltip

    local function AddIDLine(tooltip, label, id)
        if not _idBlockStarted then
            tooltip:AddLine(" ")   -- blank line before first BNB line
            _idBlockStarted = true
        end
        tooltip:AddDoubleLine("BNB " .. label .. ":", tostring(id),
            BNB_GREEN_R, BNB_GREEN_G, BNB_GREEN_B,
            BNB_GREEN_R, BNB_GREEN_G, BNB_GREEN_B)
    end

    -- Refresh tooltip after all lines are added; reset block tracker
    local function Refresh(tooltip)
        tooltip:AddLine(" ")   -- blank line after last BNB line
        _idBlockStarted = false
        tooltip:Show()
    end

    -- Item tooltips: show ItemID + IconID
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        if not ShouldShowIDs() then return end
        local id = data and data.id
        if not id or id <= 0 then return end
        AddIDLine(tooltip, "ItemID", id)
        local icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
                  or select(10, GetItemInfo(id))
        if icon then
            AddIDLine(tooltip, "IconID", icon)
        end
        Refresh(tooltip)
    end)

    -- Spell tooltips: show SpellID + IconID
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tooltip, data)
        if not ShouldShowIDs() then return end
        local id = data and data.id
        if not id or id <= 0 then return end
        AddIDLine(tooltip, "SpellID", id)
        local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
        if icon then
            AddIDLine(tooltip, "IconID", icon)
        end
        Refresh(tooltip)
    end)

    -- Quest tooltips via TooltipDataProcessor: show QuestID only (no icon)
    if Enum and Enum.TooltipDataType and Enum.TooltipDataType.Quest then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Quest, function(tooltip, data)
            if not ShouldShowIDs() then return end
            local id = data and data.id
            if id and id > 0 then
                AddIDLine(tooltip, "QuestID", id)
                Refresh(tooltip)
            end
        end)
    end

    -- Quest log list tooltips: built by QuestMapLogTitleButton_OnEnter which
    -- calls GameTooltip:SetText() + AddLine() directly, bypassing both
    -- TooltipDataProcessor and SetHyperlink. The button has .questID.
    -- Hook the global function and append our ID line after the tooltip is built.
    if QuestMapLogTitleButton_OnEnter then
        hooksecurefunc("QuestMapLogTitleButton_OnEnter", function(self)
            if not ShouldShowIDs() then return end
            if self and self.questID and GameTooltip:IsShown() then
                AddIDLine(GameTooltip, "QuestID", self.questID)
                Refresh(GameTooltip)
            end
        end)
    end

    -- Chat quest links go through SetHyperlink("quest:XXXXX:...").
    -- Hook both GameTooltip and ItemRefTooltip to catch those.
    -- Skip quest links when TooltipDataProcessor.Quest is available — that hook
    -- already handles them, and firing both would show the ID line twice.
    local _tdpHandlesQuest = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Quest ~= nil
    local function OnSetHyperlink(tooltip, link)
        if not ShouldShowIDs() then return end
        if not link then return end
        local questID = link:match("^quest:(%d+)")
        if questID and not _tdpHandlesQuest then
            local id = tonumber(questID)
            if id and id > 0 then
                AddIDLine(tooltip, "QuestID", id)
                Refresh(tooltip)
            end
        end
    end
    hooksecurefunc(GameTooltip, "SetHyperlink", OnSetHyperlink)
    if ItemRefTooltip then
        hooksecurefunc(ItemRefTooltip, "SetHyperlink", OnSetHyperlink)
    end
end
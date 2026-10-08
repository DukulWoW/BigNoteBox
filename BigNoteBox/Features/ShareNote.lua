-- BigNoteBox Features/ShareNote.lua
-- Note sharing via compressed, printable share strings.
--
-- Pipeline (share):
--   Note fields of the ticked groups (BNB.CleanNoteFields, Core/NoteFields.lua)
--   -> LibSerialize -> CompressDeflate -> EncodeForPrint -> "BNB2:<data>"
-- Pipeline (import):
--   Strip prefix -> DecodeForPrint -> DecompressDeflate -> LibSerialize
--   -> BNB.ShareReadPayload (share fields only) -> preview -> create note
--   "BNB1:" strings (before ALL-136.5) are still read, by BNB.ShareReadV1.
-- Direct Send (DirectSend.lua) uses the same payload and readers.
--
-- Public API:
--   BNB.OpenShareWindow(noteID)
--   BNB.CloseShareWindow()
--   BNB.OpenSharePreview(data)
--   BNB.CloseSharePreview()
--   BNB.OpenImportWindow()
--   BNB.CloseImportWindow()

local BNB = BigNoteBox
local L   = BNB.L

local SHARE_PREFIX    = "BNB2:"   -- LibSerialize payload (ALL-136.5)
local SHARE_PREFIX_V1 = "BNB1:"   -- the old hand-made format, still read
local SHARE_W       = 420
local PREVIEW_W     = 420
local PREVIEW_H     = 380
local PAD           = 12

-- Module state
local _shareFrame   = nil
local _previewFrame = nil
local _importFrame  = nil
local _shareNoteID  = nil

--------------------------------------------------------------------------------
-- WHAT TO SEND (ALL-179)
-- One checkbox per share group of the note schema (BNB.SHARE_GROUPS in
-- Core/NoteFields.lua); title, body and rich mode always go. The ticks are
-- remembered in BigNoteBoxDB.shareGroups ({ tags = true, ... }); nil =
-- DEFAULT_GROUPS. They replaced seven cumulative presets in a dropdown.
--------------------------------------------------------------------------------
local DEFAULT_GROUPS = { tags = true, tasks = true, refbox = true, look = true, unit = true }

function BNB.GetShareGroups()
    local db = BigNoteBoxDB
    return db and db.shareGroups or DEFAULT_GROUPS
end

local function SetShareGroup(key, on)
    local db = BigNoteBoxDB
    if not db then return end
    if not db.shareGroups then
        db.shareGroups = {}
        for k, v in pairs(DEFAULT_GROUPS) do db.shareGroups[k] = v end
    end
    db.shareGroups[key] = on or nil
end

-- Share fields of the schema that a receiver accepts: never scope, alarm,
-- pin, lock or timestamps, whatever the sender put in (review question 6)
local function IsShareField(def) return def.share ~= nil end

-- The note's fields for the ticked groups, as plain data
function BNB.ShareBuildPayload(noteID, groups)
    local ndb  = BNB.NotesDB()
    local note = ndb and ndb.notes and ndb.notes[noteID]
    if not note then return nil, L["SHARE_ERR_NOTFOUND"] end
    groups = groups or BNB.GetShareGroups()
    local data = BNB.CleanNoteFields(note, function(def)
        return def.share == "text" or (def.share ~= nil and groups[def.share] == true)
    end)
    return { v = 2, note = BNB.AddLegacyContext(data) }
end

-- A received payload (share string or Direct Send) back to note fields, or
-- nil when it is not one. Only share fields of the right type and shape get
-- through (BNB.CleanNoteFields), so nothing the sender adds can reach code
-- that expects another shape.
function BNB.ShareReadPayload(payload)
    if type(payload) ~= "table" or type(payload.note) ~= "table" then return nil end
    local data = BNB.CleanNoteFields(payload.note, IsShareField)
    if not data.title and not data.body then return nil end
    return data
end

local function GetLibSerialize()
    return LibStub and LibStub("LibSerialize", true)
end

-- LibSerialize handles nested tables (tasks, gear lists) and escaping; the
-- old format turned every nested table into the string "null" (BUG-03)
function BNB.ShareSerialize(payload)
    local ls = GetLibSerialize()
    return ls and ls:Serialize(payload)
end

function BNB.ShareDeserialize(serialized)
    local ls = GetLibSerialize()
    if not ls or type(serialized) ~= "string" then return nil end
    local ok, payload = ls:Deserialize(serialized)
    if not ok then return nil end
    return BNB.ShareReadPayload(payload)
end

--------------------------------------------------------------------------------
-- THE OLD FORMAT (BNB1: share strings, BNB2 Direct Send) - read only
-- Kept so codes already pasted around the internet, and notes sent by players
-- on older versions, still open. key\030value fields joined by \031; tables
-- one level deep only. Attachments were a flat "type:id|type:id" string.
--------------------------------------------------------------------------------
local SEP_FIELD = "\031"
local SEP_KV    = "\030"
local ATT_SEP   = "|"

local function DecodeAttachments(str)
    if not str or str == "" then return nil end
    local result = {}
    for entry in (str .. ATT_SEP):gmatch("(.-)%|") do
        local t, id = entry:match("^([^:]+):(.+)$")
        if t and id then
            local num = tonumber(id)
            if num then
                result[#result + 1] = { type = t, id = num }
            end
        end
    end
    return #result > 0 and result or nil
end

local function UnescStr(s)
    return (s or "")
        :gsub("\\k",  SEP_KV)
        :gsub("\\f",  SEP_FIELD)
        :gsub("\\\\", "\\")
end

local function DeserializeValue(s)
    if not s or s == "" then return nil end
    local tag = s:sub(1, 1)
    local body = s:sub(2)
    if tag == "s" then
        return UnescStr(body)
    elseif tag == "n" then
        return tonumber(body)
    elseif tag == "b" then
        return body == "1"
    elseif tag == "t" then
        local inner = body:sub(2)  -- strip [ or {
        local result = {}
        if body:sub(1, 1) == "[" then
            -- array
            local i = 1
            for item in (inner:sub(1, -2) .. ","):gmatch("(.-),") do
                local clean = item:gsub('^"', ""):gsub('"$', "")
                result[i] = UnescStr(clean)
                i = i + 1
            end
        else
            -- object
            for k, v in inner:sub(1, -2):gmatch('"([^"]+)":([^,}]+)') do
                local uk = UnescStr(k)
                local num = tonumber(v)
                if num then
                    result[uk] = num
                elseif v == "true" then
                    result[uk] = true
                elseif v == "false" then
                    result[uk] = false
                else
                    result[uk] = UnescStr(v:gsub('^"', ""):gsub('"$', ""))
                end
            end
        end
        return result
    end
    return nil
end

-- An old-format payload to note fields (same rules as BNB.ShareReadPayload)
function BNB.ShareReadV1(serialized)
    if not serialized or serialized == "" then return nil end
    local raw = {}
    for field in (serialized .. SEP_FIELD):gmatch("(.-)" .. SEP_FIELD) do
        local k, v = field:match("^(.-)" .. SEP_KV .. "(.+)$")
        if k and v then
            raw[UnescStr(k)] = DeserializeValue(v)
        end
    end
    if raw._att then raw.attachments = DecodeAttachments(raw._att) end
    return BNB.ShareReadPayload({ note = raw })
end

--------------------------------------------------------------------------------
-- COMPRESS / ENCODE
--------------------------------------------------------------------------------
local GetDeflate = BNB.GetDeflate

function BNB.ShareEncode(noteID, groups)
    local payload, err = BNB.ShareBuildPayload(noteID, groups)
    if not payload then return nil, err end
    local ld = GetDeflate()
    local serialized = BNB.ShareSerialize(payload)
    if not ld or not serialized then return nil, L["SHARE_ERR_GENERATE"] end
    return SHARE_PREFIX .. ld:EncodeForPrint(ld:CompressDeflate(serialized))
end

function BNB.ShareDecode(str)
    if not str or str == "" then return nil, L["SHARE_ERR_EMPTY"] end
    str = str:match("^%s*(.-)%s*$")  -- trim whitespace

    local v1 = str:sub(1, #SHARE_PREFIX_V1) == SHARE_PREFIX_V1
    if not v1 and str:sub(1, #SHARE_PREFIX) ~= SHARE_PREFIX then
        return nil, L["SHARE_ERR_PREFIX"]
    end
    local encoded = str:sub((v1 and #SHARE_PREFIX_V1 or #SHARE_PREFIX) + 1)

    local ld = GetDeflate()
    if not ld then return nil, L["SHARE_ERR_DECODE"] end
    local compressed = ld:DecodeForPrint(encoded)
    if not compressed then return nil, L["SHARE_ERR_DECODE"] end
    local serialized = ld:DecompressDeflate(compressed)
    if not serialized then return nil, L["SHARE_ERR_DECOMPRESS"] end

    local data
    if v1 then data = BNB.ShareReadV1(serialized) else data = BNB.ShareDeserialize(serialized) end
    if not data then return nil, L["SHARE_ERR_DESERIALIZE"] end
    return data
end

--------------------------------------------------------------------------------
-- PREVIEW WINDOW
-- Opens when the user clicks "Preview" after pasting a share string.
-- Shows decoded title + scrollable body. "Add Note" or "Discard" buttons.
--------------------------------------------------------------------------------
local function BuildSharePreview()
    if _previewFrame then return _previewFrame end

    -- Shared chrome (CMP-02); the content offsets are the old ones
    local f = BNB.CreateToolWindow({
        name = "BNBSharePreviewFrame", w = PREVIEW_W, h = PREVIEW_H, title = L["SHARE_PREVIEW_TITLE"],
        strata = "DIALOG", toplevel = true,
        onClose = function() BNB.CloseSharePreview() end,
    })
    local titleH = f._isSkin and BNB.TOOL_SKIN_TITLE_H or 32

    local FOOT_H = 44

    -- Note title label
    local noteTitleLbl = f:CreateFontString(nil, "OVERLAY", "BNBFontNormalLarge")
    noteTitleLbl:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, -(titleH + 10))
    noteTitleLbl:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -(titleH + 10))
    noteTitleLbl:SetJustifyH("LEFT")
    noteTitleLbl:SetHeight(22)
    BNB.SetHeaderColor(noteTitleLbl)
    f._noteTitleLbl = noteTitleLbl

    -- Divider below title
    local divHost = CreateFrame("Frame", nil, f)
    divHost:SetHeight(1)
    divHost:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, -(titleH + 36))
    divHost:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -(titleH + 36))
    local div = BNB.CreateDivider(divHost, "HORIZONTAL", 0.28, 0.28, 0.30, 1)
    div:SetPoint("TOPLEFT",  divHost, "TOPLEFT",  0, 0)
    div:SetPoint("TOPRIGHT", divHost, "TOPRIGHT", 0, 0)

    -- Scrollable body
    local sf = BNB.CreateScrollFrame(nil, f)
    sf:SetPoint("TOPLEFT",     f, "TOPLEFT",      PAD, -(titleH + 42))
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28,   FOOT_H)
    if sf.ScrollBar then
        sf.ScrollBar:SetAlpha(0)
        sf:HookScript("OnScrollRangeChanged", function(_, _, yRange)
            sf.ScrollBar:SetAlpha((yRange or 0) > 1 and 1.0 or 0)
        end)
    end
    local ct = CreateFrame("Frame", nil, sf)
    ct:SetHeight(1)
    sf:SetScrollChild(ct)
    sf:HookScript("OnShow", function(self)
        C_Timer.After(0, function()
            local w = self:GetWidth()
            if w > 0 then ct:SetWidth(w - 4) end
        end)
    end)
    sf:SetScript("OnSizeChanged", function(self)
        local w = self:GetWidth()
        if w > 0 then ct:SetWidth(w - 4) end
    end)
    f._previewSF = sf
    f._previewCt = ct

    local bodyLbl = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    bodyLbl:SetPoint("TOPLEFT",  ct, "TOPLEFT",  0, 0)
    bodyLbl:SetPoint("TOPRIGHT", ct, "TOPRIGHT", 0, 0)
    bodyLbl:SetJustifyH("LEFT"); bodyLbl:SetJustifyV("TOP")
    bodyLbl:SetWordWrap(true)
    bodyLbl:SetTextColor(0.85, 0.85, 0.85)
    f._bodyLbl = bodyLbl

    -- Refbox attachments label (shown only when data has attachments)
    local attLbl = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    attLbl:SetPoint("TOPLEFT",  ct, "TOPLEFT",  0, 0)
    attLbl:SetPoint("TOPRIGHT", ct, "TOPRIGHT", 0, 0)
    attLbl:SetJustifyH("LEFT"); attLbl:SetWordWrap(true)
    attLbl:SetTextColor(0.55, 0.75, 0.55)
    attLbl:Hide()
    f._attLbl = attLbl

    -- Footer divider
    local footHost = CreateFrame("Frame", nil, f)
    footHost:SetHeight(1)
    footHost:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  PAD,  FOOT_H - 1)
    footHost:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, FOOT_H - 1)
    local footDiv = BNB.CreateDivider(footHost, "HORIZONTAL", 0.25, 0.25, 0.28, 1)
    footDiv:SetPoint("TOPLEFT",  footHost, "TOPLEFT",  0, 0)
    footDiv:SetPoint("TOPRIGHT", footHost, "TOPRIGHT", 0, 0)

    -- Add Note button
    local addBtn = BNB.CreateButton(nil, f, L["SHARE_ADD_BTN"], 90, 26)
    addBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, 10)
    addBtn:SetScript("OnClick", function()
        local data = f._pendingData
        if not data then return end
        -- Share fields only, checked again here: TakeANote notes come in
        -- through Direct Send without going through BNB.ShareReadPayload.
        -- No scope (the note lands where CreateNote puts it, under the
        -- active sidebar character), no alarm; tasks come along (BUG-03).
        data = BNB.CleanNoteFields(data, function(def) return def.share ~= nil end)
        local id = BNB.CreateNote(data.title or "", data.body or "")
        if id then
            local updates = {}
            for k, v in pairs(data) do
                if k ~= "title" and k ~= "body" and k ~= "attachments" then updates[k] = v end
            end
            if next(updates) then BNB.UpdateNote(id, updates) end
            -- Import attachments via the proper API so refbox badge updates
            if data.attachments and BNB.RBAddAttachment then
                for _, a in ipairs(data.attachments) do
                    BNB.RBAddAttachment(id, a)
                end
            end
            if BNB.SelectNote     then BNB.SelectNote(id)    end
            BNB:Print("|cff66bb6a" .. L["SHARE_IMPORTED"] .. "|r")
        end
        BNB.CloseSharePreview()
        BNB.CloseShareWindow()
        BNB.CloseImportWindow()
    end)
    f._addBtn = addBtn

    -- Discard button
    local discardBtn = BNB.CreateButton(nil, f, L["SHARE_DISCARD_BTN"], 80, 26)
    discardBtn:SetPoint("LEFT", addBtn, "RIGHT", 8, 0)
    discardBtn:SetScript("OnClick", function() BNB.CloseSharePreview() end)

    -- Non-ESC keys propagate so they can reach focused editboxes below
    -- (e.g. the BNB clipboard helper editbox for Ctrl+C). HIGH strata +
    -- SetToplevel + EnableKeyboard otherwise swallows all keys here.
    BNB.AttachEscClose(f, function() BNB.CloseSharePreview() end)
    f:Hide()
    _previewFrame = f
    return f
end

function BNB.OpenSharePreview(data)
    local f = BuildSharePreview()
    f._pendingData = data

    -- Title
    local title = (data.title and data.title ~= "") and data.title or "|cff666666(untitled)|r"
    if f._noteTitleLbl then f._noteTitleLbl:SetText(title) end

    -- Body
    local body = data.body or ""
    if f._bodyLbl then
        f._bodyLbl:SetText(body ~= "" and body or "|cff666666(no content)|r")
        C_Timer.After(0.05, function()
            if f._bodyLbl and f._previewCt then
                local h = math.max(f._bodyLbl:GetStringHeight() + 8, 40)
                f._previewCt:SetHeight(h)
            end
        end)
    end
    if f._previewSF then f._previewSF:SetVerticalScroll(0) end

    -- Refbox attachments
    if f._attLbl then
        local atts = data.attachments
        if atts and #atts > 0 then
            local parts = {}
            for _, a in ipairs(atts) do
                local label
                if a.type == "item" then
                    local name = C_Item.GetItemInfo(a.id)
                    label = name and ("[" .. name .. "]") or ("item:" .. a.id)
                elseif a.type == "spell" then
                    local si = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(a.id)
                    label = (si and si.name) and si.name or ("spell:" .. a.id)
                else
                    label = a.type .. ":" .. a.id
                end
                parts[#parts + 1] = label
            end
            f._attLbl:SetText(string.format(L["SHARE_REFBOX_FMT"], table.concat(parts, ", ")))
            f._attLbl:Show()
        else
            f._attLbl:SetText("")
            f._attLbl:Hide()
        end
        -- Tasks travel too since ALL-136.5; say how many
        local tasks = type(data.tasks) == "table" and #data.tasks or 0
        if tasks > 0 then
            local cur = f._attLbl:IsShown() and (f._attLbl:GetText() .. "\n") or ""
            f._attLbl:SetText(cur .. string.format(L["SHARE_TASKS_FMT"], tasks))
            f._attLbl:Show()
        end
        -- Re-measure content height after attachments shown/hidden
        C_Timer.After(0.05, function()
            if f._bodyLbl and f._attLbl and f._previewCt then
                local bh = f._bodyLbl:GetStringHeight()
                local ah = f._attLbl:IsShown() and (f._attLbl:GetStringHeight() + 6) or 0
                f._previewCt:SetHeight(math.max(bh + ah + 8, 40))
                -- Reposition attLbl below bodyLbl
                f._attLbl:ClearAllPoints()
                f._attLbl:SetPoint("TOPLEFT",  f._previewCt, "TOPLEFT",  0, -(bh + 4))
                f._attLbl:SetPoint("TOPRIGHT", f._previewCt, "TOPRIGHT", 0, -(bh + 4))
            end
        end)
    end

    f:ClearAllPoints()
    if _shareFrame and _shareFrame:IsShown() then
        f:SetPoint("TOPLEFT", _shareFrame, "TOPRIGHT", 8, 0)
    elseif _importFrame and _importFrame:IsShown() then
        f:SetPoint("TOPLEFT", _importFrame, "TOPRIGHT", 8, 0)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 30, 30)
    end
    f:Show(); f:Raise()
end

function BNB.CloseSharePreview()
    if _previewFrame then _previewFrame:Hide() end
end

--------------------------------------------------------------------------------
-- SHARE WINDOW
-- Top half: pick option, generate share string, copy hint.
-- Bottom half: paste import string, preview button.
--------------------------------------------------------------------------------
local function BuildShareWindow()
    if _shareFrame then return _shareFrame end

    -- Shared chrome (CMP-02); the content offsets are the old ones
    local f = BNB.CreateToolWindow({
        name = "BNBShareFrame", w = SHARE_W, h = 340, title = L["SHARE_TITLE"],
        strata = "HIGH", toplevel = true,
        onClose = function() BNB.CloseShareWindow() end,
    })
    local titleH = f._isSkin and BNB.TOOL_SKIN_TITLE_H or 32

    local y = -(titleH + 10)
    local CW = SHARE_W - PAD * 2

    -- ── SHARE OUT ─────────────────────────────────────────────────────────────
    local shareHdr = f:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    shareHdr:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    BNB.SetHeaderColor(shareHdr)
    shareHdr:SetText(L["SHARE_HDR"])
    y = y - 20

    -- What to include: one checkbox per share group (ALL-179), three columns.
    -- Title, body and rich mode always go, so they have no box.
    local ddLbl = f:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    ddLbl:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    ddLbl:SetTextColor(0.78, 0.78, 0.78)
    ddLbl:SetText(L["SHARE_INCLUDE"])
    y = y - 18

    local function RegenerateShareString()
        if not _shareNoteID then return end
        local str, err = BNB.ShareEncode(_shareNoteID)
        if str and f._shareEB then
            f._shareEB:SetText(str)
        elseif f._shareEB then
            f._shareEB:SetText(err or L["SHARE_ERR_GENERATE"])
        end
        if f._refreshDsCount then f._refreshDsCount() end
    end

    local COLS, ROW_H = 3, 24
    local colW = CW / COLS
    f._groupCbs = {}
    for i, g in ipairs(BNB.SHARE_GROUPS) do
        local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
        local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("TOPLEFT", f, "TOPLEFT", PAD - 2 + col * colW, y - row * ROW_H + 2)
        -- The label is part of the button, so a click on it ticks the box
        cb:SetHitRectInsets(0, -(colW - 30), 0, 0)
        local lbl = f:CreateFontString(nil, "OVERLAY", "BNBFontHighlightSmall")
        lbl:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        lbl:SetWidth(colW - 30); lbl:SetJustifyH("LEFT"); lbl:SetWordWrap(false)
        lbl:SetText(L[g.label])
        local key = g.key
        cb:SetScript("OnClick", function(self)
            SetShareGroup(key, self:GetChecked() and true or false)
            RegenerateShareString()
        end)
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L[g.label], 1, 0.82, 0)
            GameTooltip:AddLine(L[g.tip], 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f._groupCbs[key] = cb
    end
    y = y - math.ceil(#BNB.SHARE_GROUPS / COLS) * ROW_H - 8

    -- Share string editbox
    local shareBg = BNB.CreateBackdropFrame("Frame", nil, f)
    BNB.SetBackdropDark(shareBg)
    shareBg:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, y)
    shareBg:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
    shareBg:SetHeight(52)

    local shareEB = CreateFrame("EditBox", nil, shareBg)
    shareEB:SetPoint("TOPLEFT",     shareBg, "TOPLEFT",     4,  -4)
    shareEB:SetPoint("BOTTOMRIGHT", shareBg, "BOTTOMRIGHT", -4,  4)
    shareEB:SetFontObject("BNBFontNormalSmall")
    shareEB:SetMultiLine(false)
    shareEB:SetAutoFocus(false)
    shareEB:SetMaxLetters(0)
    shareEB:SetTextInsets(2, 2, 2, 2)
    shareEB:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    shareEB:SetScript("OnEscapePressed",   function(self) self:ClearFocus() end)
    f._shareEB = shareEB
    y = y - 58

    -- Copy hint button
    local copyBtn = BNB.CreateButton(nil, f, L["SHARE_COPY_BTN"], 140, 24)
    copyBtn:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    copyBtn:SetScript("OnClick", function()
        local str = f._shareEB and f._shareEB:GetText() or ""
        -- deferFocus=true: synchronous focus is unreliable from this OnClick
        -- path, so defer one tick before setting focus on the helper.
        if str ~= "" then BNB.ShowClipboardHint(str, copyBtn, true) end
    end)

    -- BCB send button (or "Get BCB" if absent)
    local bcbShareBtn = BNB.CreateButton(nil, f, L["SHARE_BCB_BTN"], 110, 24)
    bcbShareBtn:SetPoint("LEFT", copyBtn, "RIGHT", 6, 0)
    local function RefreshBCBShareBtn()
        local hasBCB = BigChatBox and BigChatBox.SendDirect and true or false
        bcbShareBtn:SetText(hasBCB and L["SHARE_BCB_BTN"] or L["SHARE_GET_BCB_BTN"])
    end
    RefreshBCBShareBtn()
    bcbShareBtn:SetScript("OnClick", function()
        local hasBCB = BigChatBox and BigChatBox.SendDirect and true or false
        if not hasBCB then
            if BNB.ShowBCBPromo then BNB.ShowBCBPromo() end
            return
        end
        local str = f._shareEB and f._shareEB:GetText() or ""
        if str == "" then return end
        -- No multi-line box in this BCB (Classic, ALL-367): Copy is the way
        if not BNB.OpenInBCB(str) then BNB:Print(L["BCB_NO_MULTILINE"]) end
    end)
    -- Tint the BCB button green in normal mode (a skin button already carries
    -- the preset's look). Deferred one tick so template textures are initialized.
    C_Timer.After(0, function()
        local skinMode = BigNoteBoxDB and BigNoteBoxDB.skinMode
        if not skinMode then
            pcall(function()
                for _, region in ipairs({ bcbShareBtn:GetRegions() }) do
                    if region.IsObjectType and region:IsObjectType("Texture") then
                        region:SetVertexColor(0.30, 0.85, 0.35)
                    elseif region.IsObjectType and region:IsObjectType("FontString") then
                        BNB.SetTextWhite(region)
                    end
                end
            end)
        end
    end)
    f._bcbShareBtn = bcbShareBtn
    f._refreshBCBShareBtn = RefreshBCBShareBtn

    -- Character counter (right-aligned, same row as copy/BCB buttons)
    local charCounter = f:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    charCounter:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
    charCounter:SetPoint("TOP",   copyBtn, "TOP", 0, 0)
    charCounter:SetTextColor(0.55, 0.55, 0.55)
    charCounter:SetText(string.format(L["SHARE_CHARS_FMT"], 0))
    f._charCounter = charCounter

    shareEB:SetScript("OnTextChanged", function(self)
        local n = #(self:GetText() or "")
        local col = n > 2000 and "|cffff6666" or n > 800 and "|cffffff66" or "|cff888888"
        charCounter:SetText(col .. string.format(L["SHARE_CHARS_FMT"], n) .. "|r")
    end)

    y = y - 34

    -- ── SEND DIRECTLY ─────────────────────────────────────────────────────────
    local dsDiv1Host = CreateFrame("Frame", nil, f)
    dsDiv1Host:SetHeight(1)
    dsDiv1Host:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, y)
    dsDiv1Host:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
    local dsDiv1 = BNB.CreateDivider(dsDiv1Host, "HORIZONTAL", 0.28, 0.28, 0.30, 1)
    dsDiv1:SetPoint("TOPLEFT",  dsDiv1Host, "TOPLEFT",  0, 0)
    dsDiv1:SetPoint("TOPRIGHT", dsDiv1Host, "TOPRIGHT", 0, 0)
    y = y - 14

    local dsHdr = f:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    dsHdr:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    BNB.SetHeaderColor(dsHdr)
    dsHdr:SetText(L["DS_SECTION_HEADER"])
    y = y - 22

    -- Target editbox: plain EditBox filling the backdrop. InputBoxTemplate drew
    -- a second border inside dsEbBg and its inset left the outer ring
    -- unclickable (same fix as the Note Config icon field)
    local dsEbBg = BNB.CreateBackdropFrame("Frame", nil, f)
    BNB.SetBackdropDark(dsEbBg)
    dsEbBg:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, y)
    dsEbBg:SetWidth(CW - 70)
    dsEbBg:SetHeight(24)

    local dsEb = CreateFrame("EditBox", nil, dsEbBg)
    dsEb:SetAllPoints(dsEbBg)
    dsEb:SetTextInsets(6, 6, 0, 0)
    dsEb:SetFontObject("BNBFontNormalSmall")
    dsEb:SetAutoFocus(false)
    dsEb:SetMaxLetters(80)
    BNB.AddPlaceholder(dsEb, L["DS_TARGET_PLACEHOLDER"], 0.45, 0.45, 0.45)
    dsEb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    -- Enter clears focus, as InputBoxTemplate's handler did
    dsEb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    f._dsEb = dsEb

    -- Send button
    local dsSendBtn = BNB.CreateButton(nil, f, L["DS_SEND_BUTTON"], 60, 24)
    dsSendBtn:SetPoint("LEFT", dsEbBg, "RIGHT", 6, 0)
    f._dsSendBtn = dsSendBtn

    -- Status label (success / error feedback, cleared on next OpenShareWindow)
    local dsStatus = f:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    dsStatus:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, y - 28)
    dsStatus:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y - 28)
    dsStatus:SetJustifyH("LEFT")
    dsStatus:SetWordWrap(true)
    dsStatus:SetHeight(18)
    dsStatus:SetText("")
    f._dsStatus = dsStatus

    -- How many messages the note takes, shown before a send (SUG-10). Above
    -- the cap the line turns red and Send is greyed out.
    local function RefreshDsCount()
        local n, cap
        if _shareNoteID and BNB.DS and BNB.DS.MessageCount then
            n, cap = BNB.DS.MessageCount(_shareNoteID, BNB.GetShareGroups())
        end
        local tooBig = n ~= nil and n > cap
        dsSendBtn:SetEnabled(not tooBig)
        if not n then dsStatus:SetText(""); return end
        if tooBig then
            dsStatus:SetTextColor(1, 0.35, 0.35)
            dsStatus:SetText(string.format(L["DS_ERR_TOO_LARGE"], n))
        else
            dsStatus:SetTextColor(0.55, 0.55, 0.55)
            dsStatus:SetText(n == 1 and L["DS_STATUS_COUNT_ONE"]
                or string.format(L["DS_STATUS_COUNT"], n))
        end
    end
    f._refreshDsCount = RefreshDsCount

    -- Autocomplete frame (anchored below the editbox)
    local dsAcFrame = BNB.CreateBackdropFrame("Frame", nil, f)
    BNB.SetBackdrop(dsAcFrame, 0.08, 0.08, 0.10, 0.97, 0.35, 0.35, 0.38, 1)
    dsAcFrame:SetPoint("TOPLEFT",  dsEbBg, "BOTTOMLEFT",  0, -2)
    dsAcFrame:SetWidth(dsEbBg:GetWidth() + 66)   -- matches eb+button width
    dsAcFrame:SetFrameLevel(f:GetFrameLevel() + 30)
    dsAcFrame:Hide()
    f._dsAcFrame = dsAcFrame

    local _dsAcRows  = {}
    local _dsAcTimer = nil

    local function DsHideAC()
        dsAcFrame:Hide()
        if _dsAcTimer then _dsAcTimer:Cancel(); _dsAcTimer = nil end
    end

    local function DsShowAC(matches)
        if #matches == 0 then DsHideAC(); return end
        local ROW_H = 22
        local maxR  = math.min(#matches, 8)
        dsAcFrame:SetHeight(maxR * ROW_H + 4)
        for i = 1, maxR do
            if not _dsAcRows[i] then
                local row = CreateFrame("Button", nil, dsAcFrame)
                row:SetHeight(ROW_H)
                local hi = row:CreateTexture(nil, "HIGHLIGHT")
                hi:SetAllPoints(); hi:SetColorTexture(1, 1, 1, 0.08)
                local nl = row:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
                nl:SetPoint("LEFT",  row, "LEFT",  4, 0)
                nl:SetPoint("RIGHT", row, "RIGHT", -80, 0)
                nl:SetJustifyH("LEFT"); nl:SetMaxLines(1); BNB.SetTextWhite(nl)
                row._nameLbl = nl
                local cl = row:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
                cl:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                cl:SetWidth(76); cl:SetJustifyH("RIGHT"); cl:SetMaxLines(1)
                cl:SetTextColor(0.50, 0.50, 0.50)
                row._contLbl = cl
                _dsAcRows[i] = row
            end
            local row = _dsAcRows[i]
            local m   = matches[i]
            row._nameLbl:SetText(m.name)
            row._contLbl:SetText(m.continent or "")
            row:SetPoint("TOPLEFT",  dsAcFrame, "TOPLEFT",   4, -2 - (i-1)*ROW_H)
            row:SetPoint("TOPRIGHT", dsAcFrame, "TOPRIGHT", -4, -2 - (i-1)*ROW_H)
            local capName = m.name
            row:SetScript("OnClick", function()
                dsEb:SetText(capName)
                DsHideAC()
                dsEb:SetFocus()
            end)
            row:Show()
        end
        for i = maxR + 1, #_dsAcRows do _dsAcRows[i]:Hide() end
        dsAcFrame:Show()
    end

    dsEb:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local text = self:GetText() or ""
        if self._showingPlaceholder or #text < 2 then DsHideAC(); return end
        if _dsAcTimer then _dsAcTimer:Cancel() end
        _dsAcTimer = C_Timer.NewTimer(0.15, function()
            if BNB.ZonePicker and BNB.ZonePicker.GetMatches then
                local m = BNB.ZonePicker.GetMatches(text, "player", 8)
                DsShowAC(m)
            end
        end)
    end)

    dsEb:HookScript("OnEditFocusLost", function()
        C_Timer.After(0.2, function()
            if not dsAcFrame:IsMouseOver() then DsHideAC() end
        end)
    end)

    dsSendBtn:SetScript("OnClick", function()
        DsHideAC()
        if f._dsStatus then f._dsStatus:SetText("") end
        local target = dsEb and not dsEb._showingPlaceholder and dsEb:GetText() or ""
        target = target:match("^%s*(.-)%s*$")
        if target == "" then
            if f._dsStatus then
                f._dsStatus:SetTextColor(1, 0.35, 0.35)
                f._dsStatus:SetText(L["DS_ERR_NO_TARGET"])
            end
            return
        end
        if not _shareNoteID then
            if f._dsStatus then
                f._dsStatus:SetTextColor(1, 0.35, 0.35)
                f._dsStatus:SetText(L["DS_ERR_NO_NOTE"])
            end
            return
        end
        if BNB.DS and BNB.DS.SendNote then
            -- The status line belongs to this note: a later note shown in the
            -- window must not get this send's progress
            local sendID = _shareNoteID
            local function Status(r, g, b, text)
                if f._dsStatus and f:IsShown() and _shareNoteID == sendID then
                    f._dsStatus:SetTextColor(r, g, b)
                    f._dsStatus:SetText(text)
                end
            end
            BNB.DS.SendNote(sendID, BNB.GetShareGroups(), target, function(chunks)
                Status(0.40, 0.85, 0.45, string.format(L["DS_STATUS_SENT"], target, chunks))
            end, function(err)
                Status(1, 0.35, 0.35, err or L["DS_ERR_GENERIC"])
            end, function(sent, total)
                Status(0.40, 0.85, 0.45, string.format(L["DS_STATUS_PROGRESS"], target, sent, total))
            end, function()
                Status(0.40, 0.85, 0.45, string.format(L["DS_STATUS_DONE"], target))
            end)
        else
            if f._dsStatus then
                f._dsStatus:SetTextColor(1, 0.35, 0.35)
                f._dsStatus:SetText(L["DS_ERR_NOT_LOADED"])
            end
        end
    end)

    -- Hook: clear AC when share window hides
    f:HookScript("OnHide", function() DsHideAC() end)

    y = y - 52   -- eb row (24) + status row (18) + spacing (10)

    -- Divider between share and import sections
    local midHost = CreateFrame("Frame", nil, f)
    midHost:SetHeight(1)
    midHost:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, y)
    midHost:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
    local midDiv = BNB.CreateDivider(midHost, "HORIZONTAL", 0.28, 0.28, 0.30, 1)
    midDiv:SetPoint("TOPLEFT",  midHost, "TOPLEFT",  0, 0)
    midDiv:SetPoint("TOPRIGHT", midHost, "TOPRIGHT", 0, 0)
    y = y - 14

    -- ── IMPORT ────────────────────────────────────────────────────────────────
    local importHdr = f:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    importHdr:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    BNB.SetHeaderColor(importHdr)
    importHdr:SetText(L["SHARE_IMPORT_HDR"])
    y = y - 20

    local importLbl = f:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    importLbl:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    importLbl:SetTextColor(0.78, 0.78, 0.78)
    importLbl:SetText(L["SHARE_PASTE_PROMPT"])
    y = y - 18

    -- Import editbox
    local importBg = BNB.CreateBackdropFrame("Frame", nil, f)
    BNB.SetBackdropDark(importBg)
    importBg:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, y)
    importBg:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
    importBg:SetHeight(52)

    local importEB = CreateFrame("EditBox", nil, importBg)
    importEB:SetPoint("TOPLEFT",     importBg, "TOPLEFT",     4,  -4)
    importEB:SetPoint("BOTTOMRIGHT", importBg, "BOTTOMRIGHT", -4,  4)
    importEB:SetFontObject("BNBFontNormalSmall")
    importEB:SetMultiLine(false)
    importEB:SetAutoFocus(false)
    importEB:SetMaxLetters(0)
    importEB:SetTextInsets(2, 2, 2, 2)
    BNB.AddPlaceholder(importEB, L["SHARE_IMPORT_PLACEHOLDER"], 0.4, 0.4, 0.4)
    importEB:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f._importEB = importEB
    y = y - 58

    -- Error label
    local errLbl = f:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    errLbl:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, y)
    errLbl:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
    errLbl:SetJustifyH("LEFT"); errLbl:SetWordWrap(true); errLbl:SetHeight(18)
    errLbl:SetTextColor(1, 0.35, 0.35)
    errLbl:SetText("")
    f._errLbl = errLbl
    y = y - 22

    -- Preview button
    local previewBtn = BNB.CreateButton(nil, f, L["SHARE_PREVIEW_BTN"], 90, 26)
    previewBtn:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    previewBtn:SetScript("OnClick", function()
        if f._errLbl then f._errLbl:SetText("") end
        local str = f._importEB and not f._importEB._showingPlaceholder
            and f._importEB:GetText() or ""
        if str == "" then
            if f._errLbl then f._errLbl:SetText(L["SHARE_PASTE_FIRST"]) end
            return
        end
        local data, err = BNB.ShareDecode(str)
        if not data then
            if f._errLbl then f._errLbl:SetText(err or L["SHARE_ERR_INVALID"]) end
            return
        end
        BNB.OpenSharePreview(data)
    end)
    y = y - 36

    -- Resize window to fit content
    f:SetHeight(math.abs(y) + PAD)

    -- Non-ESC keys propagate so they can reach focused editboxes below
    -- (e.g. the BNB clipboard helper editbox for Ctrl+C). HIGH strata +
    -- SetToplevel + EnableKeyboard otherwise swallows all keys here.
    BNB.AttachEscClose(f, function()
        -- Preview closes first if open, then the share window
        local spv = _previewFrame
        if spv and spv:IsShown() then BNB.CloseSharePreview(); return end
        BNB.CloseShareWindow()
    end)
    f:Hide()
    _shareFrame = f
    return f
end

function BNB.OpenShareWindow(noteID)
    if InCombatLockdown() then BNB:Print(L["COMBAT_BLOCKED"]); return end

    _shareNoteID = noteID

    local f = BuildShareWindow()

    -- The ticks are remembered between notes and sessions (ALL-179)
    local groups = BNB.GetShareGroups()
    for key, cb in pairs(f._groupCbs or {}) do cb:SetChecked(groups[key] == true) end
    -- Reset import field
    if f._importEB then
        f._importEB:SetText("")
        BNB.AddPlaceholder(f._importEB, L["SHARE_IMPORT_PLACEHOLDER"], 0.4, 0.4, 0.4)
    end
    if f._errLbl then f._errLbl:SetText("") end

    -- Generate initial share string
    if noteID then
        local str = BNB.ShareEncode(noteID)
        if str and f._shareEB then f._shareEB:SetText(str) end
    else
        if f._shareEB then f._shareEB:SetText("") end
    end
    if f._refreshDsCount then f._refreshDsCount() end

    -- Close preview if it's open from a previous session
    BNB.CloseSharePreview()

    f:ClearAllPoints()
    if BNB.mainFrame and BNB.mainFrame:IsShown() then
        f:SetPoint("TOPRIGHT", BNB.mainFrame, "TOPLEFT", -8, 0)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    f:Show(); f:Raise()
end

function BNB.CloseShareWindow()
    BNB.CloseSharePreview()
    if _shareFrame then _shareFrame:Hide() end
end

--------------------------------------------------------------------------------
-- IMPORT-ONLY WINDOW
-- Opened from the topbar tp-import button. Shows only the import section so
-- users can add a shared note without having to select one of their own first.
-- Reuses OpenSharePreview / CloseSharePreview for the preview flow.
--------------------------------------------------------------------------------
local IMPORT_W = 420
local function BuildImportWindow()
    if _importFrame then return _importFrame end

    -- Shared chrome (CMP-02); the content offsets are the old ones
    local f = BNB.CreateToolWindow({
        name = "BNBImportFrame", w = IMPORT_W, h = 220, title = L["SHARE_IMPORT_TITLE"],
        strata = "HIGH", toplevel = true,
        onClose = function() BNB.CloseImportWindow() end,
    })
    local titleH = f._isSkin and BNB.TOOL_SKIN_TITLE_H or 32
    -- ESC chain: preview closes before import window (handled in MainWindow ESC block)

    local y   = -(titleH + 10)

    local instrLbl = f:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    instrLbl:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, y)
    instrLbl:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
    instrLbl:SetJustifyH("LEFT")
    instrLbl:SetTextColor(0.78, 0.78, 0.78)
    instrLbl:SetText(L["SHARE_PASTE_PROMPT"])
    y = y - 20

    -- Import editbox
    local importBg = BNB.CreateBackdropFrame("Frame", nil, f)
    BNB.SetBackdropDark(importBg)
    importBg:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, y)
    importBg:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
    importBg:SetHeight(52)

    local importEB = CreateFrame("EditBox", nil, importBg)
    importEB:SetPoint("TOPLEFT",     importBg, "TOPLEFT",     4, -4)
    importEB:SetPoint("BOTTOMRIGHT", importBg, "BOTTOMRIGHT", -4, 4)
    importEB:SetFontObject("BNBFontNormalSmall")
    importEB:SetMultiLine(false)
    importEB:SetAutoFocus(false)
    importEB:SetMaxLetters(0)
    importEB:SetTextInsets(2, 2, 2, 2)
    BNB.AddPlaceholder(importEB, L["SHARE_IMPORT_PLACEHOLDER"], 0.4, 0.4, 0.4)
    importEB:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f._importEB = importEB
    y = y - 58

    -- Error label
    local errLbl = f:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    errLbl:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, y)
    errLbl:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
    errLbl:SetJustifyH("LEFT"); errLbl:SetWordWrap(true); errLbl:SetHeight(18)
    errLbl:SetTextColor(1, 0.35, 0.35)
    errLbl:SetText("")
    f._errLbl = errLbl
    y = y - 22

    -- Preview button
    local previewBtn = BNB.CreateButton(nil, f, L["SHARE_PREVIEW_BTN"], 90, 26)
    previewBtn:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    previewBtn:SetScript("OnClick", function()
        if f._errLbl then f._errLbl:SetText("") end
        local str = f._importEB and not f._importEB._showingPlaceholder
            and f._importEB:GetText() or ""
        if str == "" then
            if f._errLbl then f._errLbl:SetText(L["SHARE_PASTE_FIRST"]) end
            return
        end
        local data, err = BNB.ShareDecode(str)
        if not data then
            if f._errLbl then f._errLbl:SetText(err or L["SHARE_ERR_INVALID"]) end
            return
        end
        BNB.OpenSharePreview(data)
    end)

    -- Character counter right of preview button
    local impCharCounter = f:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    impCharCounter:SetPoint("LEFT",  previewBtn, "RIGHT", 8, 0)
    impCharCounter:SetPoint("RIGHT", f,           "RIGHT", -PAD, 0)
    impCharCounter:SetJustifyH("LEFT")
    impCharCounter:SetTextColor(0.55, 0.55, 0.55)
    impCharCounter:SetText(string.format(L["SHARE_CHARS_FMT"], 0))
    f._importEB:SetScript("OnTextChanged", function(self)
        if self._showingPlaceholder then impCharCounter:SetText(string.format(L["SHARE_CHARS_FMT"], 0)); return end
        local n = #(self:GetText() or "")
        local col = n > 0 and "|cff888888" or "|cff555555"
        impCharCounter:SetText(col .. string.format(L["SHARE_CHARS_FMT"], n) .. "|r")
    end)

    y = y - 36

    f:SetHeight(math.abs(y) + PAD)
    -- Non-ESC keys propagate so they can reach focused editboxes below
    -- (e.g. the BNB clipboard helper editbox for Ctrl+C). HIGH strata +
    -- SetToplevel + EnableKeyboard otherwise swallows all keys here.
    BNB.AttachEscClose(f, function()
        local spv = _previewFrame
        if spv and spv:IsShown() then BNB.CloseSharePreview(); return end
        BNB.CloseImportWindow()
    end)
    f:Hide()
    _importFrame = f
    return f
end

function BNB.OpenImportWindow()
    if InCombatLockdown() then BNB:Print(L["COMBAT_BLOCKED"]); return end
    local f = BuildImportWindow()
    -- Reset fields
    if f._importEB then
        f._importEB:SetText("")
        BNB.AddPlaceholder(f._importEB, L["SHARE_IMPORT_PLACEHOLDER"], 0.4, 0.4, 0.4)
    end
    if f._errLbl then f._errLbl:SetText("") end
    BNB.CloseSharePreview()
    f:ClearAllPoints()
    if BNB.mainFrame and BNB.mainFrame:IsShown() then
        f:SetPoint("TOPRIGHT", BNB.mainFrame, "TOPLEFT", -8, 0)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    f:Show(); f:Raise()
end

function BNB.CloseImportWindow()
    BNB.CloseSharePreview()
    if _importFrame then _importFrame:Hide() end
end

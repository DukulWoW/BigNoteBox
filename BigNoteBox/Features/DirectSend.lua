-- BigNoteBox Features/DirectSend.lua
-- Direct addon-message note sharing between players.
--
-- Protocols supported:
--   BNB2  (send + receive)  — BNB-to-BNB direct send.
--   TAN1  (receive only)    — TakeANote compatibility; incoming TAN notes/
--                             categories are translated and queued as BNB notes.
--
-- Transport pipeline (send):
--   Build data table -> BNB.DS_Serialize -> CompressDeflate
--   -> EncodeForWoWAddonChannel -> chunk (180 chars, CHUNK_TICK intervals)
--   -> C_ChatInfo.SendAddonMessage("BNB2", chunk, "WHISPER", target)
--
-- Transport pipeline (receive BNB2):
--   Reassemble chunks -> DecodeForWoWAddonChannel -> DecompressDeflate
--   -> BNB.DS_Deserialize -> queue -> incoming prompt -> BNB.OpenSharePreview
--
-- Transport pipeline (receive TAN1):
--   Reassemble chunks -> DecodeForWoWAddonChannel -> DecompressDeflate
--   -> LibSerialize:Deserialize -> map fields -> queue -> prompt
--
-- Public API:
--   BNB.DS.SendNote(noteID, optionKey, targetName, onSent, onFail)
--   BNB.DS.IsAutoReject()

local BNB = BigNoteBox
local L   = BNB.L

BNB.DS = BNB.DS or {}
local DS = BNB.DS

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------
local PREFIX_BNB   = "BNB2"
local PREFIX_TAN   = "TAN1"
local MAX_CHUNK    = 180     -- chars per SendAddonMessage call
local CHUNK_TICK   = 0.35    -- seconds between chunk sends
local MAX_CHUNKS   = 140     -- hard cap (~25 KB encoded); reject above this
local INCOMING_TTL = 180     -- seconds before a partial reassembly is purged
local PROMPT_W     = 340
local PROMPT_H     = 148
local SK_TITLE_H   = 28
local PAD          = 12

--------------------------------------------------------------------------------
-- MODULE STATE
--------------------------------------------------------------------------------
local sendQueue       = {}   -- { msg, target }
local sendTicker      = nil
local incoming        = {}   -- keyed "sender|msgId" -> { chunks, count, total, t }
local tanParts        = {}   -- keyed "sender|sessionId" -> { parts, got, total, name, t }
local pendingIncoming = {}   -- queue of decoded data tables waiting for prompt
local currentPrompt   = nil  -- data table currently displayed in the prompt
local _prompt         = nil  -- the prompt frame (lazy built)

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------
local function GetDeflate()
    return LibStub and LibStub("LibDeflate", true)
end

local function GetLibSerialize()
    return LibStub and LibStub("LibSerialize", true)
end

local function GetRealmNorm()
    local r = GetNormalizedRealmName() or ""
    return r:gsub("%s+", "")
end

-- Append "-Realm" when no dash is present.
local function FullName(name)
    if not name or name == "" then return nil end
    name = name:match("^%s*(.-)%s*$")
    if name == "" then return nil end
    if not name:find("-", 1, true) then
        name = name .. "-" .. GetRealmNorm()
    end
    return name
end

-- Normalise for equality checks (lowercase).
local function NormName(name)
    if not name then return nil end
    local n = FullName(name)
    return n and n:lower() or nil
end

local function MyFullName()
    local p = UnitName("player") or ""
    return FullName(p)
end

--------------------------------------------------------------------------------
-- AUTO-REJECT
--------------------------------------------------------------------------------
function DS.IsAutoReject()
    local db = BigNoteBoxDB
    return db and db.directSend and db.directSend.autoReject == true
end

--------------------------------------------------------------------------------
-- SEND QUEUE TICKER
--------------------------------------------------------------------------------
local function StartTicker()
    if sendTicker then return end
    sendTicker = C_Timer.NewTicker(CHUNK_TICK, function()
        local pkt = table.remove(sendQueue, 1)
        if not pkt then
            sendTicker:Cancel()
            sendTicker = nil
            return
        end
        if C_ChatInfo and C_ChatInfo.SendAddonMessage then
            C_ChatInfo.SendAddonMessage(PREFIX_BNB, pkt.msg, "WHISPER", pkt.target)
        end
    end)
end

--------------------------------------------------------------------------------
-- SEND NOTE
-- noteID    : BNB note ID string
-- optionKey : "basic" | "refbox" | "tags" | "icon" | "everything"
-- target    : player name (realm appended if missing)
-- onSent(chunks) : called immediately after chunks are queued (fire-and-forget)
-- onFail(err)    : called if encoding fails before queuing
--------------------------------------------------------------------------------
function DS.SendNote(noteID, optionKey, targetName, onSent, onFail)
    local function fail(msg)
        if onFail then onFail(msg) end
    end

    -- Resolve note
    local ndb  = BigNoteBoxNotesDB
    local note = ndb and ndb.notes and ndb.notes[noteID]
    if not note then
        return fail(L["DS_ERR_NO_NOTE_DATA"])
    end

    -- Resolve target
    local target = FullName(targetName)
    if not target then
        return fail(L["DS_ERR_NO_TARGET"])
    end

    -- Build data table (same logic as ShareEncode)
    local fields = (BNB.DS_SHARE_FIELDS or {})[optionKey] or { "title", "body", "richMode" }
    local data   = {}
    for _, field in ipairs(fields) do
        if field == "attachments" then
            if note.attachments and #note.attachments > 0 and BNB.DS_EncodeAttachments then
                data["_att"] = BNB.DS_EncodeAttachments(note.attachments)
            end
        elseif note[field] ~= nil then
            data[field] = note[field]
        end
    end

    -- Serialize + compress + encode
    local ld = GetDeflate()
    if not ld then
        return fail(L["DS_ERR_GENERIC"])
    end
    local serialized = BNB.DS_Serialize and BNB.DS_Serialize(data)
    if not serialized then
        return fail(L["DS_ERR_NO_NOTE_DATA"])
    end
    local compressed = ld:CompressDeflate(serialized)
    local encoded    = ld:EncodeForWoWAddonChannel(compressed)

    -- Chunk count check
    local total = math.ceil(#encoded / MAX_CHUNK)
    if total > MAX_CHUNKS then
        return fail(string.format(L["DS_ERR_TOO_LARGE"], total))
    end

    -- Build a msgId: timestamp + 4 random digits
    local msgId = tostring(time()) .. tostring(math.random(1000, 9999))

    -- Enqueue
    for i = 1, total do
        local from = ((i - 1) * MAX_CHUNK) + 1
        local chunk = encoded:sub(from, from + MAX_CHUNK - 1)
        local msg   = msgId .. ":" .. i .. ":" .. total .. ":" .. chunk
        sendQueue[#sendQueue + 1] = { msg = msg, target = target }
    end
    StartTicker()

    if onSent then onSent(total) end
end

--------------------------------------------------------------------------------
-- INCOMING REASSEMBLY — BNB2
--------------------------------------------------------------------------------
local function CleanupIncoming()
    local now = time()
    for k, e in pairs(incoming) do
        if (now - (e.t or 0)) > INCOMING_TTL then
            incoming[k] = nil
        end
    end
    for k, e in pairs(tanParts) do
        if (now - (e.t or 0)) > INCOMING_TTL then
            tanParts[k] = nil
        end
    end
end

-- Called when all chunks for a BNB2 message have arrived.
local function HandleBNBPayload(encoded, sender)
    local ld = GetDeflate()
    if not ld then return end
    local compressed = ld:DecodeForWoWAddonChannel(encoded)
    if not compressed then return end
    local serialized = ld:DecompressDeflate(compressed)
    if not serialized then return end
    local data = BNB.DS_Deserialize and BNB.DS_Deserialize(serialized)
    if not data or (not data.title and not data.body) then return end

    -- Decode flat attachment string back into array (same as ShareDecode)
    if data._att and BNB.DS_DecodeAttachments then
        data.attachments = BNB.DS_DecodeAttachments(data._att)
        data._att = nil
    end

    data._sender    = sender
    data._senderVia = "BNB"
    pendingIncoming[#pendingIncoming + 1] = data
    DS.ShowNextPrompt()
end

--------------------------------------------------------------------------------
-- INCOMING REASSEMBLY — TAN1
-- TakeANote uses LibSerialize + LibDeflate:EncodeForWoWAddonChannel.
-- Envelope: { version=1, addon="TakeANote", kind=..., sender=..., data={...} }
-- kind "note"          -> data = { title, text, sourceCategory, sourceNoteIndex }
-- kind "mirror"        -> data = { title, text }
-- kind "category_part" -> data = { sessionId, partIndex, partTotal, name, notes=[{title,text}] }
--------------------------------------------------------------------------------
local function HandleTANEnvelope(payload, sender)
    if type(payload) ~= "table"
    or payload.version ~= 1
    or payload.addon   ~= "TakeANote" then
        return
    end

    local kind = payload.kind
    local data = payload.data or {}
    local from = payload.sender or sender or "?"

    -- Single note or mirror
    if kind == "note" or kind == "mirror" then
        local entry = {
            title    = data.title or "",
            body     = data.text  or "",
            _sender  = from,
            _senderVia = "TAN",
        }
        pendingIncoming[#pendingIncoming + 1] = entry
        DS.ShowNextPrompt()
        return
    end

    -- Category (multi-part streaming)
    if kind == "category_part" then
        local sessionId  = tostring(data.sessionId or "")
        local partIndex  = tonumber(data.partIndex)
        local partTotal  = tonumber(data.partTotal)
        if sessionId == "" or not partIndex or not partTotal then return end

        local key = NormName(from) .. "|" .. sessionId
        local agg = tanParts[key]
        if not agg then
            agg = {
                t      = time(),
                sender = from,
                name   = data.name or "Shared Category",
                total  = partTotal,
                got    = 0,
                parts  = {},
            }
            tanParts[key] = agg
        end
        if agg.cancelled then return end
        if not agg.parts[partIndex] then
            agg.parts[partIndex] = data.notes or {}
            agg.got = agg.got + 1
        end
        agg.t = time()

        if agg.got < agg.total then return end   -- waiting for more parts

        -- All parts received — flatten and queue one entry per note
        tanParts[key] = nil
        local allNotes = {}
        for i = 1, agg.total do
            local partNotes = agg.parts[i]
            if type(partNotes) == "table" then
                for _, n in ipairs(partNotes) do
                    allNotes[#allNotes + 1] = n
                end
            end
        end
        for _, n in ipairs(allNotes) do
            local entry = {
                title      = n.title or "",
                body       = n.text  or "",
                _sender    = agg.sender,
                _senderVia = "TAN",
            }
            pendingIncoming[#pendingIncoming + 1] = entry
        end
        DS.ShowNextPrompt()
    end
end

local function HandleTANPayload(encoded, sender)
    local ld  = GetDeflate()
    local ls  = GetLibSerialize()
    if not ld or not ls then return end

    local compressed = ld:DecodeForWoWAddonChannel(encoded)
    if not compressed then return end
    local serialized = ld:DecompressDeflate(compressed)
    if not serialized then return end
    local ok, payload = ls:Deserialize(serialized)
    if not ok then return end

    HandleTANEnvelope(payload, sender)
end

--------------------------------------------------------------------------------
-- CHUNK ROUTER
--------------------------------------------------------------------------------
local function OnAddonMessage(prefix, msg, _, sender)
    if prefix ~= PREFIX_BNB and prefix ~= PREFIX_TAN then return end
    if not msg or msg == "" then return end

    -- Ignore our own echoes
    local me = NormName(MyFullName())
    if me and NormName(sender) == me then return end

    -- Auto-reject: drop before reassembly so we never show a prompt
    if DS.IsAutoReject() then
        print(string.format(L["DS_AUTO_REJECTED"], sender or "?"))
        return
    end

    CleanupIncoming()

    -- Parse framing: msgId:idx:total:chunk
    local msgId, idxStr, totalStr, chunk =
        msg:match("^([^:]+):([^:]+):([^:]+):(.*)$")
    if not msgId then return end
    local idx   = tonumber(idxStr)
    local total = tonumber(totalStr)
    if not idx or not total or idx < 1 or total < 1 or idx > total then return end

    local key = (sender or "?") .. "|" .. msgId
    local e   = incoming[key]
    if not e then
        e = { total = total, chunks = {}, count = 0, t = time() }
        incoming[key] = e
    end
    if not e.chunks[idx] then
        e.count = e.count + 1
    end
    e.chunks[idx] = chunk
    e.t = time()
    if e.count < e.total then return end   -- still waiting for chunks

    -- All chunks in — assemble encoded string
    incoming[key] = nil
    local parts = {}
    for i = 1, e.total do
        if not e.chunks[i] then return end
        parts[i] = e.chunks[i]
    end
    local full = table.concat(parts, "")

    if prefix == PREFIX_BNB then
        HandleBNBPayload(full, sender)
    else
        HandleTANPayload(full, sender)
    end
end

--------------------------------------------------------------------------------
-- INCOMING PROMPT
-- Skin-aware: uses CreateSkinFrame + CreateSkinStrip + CreateSkinCloseButton
-- in skin mode, ButtonFrameTemplate in normal mode.
--------------------------------------------------------------------------------
local function BuildPromptSkin()
    local f = BNB.CreateSkinFrame(UIParent, false, "BNBDirectSendPrompt", false)
    _G["BNBDirectSendPrompt"] = f
    f:SetSize(PROMPT_W, PROMPT_H)
    f:SetFrameStrata("DIALOG"); f:SetToplevel(true)
    f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)

    local titleBar = BNB.CreateSkinStrip(f, true, false)
    titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    titleBar:SetHeight(SK_TITLE_H)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
    titleBar:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

    local titleLbl = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleLbl:SetPoint("CENTER", titleBar, "CENTER", -12, 0)
    titleLbl:SetTextColor(1, 0.82, 0)
    titleLbl:SetText(L["DS_PROMPT_TITLE"])

    local closeBtn = BNB.CreateSkinCloseButton(titleBar, function()
        currentPrompt = nil
        f:Hide()
        DS.ShowNextPrompt()
    end)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -3, 0)

    f:SetScript("OnShow", function()
        if BNB.ApplyMainWindowSkin then BNB.ApplyMainWindowSkin() end
    end)

    return f, SK_TITLE_H
end

local function BuildPromptNormal()
    local f = CreateFrame("Frame", "BNBDirectSendPrompt", UIParent, "ButtonFrameTemplate")
    _G["BNBDirectSendPrompt"] = f
    f:SetSize(PROMPT_W, PROMPT_H)
    f:SetFrameStrata("DIALOG"); f:SetToplevel(true)
    f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    ButtonFrameTemplate_HidePortrait(f)
    ButtonFrameTemplate_HideButtonBar(f)
    if f.Inset then f.Inset:Hide() end
    f:SetTitle(L["DS_PROMPT_TITLE"])
    return f, 32
end

local function EnsurePrompt()
    if _prompt then return _prompt end

    local skinMode = BigNoteBoxDB and BigNoteBoxDB.skinMode
    local f, titleH
    if skinMode then
        f, titleH = BuildPromptSkin()
    else
        f, titleH = BuildPromptNormal()
    end

    local y = -(titleH + PAD)

    -- "From:" line
    local fromLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fromLbl:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, y)
    fromLbl:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
    fromLbl:SetJustifyH("LEFT"); fromLbl:SetMaxLines(1)
    fromLbl:SetTextColor(0.78, 0.78, 0.78)
    f._fromLbl = fromLbl
    y = y - 18

    -- "Via:" line
    local viaLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    viaLbl:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, y)
    viaLbl:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
    viaLbl:SetJustifyH("LEFT"); viaLbl:SetMaxLines(1)
    viaLbl:SetTextColor(0.55, 0.55, 0.55)
    f._viaLbl = viaLbl
    y = y - 18

    -- "Title:" line
    local noteTitleLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    noteTitleLbl:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, y)
    noteTitleLbl:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
    noteTitleLbl:SetJustifyH("LEFT"); noteTitleLbl:SetMaxLines(2)
    noteTitleLbl:SetWordWrap(true)
    f._noteTitleLbl = noteTitleLbl
    y = y - 30

    -- Buttons (Accept / Decline), pinned to bottom of frame
    local acceptBtn = BNB.CreateButton(nil, f, L["DS_ACCEPT"], 120, 26)
    acceptBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, PAD)
    f._acceptBtn = acceptBtn

    local declineBtn = BNB.CreateButton(nil, f, L["DS_DECLINE"], 100, 26)
    declineBtn:SetPoint("LEFT", acceptBtn, "RIGHT", 8, 0)
    f._declineBtn = declineBtn

    declineBtn:SetScript("OnClick", function()
        if currentPrompt then
            print(string.format(L["DS_DECLINED_PRINT"], currentPrompt._sender or "?"))
        end
        currentPrompt = nil
        f:Hide()
        C_Timer.After(0, function() DS.ShowNextPrompt() end)
    end)

    acceptBtn:SetScript("OnClick", function()
        if currentPrompt then
            local data = currentPrompt
            currentPrompt = nil
            f:Hide()
            -- Strip internal tracking fields before handing to SharePreview
            data._sender    = nil
            data._senderVia = nil
            BNB.OpenSharePreview(data)
        else
            f:Hide()
        end
        C_Timer.After(0, function() DS.ShowNextPrompt() end)
    end)

    f:Hide()
    _prompt = f
    return f
end

--------------------------------------------------------------------------------
-- SHOW NEXT PROMPT
-- Dequeues one entry from pendingIncoming and displays it.
-- Called after each Accept / Decline, and whenever a new item is pushed.
--------------------------------------------------------------------------------
function DS.ShowNextPrompt()
    if currentPrompt then return end    -- already showing one
    if #pendingIncoming == 0 then return end

    currentPrompt = table.remove(pendingIncoming, 1)
    local f = EnsurePrompt()

    -- Populate labels
    if f._fromLbl then
        f._fromLbl:SetText(string.format(L["DS_PROMPT_FROM"], currentPrompt._sender or "?"))
    end
    if f._viaLbl then
        local viaKey = currentPrompt._senderVia == "TAN"
            and L["DS_PROMPT_VIA_TAN"] or L["DS_PROMPT_VIA_BNB"]
        f._viaLbl:SetText(viaKey)
    end
    if f._noteTitleLbl then
        local t = (currentPrompt.title and currentPrompt.title ~= "")
            and currentPrompt.title or ("|cff666666(" .. "untitled" .. ")|r")
        f._noteTitleLbl:SetText(string.format(L["DS_PROMPT_NOTE_TITLE"], t))
    end

    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    f:Show(); f:Raise()
end

--------------------------------------------------------------------------------
-- EVENT REGISTRATION
--------------------------------------------------------------------------------
local evtFrame = CreateFrame("Frame")
evtFrame:RegisterEvent("PLAYER_LOGIN")
evtFrame:RegisterEvent("CHAT_MSG_ADDON")
evtFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            C_ChatInfo.RegisterAddonMessagePrefix(PREFIX_BNB)
            C_ChatInfo.RegisterAddonMessagePrefix(PREFIX_TAN)
        end
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, channel, sender = ...
        OnAddonMessage(prefix, msg, channel, sender)
    end
end)

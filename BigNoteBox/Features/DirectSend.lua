-- BigNoteBox Features/DirectSend.lua
-- Direct addon-message note sharing between players.
--
-- Protocols supported:
--   BNB3  (send + receive)  — BNB-to-BNB direct send, LibSerialize payload
--                             (ALL-136.5), the same one as a BNB2: share string.
--   BNB2  (receive only)    — the old hand-made format, from players on
--                             versions before ALL-136.5.
--   TAN1  (receive only)    — TakeANote compatibility; incoming TAN notes/
--                             categories are translated and queued as BNB notes.
--
-- Transport pipeline (send):
--   BNB.ShareBuildPayload -> BNB.ShareSerialize -> CompressDeflate
--   -> EncodeForWoWAddonChannel -> chunk (MAX_CHUNK chars)
--   -> C_ChatInfo.SendAddonMessage("BNB3", chunk, "WHISPER", target)
--   Paced to the server's per-prefix allowance (BURST messages, then REGEN per
--   second); a throttled chunk is sent again, a refused one ends the send (BUG-30).
--
-- Transport pipeline (receive BNB3 / BNB2):
--   Reassemble chunks -> DecodeForWoWAddonChannel -> DecompressDeflate
--   -> BNB.ShareDeserialize (BNB3) / BNB.ShareReadV1 (BNB2)
--   -> queue -> incoming prompt -> BNB.OpenSharePreview
--
-- Transport pipeline (receive TAN1):
--   Reassemble chunks -> DecodeForWoWAddonChannel -> DecompressDeflate
--   -> LibSerialize:Deserialize -> map fields -> queue -> prompt
--
-- Receive: whispers only (Dukul, 2026-10-02); at most MAX_CHUNKS chunks per
-- message and MAX_INCOMING messages being put together at once.
--
-- Public API:
--   BNB.DS.SendNote(noteID, groups, targetName, onSent, onFail, onProgress, onDone)
--   BNB.DS.IsAutoReject()

local BNB = BigNoteBox
local L   = BNB.L

BNB.DS = BNB.DS or {}
local DS = BNB.DS

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------
local PREFIX_BNB   = "BNB3"
local PREFIX_BNB_V1 = "BNB2"   -- old format, receive only
local PREFIX_TAN   = "TAN1"
local MAX_CHUNK    = 230     -- chars per message; + "msgId:idx:total:" stays under 255
local SEND_TICK    = 0.1     -- seconds between send attempts
local BURST        = 10      -- the server's per-prefix allowance...
local REGEN        = 1       -- ...refilled by this many messages per second
local MAX_RETRIES  = 30      -- throttled attempts on one chunk before giving up
local DONE_DELAY   = 1.5     -- seconds after the last chunk before "sent" (offline check)
local MAX_CHUNKS   = 140     -- hard cap (~32 KB encoded); reject above this
local MAX_INCOMING = 20      -- messages being reassembled at once; more are dropped
local INCOMING_TTL = 180     -- seconds before a partial reassembly is purged
local PROMPT_W     = 340
local PROMPT_H     = 148
local SK_TITLE_H   = 28
local PAD          = 12

--------------------------------------------------------------------------------
-- MODULE STATE
--------------------------------------------------------------------------------
local sendQueue       = {}   -- { msg, target, job }
local sendTicker      = nil
local sendTokens      = BURST -- messages we may send right now
local sendRefillAt    = 0     -- GetTime() of the last refill
local activeJobs      = {}    -- job -> true from queueing until "sent" or a failure
local incoming        = {}   -- keyed "sender|msgId" -> { chunks, count, total, t }
local incomingCount   = 0
local rejected        = {}   -- "sender|msgId" -> time(), so auto-reject prints once per note
local tanParts        = {}   -- keyed "sender|sessionId" -> { parts, got, total, name, t }
local pendingIncoming = {}   -- queue of decoded data tables waiting for prompt
local currentPrompt   = nil  -- data table currently displayed in the prompt
local _prompt         = nil  -- the prompt frame (lazy built)

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------
local GetDeflate = BNB.GetDeflate

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

-- FOR-23: BNB.UnitNameRealm, so a Forever surname is part of the name
local function MyFullName()
    local name, realm = BNB.UnitNameRealm("player")
    if not name then return nil end
    realm = (realm and realm ~= "") and realm:gsub("%s+", "") or GetRealmNorm()
    return name .. "-" .. realm
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
-- SendAddonMessage returns an Enum.SendAddonMessageResult (a boolean, or
-- nothing, on older builds). Sorted by name so new codes need no change here:
-- "ok", "throttle" (send it again later), or a reason that ends the send.
local RESULT_NAMES
local function ClassifyResult(res)
    if res == nil or res == true then return "ok" end
    if res == false then return "throttle" end
    if type(res) ~= "number" then return "ok" end
    if not RESULT_NAMES then
        RESULT_NAMES = {}
        local enum = Enum and Enum.SendAddonMessageResult
        if type(enum) == "table" then
            for k, v in pairs(enum) do RESULT_NAMES[v] = tostring(k):lower() end
        end
    end
    local name = RESULT_NAMES[res]
    if not name then
        if res == 0 then return "ok" end
        if res == 3 or res == 8 then return "throttle" end
        return "error"
    end
    if name == "success" then return "ok" end
    if name:find("throttle", 1, true) then return "throttle" end
    if name:find("lockdown", 1, true) then return "lockdown" end
    if name:find("offline", 1, true) then return "offline" end
    return name
end

local FAIL_TEXT = {
    lockdown = "DS_FAIL_LOCKDOWN",
    offline  = "DS_FAIL_OFFLINE",
    throttle = "DS_FAIL_THROTTLE",
}

-- Ends a send early: drops its queued chunks and tells the sender why.
local function FailJob(job, reason)
    if job.ended then return end
    job.ended = true
    activeJobs[job] = nil
    for i = #sendQueue, 1, -1 do
        if sendQueue[i].job == job then table.remove(sendQueue, i) end
    end
    local key = FAIL_TEXT[reason]
    local why = key and L[key] or string.format(L["DS_FAIL_CODE"], tostring(reason))
    BNB:Print(string.format(L["DS_FAIL_PRINT"], job.title, job.target, why))
    if job.onFail then pcall(job.onFail, why) end
end

local function SendTick()
    local now = GetTime()
    sendTokens = math.min(BURST, sendTokens + (now - sendRefillAt) * REGEN)
    sendRefillAt = now

    while sendTokens >= 1 and sendQueue[1] do
        local pkt = sendQueue[1]
        local job = pkt.job
        local res
        if C_ChatInfo and C_ChatInfo.SendAddonMessage then
            res = C_ChatInfo.SendAddonMessage(PREFIX_BNB, pkt.msg, "WHISPER", pkt.target)
        end
        local kind = ClassifyResult(res)
        if kind == "ok" then
            table.remove(sendQueue, 1)
            sendTokens = sendTokens - 1
            job.sent = job.sent + 1
            if job.onProgress then pcall(job.onProgress, job.sent, job.total) end
            if job.sent >= job.total then
                -- Wait a moment: an offline target only shows as a system line
                C_Timer.After(DONE_DELAY, function()
                    if job.ended then return end
                    job.ended = true
                    activeJobs[job] = nil
                    BNB:Print(string.format(L["DS_SENT_PRINT"], job.title, job.target))
                    if job.onDone then pcall(job.onDone) end
                end)
            end
        elseif kind == "throttle" then
            -- The server's allowance is lower than ours: wait for a refill
            sendTokens = 0
            pkt.tries = (pkt.tries or 0) + 1
            if pkt.tries > MAX_RETRIES then FailJob(job, "throttle") end
            break
        else
            FailJob(job, kind)
        end
    end

    if not sendQueue[1] and sendTicker then
        sendTicker:Cancel()
        sendTicker = nil
    end
end

-- A whisper to someone offline is not refused by SendAddonMessage: the server
-- answers each chunk with ERR_CHAT_PLAYER_NOT_FOUND_S instead. End that send.
local function OnSystemMessage(msg)
    if not ERR_CHAT_PLAYER_NOT_FOUND_S or not next(activeJobs) then return end
    local hit = {}
    for job in pairs(activeJobs) do
        local short = job.target:match("^([^-]+)") or job.target
        if msg == ERR_CHAT_PLAYER_NOT_FOUND_S:format(job.target)
        or msg == ERR_CHAT_PLAYER_NOT_FOUND_S:format(short) then
            hit[#hit + 1] = job
        end
    end
    for _, job in ipairs(hit) do FailJob(job, "offline") end
end

local function StartTicker()
    if sendTicker then return end
    if not sendQueue[1] then return end
    -- Refill for the time the ticker was idle, then send what the allowance takes
    SendTick()
    if sendQueue[1] and not sendTicker then
        sendTicker = C_Timer.NewTicker(SEND_TICK, SendTick)
    end
end

--------------------------------------------------------------------------------
-- SEND NOTE
-- noteID    : BNB note ID string
-- groups    : share groups to include, { tags = true, ... } (BNB.GetShareGroups)
-- target    : player name (realm appended if missing)
-- onSent(chunks) : called once the chunks are queued
-- onFail(err)    : called if encoding fails, or the send is refused part way
-- onProgress(sent, total) : called after each chunk goes out
-- onDone()       : called when the last chunk went out
-- A chat line reports the end of the send either way, since a long note takes
-- a while and the Share window may be closed by then.
--------------------------------------------------------------------------------
function DS.SendNote(noteID, groups, targetName, onSent, onFail, onProgress, onDone)
    local function fail(msg)
        if onFail then onFail(msg) end
    end

    -- Resolve note
    local ndb  = BNB.NotesDB()
    local note = ndb and ndb.notes and ndb.notes[noteID]
    if not note then
        return fail(L["DS_ERR_NO_NOTE_DATA"])
    end

    -- Resolve target
    local target = FullName(targetName)
    if not target then
        return fail(L["DS_ERR_NO_TARGET"])
    end

    -- Same payload as a share string (ShareNote.lua)
    local payload = BNB.ShareBuildPayload and BNB.ShareBuildPayload(noteID, groups)
    if not payload then
        return fail(L["DS_ERR_NO_NOTE_DATA"])
    end

    -- Serialize + compress + encode
    local ld = GetDeflate()
    if not ld then
        return fail(L["DS_ERR_GENERIC"])
    end
    local serialized = BNB.ShareSerialize(payload)
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
    local job = {
        target = target, total = total, sent = 0,
        title  = (note.title and note.title ~= "") and note.title or L["TW_UNTITLED"],
        onFail = onFail, onProgress = onProgress, onDone = onDone,
    }
    for i = 1, total do
        local from = ((i - 1) * MAX_CHUNK) + 1
        local chunk = encoded:sub(from, from + MAX_CHUNK - 1)
        local msg   = msgId .. ":" .. i .. ":" .. total .. ":" .. chunk
        sendQueue[#sendQueue + 1] = { msg = msg, target = target, job = job }
    end
    activeJobs[job] = true

    if onSent then onSent(total) end
    StartTicker()
end

--------------------------------------------------------------------------------
-- INCOMING REASSEMBLY — BNB2
--------------------------------------------------------------------------------
local function CleanupIncoming()
    local now = time()
    for k, e in pairs(incoming) do
        if (now - (e.t or 0)) > INCOMING_TTL then
            incoming[k] = nil
            incomingCount = incomingCount - 1
        end
    end
    for k, t in pairs(rejected) do
        if (now - t) > INCOMING_TTL then rejected[k] = nil end
    end
    for k, e in pairs(tanParts) do
        if (now - (e.t or 0)) > INCOMING_TTL then
            tanParts[k] = nil
        end
    end
end

-- Called when all chunks for a BNB3 (or old BNB2) message have arrived.
-- Both readers keep only share fields of the right type and shape.
local function HandleBNBPayload(encoded, sender, oldFormat)
    local ld = GetDeflate()
    if not ld then return end
    local compressed = ld:DecodeForWoWAddonChannel(encoded)
    if not compressed then return end
    local serialized = ld:DecompressDeflate(compressed)
    if not serialized then return end
    local data
    if oldFormat then data = BNB.ShareReadV1(serialized) else data = BNB.ShareDeserialize(serialized) end
    if not data then return end

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
local function OnAddonMessage(prefix, msg, channel, sender)
    if prefix ~= PREFIX_BNB and prefix ~= PREFIX_BNB_V1 and prefix ~= PREFIX_TAN then return end
    if not msg or msg == "" then return end
    -- Whispers only: a group or guild broadcast would prompt everyone in it
    if channel ~= "WHISPER" then return end

    -- Ignore our own echoes
    local me = NormName(MyFullName())
    if me and NormName(sender) == me then return end

    CleanupIncoming()

    -- Parse framing: msgId:idx:total:chunk
    local msgId, idxStr, totalStr, chunk =
        msg:match("^([^:]+):([^:]+):([^:]+):(.*)$")
    if not msgId then return end
    local idx   = tonumber(idxStr)
    local total = tonumber(totalStr)
    if not idx or not total or idx < 1 or total < 1 or idx > total then return end
    if total > MAX_CHUNKS then return end

    local key = (sender or "?") .. "|" .. msgId

    -- Auto-reject: drop before reassembly so we never show a prompt. One chat
    -- line per note, not one per chunk.
    if DS.IsAutoReject() then
        if not rejected[key] then
            print(string.format(L["DS_AUTO_REJECTED"], sender or "?"))
        end
        rejected[key] = time()
        return
    end

    local e   = incoming[key]
    if not e then
        if incomingCount >= MAX_INCOMING then return end
        e = { total = total, chunks = {}, count = 0, t = time() }
        incoming[key] = e
        incomingCount = incomingCount + 1
    end
    if total ~= e.total then return end
    if not e.chunks[idx] then
        e.count = e.count + 1
    end
    e.chunks[idx] = chunk
    e.t = time()
    if e.count < e.total then return end   -- still waiting for chunks

    -- All chunks in — assemble encoded string
    incoming[key] = nil
    incomingCount = incomingCount - 1
    local parts = {}
    for i = 1, e.total do
        if not e.chunks[i] then return end
        parts[i] = e.chunks[i]
    end
    local full = table.concat(parts, "")

    if prefix == PREFIX_BNB or prefix == PREFIX_BNB_V1 then
        HandleBNBPayload(full, sender, prefix == PREFIX_BNB_V1)
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
    BNB.SeatChrome(f)   -- FOR-05: Forever border offset (UI/Chrome.lua)
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
            and currentPrompt.title or L["TW_UNTITLED"]
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
evtFrame:RegisterEvent("CHAT_MSG_SYSTEM")
evtFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            C_ChatInfo.RegisterAddonMessagePrefix(PREFIX_BNB)
            C_ChatInfo.RegisterAddonMessagePrefix(PREFIX_BNB_V1)
            C_ChatInfo.RegisterAddonMessagePrefix(PREFIX_TAN)
        end
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, channel, sender = ...
        OnAddonMessage(prefix, msg, channel, sender)
    elseif event == "CHAT_MSG_SYSTEM" then
        -- pcall: chat text can be a secret value on Midnight (DEP-01)
        pcall(OnSystemMessage, (...))
    end
end)

-- BigNoteBox Features/ShareNote.lua
-- Note sharing via compressed, printable share strings.
--
-- Pipeline (share):
--   Serialize note fields -> CompressDeflate -> EncodeForPrint -> "BNB1:<data>"
-- Pipeline (import):
--   Strip prefix -> DecodeForPrint -> DecompressDeflate -> deserialize -> preview -> create note
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

local SHARE_PREFIX  = "BNB1:"
local SHARE_W       = 420
local PREVIEW_W     = 420
local PREVIEW_H     = 380
local PAD           = 12

-- Dropdown option definitions
local SHARE_OPTIONS = {
    { key = "basic",      label = "Title and body" },
    { key = "tasks",      label = "Title, body and tasks" },
    { key = "refbox",     label = "Title, body and refbox" },
    { key = "tags",       label = "Title, body, tags and refbox" },
    { key = "icon",       label = "Title, body, tags, icon and refbox" },
    { key = "inspect",    label = "Title, body, tags, icon, refbox and inspect data" },
    { key = "everything", label = "Everything" },
}
local SHARE_FIELDS = {
    basic      = { "title", "body", "richMode" },
    tasks      = { "title", "body", "richMode", "tasks", "taskList" },
    refbox     = { "title", "body", "richMode", "attachments" },
    tags       = { "title", "body", "richMode", "attachments", "tags" },
    icon       = { "title", "body", "richMode", "attachments", "tags", "icon", "iconSource" },
    inspect    = {
        "title", "body", "richMode", "attachments", "tags", "icon", "iconSource",
        "source", "targetNpcID", "targetPlayerKey", "targetIsPet",
        "inspectRaceID", "inspectSexID",
        "inspectGearItems", "inspectTransmogItems",
    },
    everything = {
        "title", "body", "richMode", "attachments", "tags", "icon", "iconSource",
        "context", "contextDisplay", "contextLeave",
        "titleColor", "fontOverride", "fontSize",
        "textAlign", "fontOutline",
        "borderOverride", "borderScale", "borderOffset", "borderBrightness",
        "lineHeight", "scope", "waypoint", "wpClearOnLeave",
        "source", "targetNpcID", "targetPlayerKey", "targetIsPet",
        "inspectRaceID", "inspectSexID",
        "inspectGearItems", "inspectTransmogItems",
        "tasks", "taskList",
    },
}

-- Module state
local _shareFrame   = nil
local _previewFrame = nil
local _importFrame  = nil
local _shareNoteID  = nil
local _selOption    = "basic"

--------------------------------------------------------------------------------
-- ATTACHMENT ENCODE / DECODE
-- Flat format: "type:id|type:id" e.g. "item:12345|spell:67890"
-- Attachment objects are always {type=string, id=number}.
--------------------------------------------------------------------------------
local ATT_SEP = "|"
local ATT_KV  = ":"

local function EncodeAttachments(arr)
    if not arr or #arr == 0 then return "" end
    local parts = {}
    for _, a in ipairs(arr) do
        if a.type and a.id then
            parts[#parts + 1] = tostring(a.type) .. ATT_KV .. tostring(a.id)
        end
    end
    return table.concat(parts, ATT_SEP)
end

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

--------------------------------------------------------------------------------
-- SERIALIZATION
-- Simple key=value format. Values are JSON-escaped strings or numbers.
-- Tables (tags, titleColor) are encoded as nested JSON arrays/objects.
-- Delimiter: unit separator \031 between fields, \030 between key and value.
--------------------------------------------------------------------------------
local SEP_FIELD = "\031"
local SEP_KV    = "\030"

local function EscStr(s)
    return (tostring(s or ""))
        :gsub("\\", "\\\\")
        :gsub(SEP_FIELD, "\\f")
        :gsub(SEP_KV,    "\\k")
end

local function UnescStr(s)
    return (s or "")
        :gsub("\\k",  SEP_KV)
        :gsub("\\f",  SEP_FIELD)
        :gsub("\\\\", "\\")
end

local function SerializeValue(v)
    local t = type(v)
    if t == "string" then
        return "s" .. EscStr(v)
    elseif t == "number" then
        return "n" .. tostring(v)
    elseif t == "boolean" then
        return "b" .. (v and "1" or "0")
    elseif t == "table" then
        -- Encode as a simple JSON-like string for safety
        local parts = {}
        for k, val in pairs(v) do
            local vt = type(val)
            local enc
            if vt == "string" then
                enc = '"' .. EscStr(val) .. '"'
            elseif vt == "number" then
                enc = tostring(val)
            elseif vt == "boolean" then
                enc = val and "true" or "false"
            else
                enc = "null"
            end
            if type(k) == "number" then
                parts[k] = enc
            else
                parts[#parts + 1] = '"' .. EscStr(tostring(k)) .. '":' .. enc
            end
        end
        -- Detect array vs object: arrays have only numeric keys 1..n
        local isArray = (#v > 0)
        if isArray then
            local arr = {}
            for i = 1, #v do arr[i] = parts[i] or "null" end
            return "t[" .. table.concat(arr, ",") .. "]"
        else
            return "t{" .. table.concat(parts, ",") .. "}"
        end
    end
    return "s"
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

local function Serialize(tbl)
    local parts = {}
    for k, v in pairs(tbl) do
        parts[#parts + 1] = EscStr(tostring(k)) .. SEP_KV .. SerializeValue(v)
    end
    return table.concat(parts, SEP_FIELD)
end

local function Deserialize(str)
    if not str or str == "" then return nil end
    local result = {}
    for field in (str .. SEP_FIELD):gmatch("(.-)" .. SEP_FIELD) do
        local k, v = field:match("^(.-)" .. SEP_KV .. "(.+)$")
        if k and v then
            result[UnescStr(k)] = DeserializeValue(v)
        end
    end
    return result
end

--------------------------------------------------------------------------------
-- COMPRESS / ENCODE
--------------------------------------------------------------------------------
local function GetDeflate()
    return LibStub and LibStub("LibDeflate", true)
end

function BNB.ShareEncode(noteID, optionKey)
    local ndb  = BigNoteBoxNotesDB
    local note = ndb and ndb.notes and ndb.notes[noteID]
    if not note then return nil, "Note not found" end

    local fields = SHARE_FIELDS[optionKey] or SHARE_FIELDS.basic
    local data   = {}
    for _, field in ipairs(fields) do
        if field == "attachments" then
            -- Encode attachment array as flat string; skip if empty
            if note.attachments and #note.attachments > 0 then
                data["_att"] = EncodeAttachments(note.attachments)
            end
        elseif note[field] ~= nil then
            data[field] = note[field]
        end
    end

    local serialized = Serialize(data)
    local ld = GetDeflate()
    local encoded
    if ld then
        local compressed = ld:CompressDeflate(serialized)
        encoded = ld:EncodeForPrint(compressed)
    else
        -- Fallback: no compression, Base64-like via EncodeForPrint stub
        -- This path should never be hit if LibDeflate is loaded
        encoded = serialized
    end
    return SHARE_PREFIX .. encoded
end

function BNB.ShareDecode(str)
    if not str or str == "" then return nil, "Empty string" end
    str = str:match("^%s*(.-)%s*$")  -- trim whitespace

    if str:sub(1, #SHARE_PREFIX) ~= SHARE_PREFIX then
        return nil, "Not a valid BNB share string (missing prefix)"
    end
    local encoded = str:sub(#SHARE_PREFIX + 1)

    local ld = GetDeflate()
    local serialized
    if ld then
        local compressed = ld:DecodeForPrint(encoded)
        if not compressed then return nil, "Failed to decode (corrupt or wrong format)" end
        serialized = ld:DecompressDeflate(compressed)
        if not serialized then return nil, "Failed to decompress (corrupt data)" end
    else
        serialized = encoded
    end

    local data = Deserialize(serialized)
    if not data or not data.title and not data.body then
        return nil, "Failed to deserialize (no content found)"
    end
    -- Decode flat attachment string back into array
    if data._att then
        data.attachments = DecodeAttachments(data._att)
        data._att = nil
    end
    return data
end

--------------------------------------------------------------------------------
-- PREVIEW WINDOW
-- Opens when the user clicks "Preview" after pasting a share string.
-- Shows decoded title + scrollable body. "Add Note" or "Discard" buttons.
--------------------------------------------------------------------------------
local SK_PREV_TITLE_H = 28

local function BuildSharePreviewSkin()
    local f = BNB.CreateSkinFrame(UIParent, false, "BNBSharePreviewFrame", false)
    _G["BNBSharePreviewFrame"] = f
    f:SetSize(PREVIEW_W, PREVIEW_H)
    f:SetFrameStrata("DIALOG"); f:SetToplevel(true)
    f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)

    local titleBar = BNB.CreateSkinStrip(f, true, false)
    titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    titleBar:SetHeight(SK_PREV_TITLE_H)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
    titleBar:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

    local titleLbl = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleLbl:SetPoint("CENTER", titleBar, "CENTER", -12, 0)
    titleLbl:SetTextColor(1, 0.82, 0)
    titleLbl:SetText("Preview Shared Note")
    f._titleLbl = titleLbl

    local closeBtn = BNB.CreateSkinCloseButton(titleBar, function() BNB.CloseSharePreview() end)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -3, 0)

    f:SetScript("OnShow", function()
        if BNB.ApplyMainWindowSkin then BNB.ApplyMainWindowSkin() end
    end)

    return f, SK_PREV_TITLE_H
end

local function BuildSharePreviewNormal()
    local f = CreateFrame("Frame", "BNBSharePreviewFrame", UIParent, "ButtonFrameTemplate")
    f:SetSize(PREVIEW_W, PREVIEW_H)
    f:SetFrameStrata("DIALOG"); f:SetToplevel(true)
    f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    ButtonFrameTemplate_HidePortrait(f)
    ButtonFrameTemplate_HideButtonBar(f)
    if f.Inset then f.Inset:Hide() end
    f:SetTitle("Preview Shared Note")
    if f.CloseButton then
        f.CloseButton:SetScript("OnClick", function() BNB.CloseSharePreview() end)
    end
    return f, 32
end

local function BuildSharePreview()
    if _previewFrame then return _previewFrame end

    local skinMode = BigNoteBoxDB and BigNoteBoxDB.skinMode
    local f, titleH
    if skinMode then
        f, titleH = BuildSharePreviewSkin()
    else
        f, titleH = BuildSharePreviewNormal()
    end

    local FOOT_H = 44

    -- Note title label
    local noteTitleLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    noteTitleLbl:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, -(titleH + 10))
    noteTitleLbl:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -(titleH + 10))
    noteTitleLbl:SetJustifyH("LEFT")
    noteTitleLbl:SetHeight(22)
    noteTitleLbl:SetTextColor(1, 0.82, 0)
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
    local sf = CreateFrame("ScrollFrame", nil, f, "ScrollFrameTemplate")
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

    local bodyLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bodyLbl:SetPoint("TOPLEFT",  ct, "TOPLEFT",  0, 0)
    bodyLbl:SetPoint("TOPRIGHT", ct, "TOPRIGHT", 0, 0)
    bodyLbl:SetJustifyH("LEFT"); bodyLbl:SetJustifyV("TOP")
    bodyLbl:SetWordWrap(true)
    bodyLbl:SetTextColor(0.85, 0.85, 0.85)
    f._bodyLbl = bodyLbl

    -- Refbox attachments label (shown only when data has attachments)
    local attLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
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
    local addBtn = BNB.CreateButton(nil, f, "Add Note", 90, 26)
    addBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, 10)
    addBtn:SetScript("OnClick", function()
        local data = f._pendingData
        if not data then return end
        local id = BNB.CreateNote(data.title or "")
        if id then
            local updates = {}
            local skip = { title = true, attachments = true }
            for _, field in ipairs({
                "body", "richMode", "tags", "icon", "iconSource",
                "context", "contextDisplay", "contextLeave",
                "titleColor", "fontOverride", "fontSize", "textAlign", "fontOutline",
                "borderOverride", "borderScale", "borderOffset", "borderBrightness",
                "lineHeight", "scope", "waypoint", "wpClearOnLeave",
                "source", "targetNpcID", "targetPlayerKey", "targetIsPet",
                "inspectRaceID", "inspectSexID",
                "inspectGearItems", "inspectTransmogItems",
            }) do
                if data[field] ~= nil and not skip[field] then
                    updates[field] = data[field]
                end
            end
            if next(updates) then BNB.UpdateNote(id, updates) end
            -- Import attachments via the proper API so refbox badge updates
            if data.attachments and BNB.RBAddAttachment then
                for _, a in ipairs(data.attachments) do
                    BNB.RBAddAttachment(id, a)
                end
            end
            if BNB.RefreshNoteList then BNB.RefreshNoteList() end
            if BNB.SelectNote     then BNB.SelectNote(id)    end
            BNB:Print("|cff66bb6aNote imported successfully.|r")
        end
        BNB.CloseSharePreview()
        BNB.CloseShareWindow()
        BNB.CloseImportWindow()
    end)
    f._addBtn = addBtn

    -- Discard button
    local discardBtn = BNB.CreateButton(nil, f, "Discard", 80, 26)
    discardBtn:SetPoint("LEFT", addBtn, "RIGHT", 8, 0)
    discardBtn:SetScript("OnClick", function() BNB.CloseSharePreview() end)

    f:EnableKeyboard(true)
    f:SetScript("OnKeyDown", function(self, key)
        -- Propagate non-ESCAPE keys so they can reach focused editboxes below
        -- (e.g. the BNB clipboard helper editbox for Ctrl+C). HIGH strata +
        -- SetToplevel + EnableKeyboard otherwise swallows all keys here.
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            BNB.CloseSharePreview()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
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
                    local name = GetItemInfo(a.id)
                    label = name and ("[" .. name .. "]") or ("Item:" .. a.id)
                elseif a.type == "spell" then
                    local si = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(a.id)
                    label = (si and si.name) and si.name or ("Spell:" .. a.id)
                else
                    label = a.type .. ":" .. a.id
                end
                parts[#parts + 1] = label
            end
            f._attLbl:SetText("|cff88cc88Refbox:|r " .. table.concat(parts, ", "))
            f._attLbl:Show()
        else
            f._attLbl:Hide()
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
local SK_SHARE_TITLE_H = 28

local function BuildShareWindowSkin()
    local f = BNB.CreateSkinFrame(UIParent, false, "BNBShareFrame", false)
    _G["BNBShareFrame"] = f
    f:SetSize(SHARE_W, 340)
    f:SetFrameStrata("HIGH"); f:SetToplevel(true)
    f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)

    local titleBar = BNB.CreateSkinStrip(f, true, false)
    titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    titleBar:SetHeight(SK_SHARE_TITLE_H)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
    titleBar:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

    local titleLbl = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleLbl:SetPoint("CENTER", titleBar, "CENTER", -12, 0)
    titleLbl:SetTextColor(1, 0.82, 0)
    titleLbl:SetText("Share Note")

    local closeBtn = BNB.CreateSkinCloseButton(titleBar, function() BNB.CloseShareWindow() end)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -3, 0)

    f:SetScript("OnShow", function()
        if BNB.ApplyMainWindowSkin then BNB.ApplyMainWindowSkin() end
    end)

    return f, SK_SHARE_TITLE_H
end

local function BuildShareWindowNormal()
    local f = CreateFrame("Frame", "BNBShareFrame", UIParent, "ButtonFrameTemplate")
    f:SetSize(SHARE_W, 340)
    f:SetFrameStrata("HIGH"); f:SetToplevel(true)
    f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    ButtonFrameTemplate_HidePortrait(f)
    ButtonFrameTemplate_HideButtonBar(f)
    if f.Inset then f.Inset:Hide() end
    f:SetTitle("Share Note")
    if f.CloseButton then
        f.CloseButton:SetScript("OnClick", function() BNB.CloseShareWindow() end)
    end
    return f, 32
end

local function BuildShareWindow()
    if _shareFrame then return _shareFrame end

    local skinMode = BigNoteBoxDB and BigNoteBoxDB.skinMode
    local f, titleH
    if skinMode then
        f, titleH = BuildShareWindowSkin()
    else
        f, titleH = BuildShareWindowNormal()
    end

    local y = -(titleH + 10)
    local CW = SHARE_W - PAD * 2

    -- ── SHARE OUT ─────────────────────────────────────────────────────────────
    local shareHdr = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    shareHdr:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    shareHdr:SetTextColor(1, 0.82, 0)
    shareHdr:SetText("Share")
    y = y - 20

    -- What to include dropdown
    local ddLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ddLbl:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    ddLbl:SetTextColor(0.78, 0.78, 0.78)
    ddLbl:SetText("Include:")
    y = y - 18

    local useNativeDD = C_XMLUtil and C_XMLUtil.GetTemplateInfo
        and C_XMLUtil.GetTemplateInfo("WowStyle1DropdownTemplate")

    local function RegenerateShareString()
        if not _shareNoteID then return end
        local str, err = BNB.ShareEncode(_shareNoteID, _selOption)
        if str and f._shareEB then
            f._shareEB:SetText(str)
        elseif f._shareEB then
            f._shareEB:SetText(err or "Error generating share string")
        end
    end

    if useNativeDD then
        local dd = CreateFrame("DropdownButton", nil, f, "WowStyle1DropdownTemplate")
        dd:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, y)
        dd:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
        dd:SetHeight(26)
        local function RebuildDD()
            dd:SetupMenu(function(_, root)
                for _, opt in ipairs(SHARE_OPTIONS) do
                    local key = opt.key
                    root:CreateRadio(opt.label,
                        function() return _selOption == key end,
                        function()
                            _selOption = key
                            dd:GenerateMenu()
                            RegenerateShareString()
                        end)
                end
            end)
        end
        RebuildDD()
        f._shareDD = dd
        f._rebuildDD = RebuildDD
    else
        -- Fallback: cycling button
        local function GetCurrentLabel()
            for _, opt in ipairs(SHARE_OPTIONS) do
                if opt.key == _selOption then return opt.label end
            end
            return SHARE_OPTIONS[1].label
        end
        local cycleBtn = BNB.CreateButton(nil, f, GetCurrentLabel(), CW, 24)
        cycleBtn:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
        cycleBtn:SetScript("OnClick", function(self)
            local idx = 1
            for i, opt in ipairs(SHARE_OPTIONS) do
                if opt.key == _selOption then idx = i; break end
            end
            idx = (idx % #SHARE_OPTIONS) + 1
            _selOption = SHARE_OPTIONS[idx].key
            self:SetText(SHARE_OPTIONS[idx].label)
            RegenerateShareString()
        end)
        f._shareCycleBtn = cycleBtn
    end
    y = y - 32

    -- Share string editbox
    local shareBg = BNB.CreateBackdropFrame("Frame", nil, f)
    BNB.SetBackdropDark(shareBg)
    shareBg:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, y)
    shareBg:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
    shareBg:SetHeight(52)

    local shareEB = CreateFrame("EditBox", nil, shareBg)
    shareEB:SetPoint("TOPLEFT",     shareBg, "TOPLEFT",     4,  -4)
    shareEB:SetPoint("BOTTOMRIGHT", shareBg, "BOTTOMRIGHT", -4,  4)
    shareEB:SetFontObject("GameFontNormalSmall")
    shareEB:SetMultiLine(false)
    shareEB:SetAutoFocus(false)
    shareEB:SetMaxLetters(0)
    shareEB:SetTextInsets(2, 2, 2, 2)
    shareEB:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    shareEB:SetScript("OnEscapePressed",   function(self) self:ClearFocus() end)
    f._shareEB = shareEB
    y = y - 58

    -- Copy hint button
    local copyBtn = BNB.CreateButton(nil, f, "Copy to Clipboard", 140, 24)
    copyBtn:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    copyBtn:SetScript("OnClick", function()
        local str = f._shareEB and f._shareEB:GetText() or ""
        -- deferFocus=true: synchronous focus is unreliable from this OnClick
        -- path, so defer one tick before setting focus on the helper.
        if str ~= "" then BNB.ShowClipboardHint(str, copyBtn, true) end
    end)

    -- BCB send button (or "Get BCB" if absent)
    local bcbShareBtn = BNB.CreateButton(nil, f, "Send with BCB", 110, 24)
    bcbShareBtn:SetPoint("LEFT", copyBtn, "RIGHT", 6, 0)
    local function RefreshBCBShareBtn()
        local hasBCB = BigChatBox and BigChatBox.SendDirect and true or false
        bcbShareBtn:SetText(hasBCB and "Send with BCB" or "Get BCB")
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
        if BCB_OpenMultiline then BCB_OpenMultiline() end
        C_Timer.After(0.05, function()
            if BigChatBox.mlEditBox then
                BigChatBox.mlEditBox:SetText(str)
                BigChatBox.mlEditBox:SetFocus()
                BigChatBox.mlEditBox:SetCursorPosition(#str)
            end
        end)
    end)
    -- Tint BCB button to match current skin preset (or green in normal mode).
    -- Deferred one tick so template textures are initialized before tinting.
    C_Timer.After(0, function()
        local skinMode = BigNoteBoxDB and BigNoteBoxDB.skinMode
        if skinMode then
            BNB.TintButton(bcbShareBtn)
        else
            pcall(function()
                for _, region in ipairs({ bcbShareBtn:GetRegions() }) do
                    if region.IsObjectType and region:IsObjectType("Texture") then
                        region:SetVertexColor(0.30, 0.85, 0.35)
                    elseif region.IsObjectType and region:IsObjectType("FontString") then
                        region:SetTextColor(1, 1, 1)
                    end
                end
            end)
        end
    end)
    f._bcbShareBtn = bcbShareBtn
    f._refreshBCBShareBtn = RefreshBCBShareBtn

    -- Character counter (right-aligned, same row as copy/BCB buttons)
    local charCounter = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    charCounter:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
    charCounter:SetPoint("TOP",   copyBtn, "TOP", 0, 0)
    charCounter:SetTextColor(0.55, 0.55, 0.55)
    charCounter:SetText("0 chars")
    f._charCounter = charCounter

    shareEB:SetScript("OnTextChanged", function(self)
        local n = #(self:GetText() or "")
        local col = n > 2000 and "|cffff6666" or n > 800 and "|cffffff66" or "|cff888888"
        charCounter:SetText(col .. n .. " chars|r")
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

    local dsHdr = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dsHdr:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    dsHdr:SetTextColor(1, 0.82, 0)
    dsHdr:SetText(L["DS_SECTION_HEADER"])
    y = y - 22

    -- Target editbox (InputBoxTemplate for keyboard input on retail)
    local dsEbBg = BNB.CreateBackdropFrame("Frame", nil, f)
    BNB.SetBackdropDark(dsEbBg)
    dsEbBg:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, y)
    dsEbBg:SetWidth(CW - 70)
    dsEbBg:SetHeight(24)

    local dsEb = CreateFrame("EditBox", nil, dsEbBg, "InputBoxTemplate")
    dsEb:SetPoint("TOPLEFT",     dsEbBg, "TOPLEFT",      4,  -2)
    dsEb:SetPoint("BOTTOMRIGHT", dsEbBg, "BOTTOMRIGHT", -4,   2)
    dsEb:SetFontObject("GameFontNormalSmall")
    dsEb:SetAutoFocus(false)
    dsEb:SetMaxLetters(80)
    BNB.AddPlaceholder(dsEb, L["DS_TARGET_PLACEHOLDER"], 0.45, 0.45, 0.45)
    dsEb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f._dsEb = dsEb

    -- Send button
    local dsSendBtn = BNB.CreateButton(nil, f, L["DS_SEND_BUTTON"], 60, 24)
    dsSendBtn:SetPoint("LEFT", dsEbBg, "RIGHT", 6, 0)
    f._dsSendBtn = dsSendBtn

    -- Status label (success / error feedback, cleared on next OpenShareWindow)
    local dsStatus = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dsStatus:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, y - 28)
    dsStatus:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y - 28)
    dsStatus:SetJustifyH("LEFT")
    dsStatus:SetWordWrap(true)
    dsStatus:SetHeight(18)
    dsStatus:SetText("")
    f._dsStatus = dsStatus

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
                local nl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                nl:SetPoint("LEFT",  row, "LEFT",  4, 0)
                nl:SetPoint("RIGHT", row, "RIGHT", -80, 0)
                nl:SetJustifyH("LEFT"); nl:SetMaxLines(1); nl:SetTextColor(1, 1, 1)
                row._nameLbl = nl
                local cl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
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
            BNB.DS.SendNote(_shareNoteID, _selOption, target, function(chunks)
                if f._dsStatus and f:IsShown() then
                    f._dsStatus:SetTextColor(0.40, 0.85, 0.45)
                    f._dsStatus:SetText(string.format(L["DS_STATUS_SENT"], target, chunks))
                end
            end, function(err)
                if f._dsStatus and f:IsShown() then
                    f._dsStatus:SetTextColor(1, 0.35, 0.35)
                    f._dsStatus:SetText(err or L["DS_ERR_GENERIC"])
                end
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
    local importHdr = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    importHdr:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    importHdr:SetTextColor(1, 0.82, 0)
    importHdr:SetText("Import")
    y = y - 20

    local importLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    importLbl:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    importLbl:SetTextColor(0.78, 0.78, 0.78)
    importLbl:SetText("Paste a share string from another player:")
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
    importEB:SetFontObject("GameFontNormalSmall")
    importEB:SetMultiLine(false)
    importEB:SetAutoFocus(false)
    importEB:SetMaxLetters(0)
    importEB:SetTextInsets(2, 2, 2, 2)
    BNB.AddPlaceholder(importEB, "Paste BNB share string here...", 0.4, 0.4, 0.4)
    importEB:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f._importEB = importEB
    y = y - 58

    -- Error label
    local errLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    errLbl:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, y)
    errLbl:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
    errLbl:SetJustifyH("LEFT"); errLbl:SetWordWrap(true); errLbl:SetHeight(18)
    errLbl:SetTextColor(1, 0.35, 0.35)
    errLbl:SetText("")
    f._errLbl = errLbl
    y = y - 22

    -- Preview button
    local previewBtn = BNB.CreateButton(nil, f, "Preview", 90, 26)
    previewBtn:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    previewBtn:SetScript("OnClick", function()
        if f._errLbl then f._errLbl:SetText("") end
        local str = f._importEB and not f._importEB._showingPlaceholder
            and f._importEB:GetText() or ""
        if str == "" then
            if f._errLbl then f._errLbl:SetText("Please paste a share string first.") end
            return
        end
        local data, err = BNB.ShareDecode(str)
        if not data then
            if f._errLbl then f._errLbl:SetText(err or "Invalid share string.") end
            return
        end
        BNB.OpenSharePreview(data)
    end)
    y = y - 36

    -- Resize window to fit content
    f:SetHeight(math.abs(y) + PAD)

    f:EnableKeyboard(true)
    f:SetScript("OnKeyDown", function(self, key)
        -- Propagate non-ESCAPE keys so they can reach focused editboxes below
        -- (e.g. the BNB clipboard helper editbox for Ctrl+C). HIGH strata +
        -- SetToplevel + EnableKeyboard otherwise swallows all keys here.
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            -- Preview closes first if open, then the share window
            local spv = _previewFrame
            if spv and spv:IsShown() then BNB.CloseSharePreview(); return end
            BNB.CloseShareWindow()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    f:Hide()
    _shareFrame = f
    return f
end

function BNB.OpenShareWindow(noteID)
    if InCombatLockdown() then BNB:Print(L["COMBAT_BLOCKED"]); return end

    _shareNoteID = noteID
    _selOption   = "basic"

    local f = BuildShareWindow()

    -- Reset dropdown to default
    if f._shareDD and f._rebuildDD then f._rebuildDD() end
    if f._shareCycleBtn then
        f._shareCycleBtn:SetText(SHARE_OPTIONS[1].label)
    end
    -- Reset import field
    if f._importEB then
        f._importEB:SetText("")
        BNB.AddPlaceholder(f._importEB, "Paste BNB share string here...", 0.4, 0.4, 0.4)
    end
    if f._errLbl then f._errLbl:SetText("") end

    -- Generate initial share string
    if noteID then
        local str = BNB.ShareEncode(noteID, _selOption)
        if str and f._shareEB then f._shareEB:SetText(str) end
    else
        if f._shareEB then f._shareEB:SetText("") end
    end

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
-- Opened from the topbar tp-share button. Shows only the import section so
-- users can add a shared note without having to select one of their own first.
-- Reuses OpenSharePreview / CloseSharePreview for the preview flow.
--------------------------------------------------------------------------------
local IMPORT_W = 420
local SK_IMPORT_TITLE_H = 28

local function BuildImportWindowSkin()
    local f = BNB.CreateSkinFrame(UIParent, false, "BNBImportFrame", false)
    _G["BNBImportFrame"] = f
    f:SetSize(IMPORT_W, 220)
    f:SetFrameStrata("HIGH"); f:SetToplevel(true)
    f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)

    local titleBar = BNB.CreateSkinStrip(f, true, false)
    titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    titleBar:SetHeight(SK_IMPORT_TITLE_H)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
    titleBar:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

    local titleLbl = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleLbl:SetPoint("CENTER", titleBar, "CENTER", -12, 0)
    titleLbl:SetTextColor(1, 0.82, 0)
    titleLbl:SetText("Import Shared Note")

    local closeBtn = BNB.CreateSkinCloseButton(titleBar, function() BNB.CloseImportWindow() end)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -3, 0)

    f:SetScript("OnShow", function()
        if BNB.ApplyMainWindowSkin then BNB.ApplyMainWindowSkin() end
    end)
    return f, SK_IMPORT_TITLE_H
end

local function BuildImportWindowNormal()
    local f = CreateFrame("Frame", "BNBImportFrame", UIParent, "ButtonFrameTemplate")
    f:SetSize(IMPORT_W, 220)
    f:SetFrameStrata("HIGH"); f:SetToplevel(true)
    f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    ButtonFrameTemplate_HidePortrait(f)
    ButtonFrameTemplate_HideButtonBar(f)
    if f.Inset then f.Inset:Hide() end
    f:SetTitle("Import Shared Note")
    if f.CloseButton then
        f.CloseButton:SetScript("OnClick", function() BNB.CloseImportWindow() end)
    end
    return f, 32
end

local function BuildImportWindow()
    if _importFrame then return _importFrame end

    local skinMode = BigNoteBoxDB and BigNoteBoxDB.skinMode
    local f, titleH
    if skinMode then
        f, titleH = BuildImportWindowSkin()
    else
        f, titleH = BuildImportWindowNormal()
    end
    -- ESC chain: preview closes before import window (handled in MainWindow ESC block)

    local y   = -(titleH + 10)
    local CW  = IMPORT_W - PAD * 2

    local instrLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    instrLbl:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, y)
    instrLbl:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
    instrLbl:SetJustifyH("LEFT")
    instrLbl:SetTextColor(0.78, 0.78, 0.78)
    instrLbl:SetText("Paste a share string from another player:")
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
    importEB:SetFontObject("GameFontNormalSmall")
    importEB:SetMultiLine(false)
    importEB:SetAutoFocus(false)
    importEB:SetMaxLetters(0)
    importEB:SetTextInsets(2, 2, 2, 2)
    BNB.AddPlaceholder(importEB, "Paste BNB share string here...", 0.4, 0.4, 0.4)
    importEB:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f._importEB = importEB
    y = y - 58

    -- Error label
    local errLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    errLbl:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, y)
    errLbl:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
    errLbl:SetJustifyH("LEFT"); errLbl:SetWordWrap(true); errLbl:SetHeight(18)
    errLbl:SetTextColor(1, 0.35, 0.35)
    errLbl:SetText("")
    f._errLbl = errLbl
    y = y - 22

    -- Preview button
    local previewBtn = BNB.CreateButton(nil, f, "Preview", 90, 26)
    previewBtn:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    previewBtn:SetScript("OnClick", function()
        if f._errLbl then f._errLbl:SetText("") end
        local str = f._importEB and not f._importEB._showingPlaceholder
            and f._importEB:GetText() or ""
        if str == "" then
            if f._errLbl then f._errLbl:SetText("Please paste a share string first.") end
            return
        end
        local data, err = BNB.ShareDecode(str)
        if not data then
            if f._errLbl then f._errLbl:SetText(err or "Invalid share string.") end
            return
        end
        BNB.OpenSharePreview(data)
    end)

    -- Character counter right of preview button
    local impCharCounter = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    impCharCounter:SetPoint("LEFT",  previewBtn, "RIGHT", 8, 0)
    impCharCounter:SetPoint("RIGHT", f,           "RIGHT", -PAD, 0)
    impCharCounter:SetJustifyH("LEFT")
    impCharCounter:SetTextColor(0.55, 0.55, 0.55)
    impCharCounter:SetText("0 chars")
    f._importEB:SetScript("OnTextChanged", function(self)
        if self._showingPlaceholder then impCharCounter:SetText("0 chars"); return end
        local n = #(self:GetText() or "")
        local col = n > 0 and "|cff888888" or "|cff555555"
        impCharCounter:SetText(col .. n .. " chars|r")
    end)

    y = y - 36

    f:SetHeight(math.abs(y) + PAD)
    f:EnableKeyboard(true)
    f:SetScript("OnKeyDown", function(self, key)
        -- Propagate non-ESCAPE keys so they can reach focused editboxes below
        -- (e.g. the BNB clipboard helper editbox for Ctrl+C). HIGH strata +
        -- SetToplevel + EnableKeyboard otherwise swallows all keys here.
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            local spv = _previewFrame
            if spv and spv:IsShown() then BNB.CloseSharePreview(); return end
            BNB.CloseImportWindow()
        else
            self:SetPropagateKeyboardInput(true)
        end
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
        BNB.AddPlaceholder(f._importEB, "Paste BNB share string here...", 0.4, 0.4, 0.4)
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

--------------------------------------------------------------------------------
-- DIRECT SEND INTERNALS EXPOSED
-- DirectSend.lua uses BNB's own Serialize/Deserialize for the BNB2 wire format.
-- These are the same functions used by ShareEncode/ShareDecode above; exposed
-- here so DirectSend.lua (loaded after this file) can reference them without
-- duplicating the implementation.
--------------------------------------------------------------------------------
BNB.DS_Serialize         = Serialize
BNB.DS_Deserialize       = Deserialize
BNB.DS_SHARE_FIELDS      = SHARE_FIELDS
BNB.DS_EncodeAttachments = EncodeAttachments
BNB.DS_DecodeAttachments = DecodeAttachments

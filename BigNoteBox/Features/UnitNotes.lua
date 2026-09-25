-- BigNoteBox Features/UnitNotes.lua
-- Shared pieces of the two features that make a note from a unit: InspectNote
-- (players, from the Inspect frame) and TargetNote (NPCs, keybind and unit
-- menu). The note bodies and the duplicate lookups stay in each feature, since
-- they read different data and different keys (ALL-65.7).
--
-- Public API (BNB.UnitNotes):
--   Dialog(globalName, w, h, title)          small skin-aware dialog, hidden
--   TypeDialog(globalName, title, glowKey)   Normal / Rich; dlg:Open(onPick)
--   WarnDialog(globalName, w, h, rowY, dupeW) "note exists"; dlg:Open(...)
--   OpenNote(noteID)                         main window, note selected
--   FindPlayerNote(name, realm)              existing note for a player
--   UniqueTitle(baseName)                    "Name (Duplicate)" when taken
--   FormatNumber(n)                          client thousands separator
--------------------------------------------------------------------------------

local BNB = BigNoteBox
local L   = BNB.L

BNB.UnitNotes = BNB.UnitNotes or {}
local UN = BNB.UnitNotes

--------------------------------------------------------------------------------
-- DIALOG FRAME
-- Skin mode decides the chrome once, when the dialog is first built.
--------------------------------------------------------------------------------
function UN.Dialog(globalName, w, h, title)
    local skin = BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.CreateSkinFrame
    local f
    if skin then
        f = BNB.CreateSkinFrame(UIParent, false, globalName, false)
        _G[globalName] = f
    else
        f = CreateFrame("Frame", globalName, UIParent, "BasicFrameTemplateWithInset")
        f.TitleText:SetText(title)
    end
    f:SetSize(w, h)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true); f:EnableMouse(true); f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)

    if skin then
        local tb = BNB.CreateSkinStrip(f, true, false)
        tb:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
        tb:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
        tb:SetHeight(26)
        tb:EnableMouse(true); tb:RegisterForDrag("LeftButton")
        tb:SetScript("OnDragStart", function() f:StartMoving() end)
        tb:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

        local tl = tb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        tl:SetPoint("CENTER", tb, "CENTER", -12, 0)
        tl:SetTextColor(1, 0.82, 0); tl:SetText(title)

        BNB.CreateSkinCloseButton(tb, function() f:Hide() end)
            :SetPoint("RIGHT", tb, "RIGHT", -3, 0)

        f:SetScript("OnShow", function()
            if BNB.ApplyMainWindowSkin then BNB.ApplyMainWindowSkin() end
        end)
    end

    f:Hide()
    tinsert(UISpecialFrames, globalName)
    return f
end

--------------------------------------------------------------------------------
-- TYPE DIALOG: "Normal" or "Rich"
-- dlg:Open(onPick) shows it; a click hides it, then calls onPick(richMode).
-- onPick is set on every Open, so it sees the caller's current data.
--------------------------------------------------------------------------------
function UN.TypeDialog(globalName, title, glowKey)
    local f = UN.Dialog(globalName, 220, 100, title)

    local function Pick(richMode)
        f:Hide()
        if f._onPick then f._onPick(richMode) end
    end

    local nb = BNB.CreateButton(nil, f, L["SW_MODE_NORMAL"], 85, 28)
    nb:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 14)
    nb:SetScript("OnClick", function() Pick(false) end)

    local rb = BNB.CreateButton(nil, f, L["INS_RICH_BTN"], 85, 28)
    rb:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 14)
    rb:SetScript("OnClick", function() Pick(true) end)

    f:HookScript("OnHide", function(self)
        if BNB.StopWindowGlow then BNB.StopWindowGlow(self, glowKey) end
    end)

    function f:Open(onPick)
        self._onPick = onPick
        self:Show()
        if BNB.StartWindowGlow then BNB.StartWindowGlow(self, glowKey, BNB.BasicFrameGlowPad()) end
    end
    return f
end

--------------------------------------------------------------------------------
-- WARNING DIALOG: "You already have a note for [Name]"
-- Open Note | Create Duplicate | Close in one row, rowY up from the bottom.
-- A feature with more buttons adds them to the returned frame.
-- dlg:Open(name, noteID, onDuplicate) sets the text and wires the buttons.
--------------------------------------------------------------------------------
function UN.WarnDialog(globalName, w, h, rowY, dupeW)
    local f = UN.Dialog(globalName, w, h, L["INS_NOTE_EXISTS"])

    local msg = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    msg:SetPoint("TOP",   f, "TOP",   0,   -38)
    msg:SetPoint("LEFT",  f, "LEFT",  16,  0)
    msg:SetPoint("RIGHT", f, "RIGHT", -16, 0)
    msg:SetJustifyH("CENTER"); msg:SetWordWrap(true)
    f._msgLbl = msg

    f._openBtn = BNB.CreateButton(nil, f, L["AO_OPEN_NOTE_BTN"], 90, 26)
    f._openBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, rowY)

    f._dupeBtn = BNB.CreateButton(nil, f, L["INS_WARN_DUPLICATE"], dupeW, 26)
    f._dupeBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, rowY)

    local closeBtn = BNB.CreateButton(nil, f, L["CLOSE"], 70, 26)
    closeBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, rowY)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    function f:Open(name, noteID, onDuplicate)
        self._msgLbl:SetText(string.format(L["INS_WARN_EXISTS_FMT"], name))
        self._openBtn:SetScript("OnClick", function()
            self:Hide()
            UN.OpenNote(noteID)
        end)
        self._dupeBtn:SetScript("OnClick", function()
            self:Hide()
            if onDuplicate then onDuplicate() end
        end)
        self:Show()
    end
    return f
end

--------------------------------------------------------------------------------
-- NOTE HELPERS
--------------------------------------------------------------------------------
function UN.OpenNote(noteID)
    if BNB.OpenMainWindow then BNB.OpenMainWindow() end
    if BNB.SelectNote then
        if BNB.SaveCurrentNote then BNB.SaveCurrentNote() end
        BNB.SelectNote(noteID)
    end
    if BNB.RefreshNoteList then BNB.RefreshNoteList() end
end

-- An existing note for a player. Returns noteID or nil.
-- Matches the player context, or an inspect note's inspectName/inspectRealm
-- (the same test as NoteList and ReferenceBox). The context is only saved when
-- inspectNoteAddSituation is on (default off), so on its own it missed every
-- note made with default settings: no warning, and auto mode made a new
-- "(Duplicate)" note on every inspect.
function UN.FindPlayerNote(playerName, realm)
    local ndb = BigNoteBoxNotesDB
    if not ndb or not ndb.notes or not playerName then return nil end
    local ctx = "player:" .. playerName
    if realm and realm ~= "" then ctx = ctx .. "-" .. realm end
    for id, note in pairs(ndb.notes) do
        if note.context == ctx then return id end
        if note.source == "inspect" and note.inspectName == playerName
           and (not note.inspectRealm or note.inspectRealm == "" or note.inspectRealm == realm) then
            return id
        end
    end
    return nil
end

local function TitleTaken(ndb, title)
    for _, note in pairs(ndb.notes) do
        if note.title == title then return true end
    end
    return false
end

-- baseName when free, else "Name (Duplicate)", "Name (Duplicate 2)", ...
function UN.UniqueTitle(baseName)
    local ndb = BigNoteBoxNotesDB
    if not ndb or not ndb.notes then return baseName end
    if not TitleTaken(ndb, baseName) then return baseName end
    for i = 1, 100 do
        local candidate
        if i == 1 then
            candidate = string.format(L["INSPECT_DUP_FMT"], baseName)
        else
            candidate = string.format(L["INSPECT_DUP_N_FMT"], baseName, tostring(i))
        end
        if not TitleTaken(ndb, candidate) then return candidate end
    end
    return string.format(L["INSPECT_DUP_N_FMT"], baseName, tostring(time()))
end

function UN.FormatNumber(n)
    if not n then return "?" end
    -- The client's own thousands separator (ALL-72)
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(math.floor(n)) end
    local s = tostring(math.floor(n))
    local pos, result = #s, ""
    while pos > 0 do
        local start = math.max(1, pos - 2)
        result = s:sub(start, pos) .. (result ~= "" and "," or "") .. result
        pos = start - 1
    end
    return result
end

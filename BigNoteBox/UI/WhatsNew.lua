-- BigNoteBox UI/WhatsNew.lua
--
-- "What's New?" window, opened from the version button in Settings > General
-- (and /bnb whatsnew). Since ALL-409 an update no longer opens it: the release
-- becomes a pinned patch note plus a toast (see "Patch note" below).
--
-- PUBLIC API:
--   BNB.WhatsNew.Open(showOverlay)   -- showOverlay: true = dimmer behind it, false = none
--   BNB.WhatsNew.Close()
--   BNB.WhatsNew.CheckAndShow(newInstall)  -- called on login; the patch note + toast if the version is new
--
-- DATA:
--   BNB.PATCH_NOTES  (defined in UI/WhatsNewData.lua)
--     .version  string  -- must match BNB.ADDON_VERSION to trigger auto-show
--     .entries  table   -- array, one per bullet. A plain string shows on every client;
--                          { forever = true, "text" } / { retail = true, "text" } shows on
--                          that client only (BNB.IsForever). A release with no lines for
--                          this client does not auto-show.
--
-- PERSISTENCE:
--   BigNoteBoxDB.lastSeenWhatsNewVersion  -- set to version on close (no longer read)
--   NotesDB().patchNote = { version, id, sum }  -- the patch note made for a version
--
-- WINDOW SIZING:
--   Width  : CFG_W (480px) -- same as ConfigWindow
--   Height : grows with content from WN_MIN_H (300px) up to mainFrame:GetHeight() cap
--   When content exceeds cap: scrollbar appears, window stays at cap height
--
-- CHROME:
--   Normal mode : ButtonFrameTemplate (matches ConfigWindow)
--   Skin mode   : BNB.CreateSkinFrame + BNB.CreateSkinStrip title bar
--
-- OVERLAY:
--   Cosmetic full-screen dimmer behind the window (auto-popup only).
--   EnableMouse(false) -- click-through; does not block game interaction.
--   Skin mode + focusOverlayUseSkinColor: tinted with skin preset colour.
--   Dismissed when window closes.

local BNB = BigNoteBox
local L   = BNB.L

BNB.WhatsNew = BNB.WhatsNew or {}
local WN = BNB.WhatsNew

-- ── Layout constants ──────────────────────────────────────────────────────────
local CFG_W       = 480     -- matches ConfigWindow
local WN_MIN_H    = 300     -- window grows from this minimum
local PAD         = 16
local TITLE_H_N   = 28      -- ButtonFrameTemplate title bar (normal mode)
local OK_BTN_H    = 44      -- height of the OK button
local OK_BTN_PAD  = 10      -- padding above and below OK button area
local ENTRY_PAD_X = 12      -- horizontal padding inside scroll area
local ENTRY_GAP   = 6       -- vertical gap between entries
local ENTRY_FONT_SIZE = 13  -- patch note entry font size in pixels (increase to fit fewer lines, decrease for more)
local BULLET      = "|cff66bb6a-|r "   -- BNB green bullet prefix

-- ── Module state ──────────────────────────────────────────────────────────────
local _frame    = nil   -- the window frame (built once, reused)
local _overlay  = nil   -- the cosmetic dimmer (built once, reused)

-- ── AutoCast glow (LibCustomGlow-1.0) ─────────────────────────────────────────
-- The LCG lookup, start/stop and the skin-tinted overlay colour check are
-- shared with FeatureList/SetupWizard/DangerZone/FocusEditor in
-- UI/GlowOverlay.lua (ALL-65.4). BNB.StartWindowGlow/StopWindowGlow are the
-- default (BNB-green) window glow; other windows (Report a bug, ALL-73;
-- note-type "add" dialog, ALL-71) call them directly with their own key.
local GLOW_KEY = "bnb_whatsnew"

local function StartGlow(f, key)
    BNB.StartWindowGlow(f, key or GLOW_KEY)
end

local function StopGlow(f, key)
    BNB.StopWindowGlow(f, key or GLOW_KEY)
end

-- ── Overlay ───────────────────────────────────────────────────────────────────
local _overlayColor = BNB.OverlayColor

local function GetOverlay()
    if _overlay then return _overlay end
    local ov = CreateFrame("Frame", nil, UIParent)
    ov:SetAllPoints()
    ov:SetFrameStrata("DIALOG")  -- window is also DIALOG; lower frame level keeps overlay behind
    ov:SetFrameLevel(1)
    ov:EnableMouse(false)       -- cosmetic only; clicks pass through
    local tex = ov:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints()
    tex:SetColorTexture(0, 0, 0, 1)
    ov._tex = tex
    ov:Hide()
    -- Re-tint when skin changes
    if BNB.RegisterSkinBackdrop then
        BNB.RegisterSkinBackdrop(function()
            if ov:IsShown() then
                local r, g, b = _overlayColor()
                ov._tex:SetColorTexture(r, g, b, 0.6)
            end
        end)
    end
    _overlay = ov
    return ov
end

local function ShowOverlay()
    local ov = GetOverlay()
    local r, g, b = _overlayColor()
    ov._tex:SetColorTexture(r, g, b, 0.6)
    ov:Show()
end

local function HideOverlay()
    if _overlay then _overlay:Hide() end
end

-- ── Height calculation ────────────────────────────────────────────────────────
local function GetMaxHeight()
    if BNB.mainFrame then
        local h = BNB.mainFrame:GetHeight()
        if h and h > 100 then return h end
    end
    -- Fallback: use ConfigWindow helper if available
    if BNB._GetConfigTargetHeight then
        return BNB._GetConfigTargetHeight()
    end
    return math.min(math.max(math.floor(UIParent:GetHeight() * 0.75), WN_MIN_H), 900)
end

-- ── Window chrome, both modes (CMP-02 S3) ─────────────────────────────────────
local function BuildFrame(onClose)
    local f = BNB.CreateToolWindow({
        name = "BigNoteBoxWhatsNewFrame", w = CFG_W, h = WN_MIN_H,   -- sized to the notes later
        title = string.format(L["WN_TITLE_FMT"], BNB.ADDON_VERSION or "?"),
        toplevel = true, escClose = true, onClose = onClose,
    })
    return f, f._isSkin and BNB.TOOL_SKIN_TITLE_H or TITLE_H_N
end

-- ── Build the window (once) ───────────────────────────────────────────────────
local function BuildWindow()
    local skinMode = BigNoteBoxDB and BigNoteBoxDB.skinMode and true or false

    -- Rebuild if skin mode changed since the frame was first created
    if _frame and _frame._builtSkin ~= skinMode then
        _frame:Hide()
        _frame:SetParent(nil)
        _frame = nil
    end

    if _frame then return _frame end

    local onClose = function() WN.Close() end

    local f, titleH = BuildFrame(onClose)

    -- Store titleH on frame for content positioning
    f._titleH = titleH

    -- ── OK button area — fixed at bottom, always visible ──────────────────────
    -- Anchored to the bottom of the frame BEFORE the scroll area so it's
    -- always accessible regardless of content length.
    local okArea = CreateFrame("Frame", nil, f)
    okArea:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  PAD,  PAD)
    okArea:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD)
    okArea:SetHeight(OK_BTN_H + OK_BTN_PAD)
    f._okArea = okArea

    local okBtn
    if skinMode then
        okBtn = BNB.CreateSkinButton(nil, okArea, BNB.RandomOkPhrase(), okArea:GetWidth() or (CFG_W - PAD * 2), OK_BTN_H, 16)
    else
        local tpl = "SharedButtonLargeTemplate"
        okBtn = CreateFrame("Button", nil, okArea, tpl)
        okBtn:SetSize(okArea:GetWidth() or (CFG_W - PAD * 2), OK_BTN_H)
        pcall(function() DynamicResizeButton_Resize(okBtn) end)
        okBtn:SetText(BNB.RandomOkPhrase())
        local bfs = okBtn:GetFontString()
        if bfs then pcall(function() bfs:SetFont(BNB.GetLocaleFont(), 16, "") end) end
    end
    okBtn:SetPoint("BOTTOM", okArea, "BOTTOM", 0, 0)
    f._okBtn = okBtn
    okBtn:SetScript("OnClick", onClose)

    -- The OK area width is not valid at build time (frame not laid out yet).
    -- Re-set it when the frame is shown so the button fills correctly.
    f:HookScript("OnShow", function()
        local w = okArea:GetWidth()
        if w and w > 0 then okBtn:SetWidth(w) end
    end)

    -- ── Scroll area — fills between title bar and OK area ─────────────────────
    local BOTTOM_CHROME = OK_BTN_H + OK_BTN_PAD * 2 + PAD

    local sf = BNB.CreateScrollFrame(nil, f)
    sf:SetPoint("TOPLEFT",     f,  "TOPLEFT",  PAD,  -(titleH + PAD))
    sf:SetPoint("BOTTOMRIGHT", f,  "BOTTOMRIGHT", -24, BOTTOM_CHROME)
    f._sf = sf

    local bar = sf.ScrollBar
    if bar then bar:SetAlpha(0) end

    local ct = CreateFrame("Frame", nil, sf)
    ct:SetWidth(CFG_W - PAD * 2 - 24)
    ct:SetHeight(1)
    sf:SetScrollChild(ct)
    f._ct = ct

    -- Scrollbar auto-show/hide
    sf:HookScript("OnSizeChanged", function()
        local sfH = sf:GetHeight()
        if sfH < 4 then return end
        local ctH = ct._contentH or 0
        ct:SetHeight(math.max(ctH, sfH))
        if bar then
            bar:SetAlpha(ctH > sfH + 2 and 1 or 0)
        end
    end)

    f:Hide()
    f._builtSkin = skinMode
    _frame = f
    return f
end

-- ── Entries for this client ──────────────────────────────────────────────────
-- Drops lines tagged for the other client and unwraps tagged ones to their text.
local function ClientEntries(entries)
    local out = {}
    for _, entry in ipairs(entries or {}) do
        if type(entry) == "string" then
            out[#out + 1] = entry
        elseif type(entry) == "table" and type(entry[1]) == "string" then
            local show
            if entry.forever then show = BNB.IsForever
            elseif entry.classic then show = BNB.IsClassic   -- ALL-168
            elseif entry.retail then show = not (BNB.IsForever or BNB.IsClassic)
            else show = true end
            if show then out[#out + 1] = entry[1] end
        end
    end
    return out
end

-- ── Populate entries into the scroll content frame ────────────────────────────
local function PopulateEntries(ct, entries)
    -- Clear old children
    for _, child in ipairs({ ct:GetRegions() }) do
        child:Hide()
        child:SetParent(nil)
    end

    local availW = ct:GetWidth() - ENTRY_PAD_X * 2
    local y = -PAD
    for _, entry in ipairs(entries or {}) do
        local fs = ct:CreateFontString(nil, "ARTWORK", "BNBFontNormalSmall")
        fs:SetFont("Fonts\\FRIZQT__.TTF", ENTRY_FONT_SIZE, "")
        fs:SetPoint("TOPLEFT", ct, "TOPLEFT", ENTRY_PAD_X, y)
        fs:SetWidth(availW)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true)
        fs:SetSpacing(2)
        fs:SetTextColor(0.88, 0.88, 0.88)
        fs:SetText(BULLET .. entry)
        local h = fs:GetStringHeight()
        if h < 14 then h = 14 end
        y = y - h - ENTRY_GAP
    end
    y = y - PAD

    local contentH = math.abs(y)
    ct._contentH = contentH
    return contentH
end

-- ── Size the window to fit content ───────────────────────────────────────────
local function ApplyWindowHeight(f, contentH)
    local maxH  = GetMaxHeight()
    local chrome = f._titleH + PAD + (OK_BTN_H + OK_BTN_PAD * 2 + PAD) + PAD
    local ideal  = contentH + chrome
    local final  = math.max(WN_MIN_H, math.min(ideal, maxH))
    f:SetSize(CFG_W, final)

    -- Update scroll child height and scrollbar visibility
    local sf  = f._sf
    local ct  = f._ct
    local bar = sf and sf.ScrollBar
    if sf and ct then
        local sfH = sf:GetHeight()
        if sfH < 4 then
            -- Not laid out yet; defer one tick
            C_Timer.After(0.05, function()
                sfH = sf:GetHeight()
                ct:SetHeight(math.max(contentH, sfH))
                if bar then
                    bar:SetAlpha(contentH > sfH + 2 and 1 or 0)
                end
            end)
        else
            ct:SetHeight(math.max(contentH, sfH))
            if bar then
                bar:SetAlpha(contentH > sfH + 2 and 1 or 0)
            end
        end
    end
end

-- ── Public: Open ─────────────────────────────────────────────────────────────
-- showOverlay: true  = auto-popup path (dimmer visible)
--              false = manual open from version button (no dimmer)
function WN.Open(showOverlay)
    local data = BNB.PATCH_NOTES
    if not data then return end

    local f = BuildWindow()

    -- Randomize OK button label on each open
    if f._okBtn then f._okBtn:SetText(BNB.RandomOkPhrase()) end

    -- Populate entries and measure
    local contentH = PopulateEntries(f._ct, ClientEntries(data.entries))

    -- Position CENTER before sizing so GetHeight() is valid when we check maxH
    f:ClearAllPoints()
    f:SetPoint("CENTER")

    ApplyWindowHeight(f, contentH)
    f:Show()
    f:Raise()
    StartGlow(f)

    -- Ensure overlay strata is just below the window
    if showOverlay then
        ShowOverlay()
        -- Pull overlay just below the window frame level
        local ov = GetOverlay()
        ov:SetFrameLevel(math.max(1, f:GetFrameLevel() - 1))
    else
        HideOverlay()
    end
end

-- ── Public: Close ─────────────────────────────────────────────────────────────
function WN.Close()
    HideOverlay()
    if _frame then
        StopGlow(_frame)
        _frame:Hide()
    end
    -- Mark this version as seen so it won't auto-show again
    local data = BNB.PATCH_NOTES
    if data and data.version and BigNoteBoxDB then
        BigNoteBoxDB.lastSeenWhatsNewVersion = data.version
    end
end

-- ── Patch note (ALL-409) ─────────────────────────────────────────────────────
-- An update no longer opens the window: the release's lines become a pinned,
-- favourite, Global note (rich while Rich Notes is on) tagged Bnb / V1.23.0 /
-- V1.23, plus a toast that waits for a click (source "patchnotes", so it
-- follows the Toasts module). The window stays on the version button.
--
-- Bookkeeping lives in the active notes set, so dev mode (its own notes DB)
-- gets its own note: NotesDB().patchNote = { version, id, sum }. sum is a
-- checksum of the title and body as written; the next version's note replaces
-- the old one only while that still matches and the Bnb tag is on it (the
-- player did not edit it or untag it). Pin / favourite do not count.
local PN_TAG    = "BNB"
local PN_GREEN  = "66bb6a"
local PN_ORDER  = { "New", "Change", "Fixed" }   -- other labels follow, as found
local PN_LABELS = { Changed = "Change" }          -- spellings WhatsNewData allows

local function PatchTags(version)
    local minor = version:match("^(%d+%.%d+)")
    local tags = { BNB.NormalizeTag(PN_TAG), BNB.NormalizeTag("v" .. version) }
    if minor and minor ~= version then tags[#tags + 1] = BNB.NormalizeTag("v" .. minor) end
    return tags
end

local function Checksum(note)
    local s = (note.title or "") .. "\n" .. (note.body or "")
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
    return h
end

local function HasTag(note, tag)
    for _, t in ipairs(note.tags or {}) do
        if t == tag then return true end
    end
    return false
end

-- "|cff66bb6aNew:|r text" -> "New", "text"; a line with no label -> "", line
local function SplitLabel(entry)
    local label, text = entry:match("^|c%x%x%x%x%x%x%x%x(%a+):|r%s*(.*)$")
    if not label then label, text = entry:match("^(%a+):%s+(.*)$") end
    if not label then return "", entry end
    return PN_LABELS[label] or label, text
end

-- Colour codes in a line: markup for a rich note, gone from a plain one.
-- Braces become parentheses first in a rich note, so text such as "{p}" in
-- a patch line is never read as a tag (a repair would change the body).
local function LineText(text, rich)
    if rich then
        text = text:gsub("{", "("):gsub("}", ")")
        text = text:gsub("|c%x%x(%x%x%x%x%x%x)", "{col:%1}"):gsub("|r", "{/col}")
    else
        text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    end
    return text
end

local function PatchBody(version, entries, rich)
    local groups, order = {}, {}
    for _, label in ipairs(PN_ORDER) do groups[label] = {} end
    for _, entry in ipairs(entries) do
        local label, text = SplitLabel(entry)
        if not groups[label] then groups[label] = {}; order[#order + 1] = label end
        table.insert(groups[label], text)
    end
    -- Unlabelled lines first, then New / Change / Fixed, then any other label
    local seq = {}
    if groups[""] then seq[1] = "" end
    for _, label in ipairs(PN_ORDER) do seq[#seq + 1] = label end
    for _, label in ipairs(order) do
        if label ~= "" then seq[#seq + 1] = label end
    end

    local heading = string.format(L["PN_NOTE_HEADING"], version)
    local out = { rich and ("{h1}" .. heading .. "{/h1}") or heading }
    for _, label in ipairs(seq) do
        local lines = groups[label]
        if #lines > 0 then
            if label ~= "" then
                if rich then
                    out[#out + 1] = "{h3}{col:" .. PN_GREEN .. "}" .. label .. "{/col}{/h3}"
                else
                    out[#out + 1] = ""
                    out[#out + 1] = label
                end
            elseif not rich then
                out[#out + 1] = ""
            end
            for _, text in ipairs(lines) do
                local bullet = rich and ("{col:" .. PN_GREEN .. "}-{/col} ") or "- "
                out[#out + 1] = bullet .. LineText(text, rich)
            end
        end
    end
    return table.concat(out, "\n")
end

-- The previous version's note goes, unless the player made it theirs
local function RemoveOldPatchNote(ndb)
    local pn = ndb.patchNote
    local old = pn and pn.id and ndb.notes and ndb.notes[pn.id]
    if not old then return end
    if not HasTag(old, BNB.NormalizeTag(PN_TAG)) then return end
    if Checksum(old) ~= pn.sum then return end
    BNB.DeleteNote(pn.id, true)
end

-- A note from BigNoteBox itself (patch note, welcome note): Global, pinned,
-- favourite, and made nowhere, so no creation spot
local function MakeAddonNote(title, body, rich, tags)
    local id = BNB.CreateNote(title, body)
    if not id then return nil end
    BNB.UpdateNote(id, {
        scope = "global", tags = tags,
        pinned = true, favorited = true, richMode = rich,
        _clear = { "coordX", "coordY", "coordMapID", "coordZone", "coordSubzone" },
    })
    return id
end

local function CreatePatchNote(version, entries)
    local rich = BNB.RichEnabled and BNB.RichEnabled() or false
    return MakeAddonNote(string.format(L["PN_NOTE_TITLE"], version),
        PatchBody(version, entries, rich), rich, PatchTags(version))
end

local function ShowPatchToast(version, id)
    if not (BNB.Toast and BNB.Toast.Show) then return end
    BNB.Toast.Show({
        key    = "patchnotes",
        source = "patchnotes",
        title  = L["PN_TOAST_TITLE"],
        text   = string.format(L["PN_TOAST_TEXT"], version),
        hold   = 0,   -- waits for a click
        onClick = function()
            if BNB.OpenNoteInMain and BNB.GetNote(id) then BNB.OpenNoteInMain(id) end
        end,
    })
end

-- ── Public: CheckAndShow ──────────────────────────────────────────────────────
-- Called on login after Initialize(). Once per version per notes set: makes
-- the patch note and shows its toast (ALL-409). newInstall = setup not done
-- yet: the version is only stamped, a new player gets no patch note for the
-- version they installed. The window opens from the version button only.
function WN.CheckAndShow(newInstall)
    local data = BNB.PATCH_NOTES
    if not data or not data.version then return end
    local ndb = BNB.NotesDB and BNB.NotesDB()
    if type(ndb) ~= "table" or type(ndb.notes) ~= "table" then return end
    local pn = ndb.patchNote
    if type(pn) == "table" and pn.version == data.version then return end
    if type(pn) ~= "table" then pn = {} end
    pn.version = data.version
    ndb.patchNote = pn
    if newInstall then return end
    -- Nothing for this client in this release (e.g. a Forever-only patch on
    -- Retail): the last patch note stays
    local entries = ClientEntries(data.entries)
    if #entries == 0 then return end
    RemoveOldPatchNote(ndb)
    local id = CreatePatchNote(data.version, entries)
    if not id then return end
    pn.id, pn.sum = id, Checksum(BNB.GetNote(id))
    ShowPatchToast(data.version, id)
end

-- ── Welcome note (ALL-242) ───────────────────────────────────────────────────
-- Dukul's note to a new player, made once on a fresh install: Horde, Alliance
-- or (a Pandaren before choosing) Neutral text, the Forever line on Forever
-- only. Rich: "BigNoteBox" in BNB green, the site names linked, greeting and
-- sign-off in the faction colour, "Dukul" in shaman blue. Plain (Rich Notes
-- off): the URLs written out in brackets after each site name.
local WELCOME_SHAMAN = "0070dd"
local WELCOME_FACTION = {
    Horde    = { col = "ff5040", greet = "WNOTE_GREET_HORDE",    bye = "WNOTE_BYE_HORDE" },
    Alliance = { col = "4da3ff", greet = "WNOTE_GREET_ALLIANCE", bye = "WNOTE_BYE_ALLIANCE" },
    Neutral  = { col = "d8b45a", greet = "WNOTE_GREET_NEUTRAL",  bye = "WNOTE_BYE_NEUTRAL" },
}

-- Every plain-text occurrence of find in s replaced by repl (no patterns:
-- "Wago.io" has a dot)
local function ReplacePlain(s, find, repl)
    local out, pos = {}, 1
    while true do
        local st, en = s:find(find, pos, true)
        if not st then break end
        out[#out + 1] = s:sub(pos, st - 1)
        out[#out + 1] = repl
        pos = en + 1
    end
    out[#out + 1] = s:sub(pos)
    return table.concat(out)
end

-- One paragraph: the site names linked (rich) or followed by their URL
-- (plain), "BigNoteBox" green (rich). Site names go through placeholders
-- first, so the green never lands inside a URL
local function WelcomeText(text, rich)
    if not rich then
        for _, site in ipairs(BNB.SITE_LINKS) do
            text = ReplacePlain(text, site.name, site.name .. " (" .. site.url .. ")")
        end
        return text
    end
    text = text:gsub("{", "("):gsub("}", ")")   -- a translation is never read as markup
    for i, site in ipairs(BNB.SITE_LINKS) do
        text = ReplacePlain(text, site.name, "@@SITE" .. i .. "@@")
    end
    text = ReplacePlain(text, "BigNoteBox", "{col:" .. PN_GREEN .. "}BigNoteBox{/col}")
    for i, site in ipairs(BNB.SITE_LINKS) do
        text = ReplacePlain(text, "@@SITE" .. i .. "@@", "{link*" .. site.url .. "*" .. site.name .. "}")
    end
    return text
end

local function WelcomeBody(faction, rich)
    local f = WELCOME_FACTION[faction] or WELCOME_FACTION.Neutral
    local paras = {
        L[BNB.IsForever and "WNOTE_P1_FOREVER" or "WNOTE_P1"],
        L["WNOTE_P2"],
        L["WNOTE_P3"],
    }
    local greet, bye = L[f.greet], L[f.bye]
    local out = {}
    if rich then
        out[1] = "{h2}{col:" .. f.col .. "}" .. WelcomeText(greet, true) .. "{/col}{/h2}"
        for _, p in ipairs(paras) do out[#out + 1] = WelcomeText(p, true) end
        out[#out + 1] = "{p:r}{col:" .. f.col .. "}" .. WelcomeText(bye, true) .. "{/col}{br}{col:"
            .. WELCOME_SHAMAN .. "}Dukul{/col}{/p}"
    else
        out[1] = greet
        for _, p in ipairs(paras) do
            out[#out + 1] = ""
            out[#out + 1] = WelcomeText(p, false)
        end
        out[#out + 1] = ""
        out[#out + 1] = bye
        out[#out + 1] = "Dukul"
    end
    return table.concat(out, "\n")
end

-- Called on login with CheckAndShow. Decided once per account (settings
-- flag welcomeNoteDone, kept out of DEFAULTS: nil = not decided yet): a
-- fresh install with no notes gets the note, an existing install only the
-- flag, so a deleted welcome note never comes back. force (Developer tools):
-- make it now, whatever the flag and the notes say.
function WN.CheckWelcome(newInstall, force)
    local db = BigNoteBoxDB
    if not db then return end
    local ndb = BNB.NotesDB and BNB.NotesDB()
    if type(ndb) ~= "table" or type(ndb.notes) ~= "table" then return end
    if not force then
        if db.welcomeNoteDone then return end
        db.welcomeNoteDone = true
        if not newInstall or next(ndb.notes) then return end
    end
    local rich = BNB.RichEnabled and BNB.RichEnabled() or false
    local faction = UnitFactionGroup("player")
    local id = MakeAddonNote(L["WNOTE_TITLE"], WelcomeBody(faction, rich), rich,
        { BNB.NormalizeTag(PN_TAG), BNB.NormalizeTag("Welcome") })
    if not id then return end
    db.welcomeToastPending = id
    WN.ShowWelcomeToast()
end

-- The welcome note's toast waits for the end of setup: the note is made at
-- the first login, under the wizard, and the toast shows once setup is done
-- (the wizard's Quit, or the login after Finish, which reloads). Pending =
-- BigNoteBoxDB.welcomeToastPending (the note id), cleared when it shows.
-- Waits for a click, as the patch note's does, and follows the same
-- toastSources switch ("Messages from BigNoteBox").
function WN.ShowWelcomeToast()
    local db = BigNoteBoxDB
    local id = db and db.welcomeToastPending
    if not id or db.setupComplete ~= true then return end
    db.welcomeToastPending = nil
    if not (BNB.GetNote(id) and BNB.Toast and BNB.Toast.Show) then return end
    BNB.Toast.Show({
        key    = "welcome",
        source = "patchnotes",
        title  = L["WNOTE_TITLE"],
        text   = L["WNOTE_TOAST_TEXT"],
        hold   = 0,
        onClick = function()
            if BNB.OpenNoteInMain and BNB.GetNote(id) then BNB.OpenNoteInMain(id) end
        end,
    })
end

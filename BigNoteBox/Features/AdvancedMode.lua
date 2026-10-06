-- BigNoteBox Features/AdvancedMode.lua
-- Rich note rendering: markup converter and SimpleHTML frame factory.
--
-- Public API (BNB.AdvancedMode):
--   AM.IsRich(note)                          -> bool
--   AM.ToHTML(text, bodySize)                -> html string
--   AM.CreateRenderFrame(name, parent)       -> SimpleHTML frame
--   AM.ApplyFontsToRenderFrame(f, bodySize)  -> wires font objects
--   AM.ConvertToPlain(id, onDone)            -> strips tags, confirms first
--   AM.GetUserImages()                       -> table of registered image paths
--   AM.UserImageShortName(full) / AM.ResolveUserImage(typed)  -> picker name / full path
--   BNB.RegisterUserImages(folder, names)    -> images from a player's own addon (SUG-09)

local BNB = BigNoteBox
BNB.AdvancedMode = BNB.AdvancedMode or {}
local AM = BNB.AdvancedMode

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------
local function HtmlEscape(s)
    -- Escape HTML special chars. We do this per-line BEFORE tag processing
    -- so that user-typed < > " don't break the HTML structure.
    s = s:gsub("&", "&amp;")
    s = s:gsub("<", "&lt;")
    s = s:gsub(">", "&gt;")
    s = s:gsub("\"", "&quot;")
    return s
end

-- Structure tags: {h1}{/h1} {h2}{/h2} {h3}{/h3} {p}{/p} and alignment variants
local STRUCT_OPEN = {
    ["{h1}"]   = "<h1>",
    ["{h1:c}"] = "<h1 align=\"center\">",
    ["{h1:r}"] = "<h1 align=\"right\">",
    ["{h2}"]   = "<h2>",
    ["{h2:c}"] = "<h2 align=\"center\">",
    ["{h2:r}"] = "<h2 align=\"right\">",
    ["{h3}"]   = "<h3>",
    ["{h3:c}"] = "<h3 align=\"center\">",
    ["{h3:r}"] = "<h3 align=\"right\">",
    ["{p}"]    = "<P>",
    ["{p:c}"]  = "<P align=\"center\">",
    ["{p:r}"]  = "<P align=\"right\">",
}
local STRUCT_CLOSE = {
    ["{/h1}"] = "</h1>",
    ["{/h2}"] = "</h2>",
    ["{/h3}"] = "</h3>",
    ["{/p}"]  = "</P>",
}

-- The closing html for each open tag's block, so a block is always closed with
-- its own tag, whatever the player typed ({h1}...{/p} closes the h1)
local STRUCT_END = {}
for tag, html in pairs(STRUCT_OPEN) do
    STRUCT_END[tag] = "</" .. html:match("^<(%w+)") .. ">"
end

-- Body-level text must sit inside a block element: a bare text node between
-- blocks makes SimpleHTML drop the whole document (ALL-236: "{p}a{/p}b" on one
-- line lost everything). Wraps the text around any <P ...>...</P> (an aligned
-- icon) or <img .../> already in s. keepBlank: a line that is only spaces
-- still makes an empty paragraph, as before; gaps between tags do not.
local function WrapBare(s, keepBlank)
    local out, pos = {}, 1
    local function text(t)
        if t ~= "" and (keepBlank or t:find("%S")) then
            out[#out + 1] = "<P>" .. t .. "</P>"
        end
    end
    while true do
        local ps = s:find("<P", pos, true)
        local is = s:find("<img ", pos, true)
        local st = ps and (not is or ps < is) and ps or is
        if not st then break end
        local _, en
        if st == ps then _, en = s:find("</P>", st, true)
        else _, en = s:find("/>", st, true) end
        if not en then break end
        text(s:sub(pos, st - 1))
        out[#out + 1] = s:sub(st, en)
        pos = en + 1
    end
    text(s:sub(pos))
    return table.concat(out)
end

--------------------------------------------------------------------------------
-- MAIN CONVERTER: AM.ToHTML(text, bodySize)
-- Converts BNB rich-note markup to WoW SimpleHTML format.
-- Processing order matters — img must run before struct tags (img closes/reopens P).
--------------------------------------------------------------------------------
function AM.ToHTML(text, bodySize)
    if not text or text == "" then return "" end

    local lines = {}
    -- Split on newlines
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        table.insert(lines, line)
    end

    local out = {}
    local openEnd = nil  -- closing html of the open {h*} / {p} block, nil = none

    for _, rawLine in ipairs(lines) do
        local line = HtmlEscape(rawLine)

        -- 1. {img:path:width:height[:align]} — standalone block-level element.
        --    Replace the ENTIRE line with just the <img> tag so the bare-line
        --    wrapper (step 7) sees a line starting with "<" and leaves it alone.
        --    Previous approach wrapped with </P>...<P> which created orphaned /
        --    unclosed <P> tags when the img was not inside a {p} block, killing
        --    the SimpleHTML parser for the whole document.
        line = line:gsub("{img:([^:}]+):([^:}]+):([^:}]+):?([^:}]*)}", function(src, w, h, align)
            local a = align ~= "" and align or "center"
            -- map single-char align
            if a == "c" then a = "center"
            elseif a == "l" then a = "left"
            elseif a == "r" then a = "right" end
            w = math.abs(tonumber(w) or 128)
            h = math.abs(tonumber(h) or 128)
            return string.format("<img src=\"%s\" width=\"%d\" height=\"%d\" align=\"%s\"/>",
                src, w, h, a)
        end)

        -- 2. {icon:name:size} or {icon:name:size:l/c/r} -> texture tag with optional alignment
        -- Alignment variants wrap the icon in a <P align=...> block.
        -- Inline (no suffix): emitted as a raw |T...|t code inside the current line.
        -- Numeric names (fileIDs from GetItemIcon etc.) are passed directly to |T|t
        -- without the Interface\ICONS\ prefix — WoW resolves them natively.
        local function iconTex(name, size)
            size = tonumber(size) or 25
            if name:match("^%d+$") then
                return string.format("|T%s:%d:%d|t", name, size, size)
            end
            return string.format("|TInterface\\ICONS\\%s:%d:%d|t", name, size, size)
        end
        line = line:gsub("{icon:([^:}]+):(%d+):([lcr])}", function(name, size, align)
            local tex = iconTex(name, size)
            local alignStr = (align == "c") and "center" or (align == "r") and "right" or "left"
            -- Alignment block: wrap in its own <P> so SimpleHTML honours the alignment.
            -- We signal to the bare-line wrapper (step 7) that this line is already
            -- a block element by prefixing it with a sentinel it will skip.
            return string.format("<P align=\"%s\">%s</P>", alignStr, tex)
        end)
        line = line:gsub("{icon:([^:}]+):(%d+)}", function(name, size)
            return iconTex(name, size)
        end)

        -- 3. {col:rrggbb}...{/col} -> WoW color codes
        line = line:gsub("{col:(%x%x%x%x%x%x)}", function(hex)
            return "|cff" .. hex
        end)
        line = line:gsub("{/col}", "|r")

        -- 4. {link*url*text} -> <a href="url"> with BNB green colour baked in.
        -- SimpleHTML has no API to set <a> tag colour at runtime, so we wrap
        -- the visible text in a WoW colour code (BNB green: 0.40, 0.85, 0.40
        -- = #66d966) so links stand out from body text without underline support.
        line = line:gsub("{link%*([^*}]+)%*([^}]*)}", function(url, linkText)
            if linkText == "" then linkText = url end
            return string.format("<a href=\"%s\">|cff66d966%s|r</a>", url, linkText)
        end)

        -- 5. {br} -> <BR/> — inline line break with no paragraph margin
        line = line:gsub("{br}", "<BR/>")

        -- 6-8. Structure tags, left to right, so the result is always well
        --      formed (ALL-236). An open tag while a block is open closes that
        --      block first (SimpleHTML cannot nest them); a close tag closes
        --      the open block with its own tag; a stray close tag is dropped.
        --      Text outside a block becomes its own <P> (WrapBare); text inside
        --      one is kept as it is. A block left open runs on to the next
        --      lines and is closed at the end of the note at the latest.
        -- hadTag: a line with tags drops blank gaps between them (WrapBare).
        -- carried: this line continues a block opened on an earlier line, so
        -- its first text starts on a new line (<BR/>), as typed: the lines of
        -- a multi-line block used to run together with no break or space.
        local parts, pos, scan, hadTag = {}, 1, 1, false
        local carried = openEnd ~= nil
        local function emit(t)
            if t == "" then return end
            if openEnd then
                if carried then parts[#parts + 1] = "<BR/>" end
                parts[#parts + 1] = t
            else
                parts[#parts + 1] = WrapBare(t, not hadTag)
            end
            carried = false
        end
        while true do
            local st, en = line:find("{/?[hp]%d?:?[cr]?}", scan)
            if not st then break end
            local tag = line:sub(st, en)
            if STRUCT_OPEN[tag] or STRUCT_CLOSE[tag] then   -- else plain text
                hadTag = true
                emit(line:sub(pos, st - 1))
                carried = false
                if openEnd then parts[#parts + 1] = openEnd; openEnd = nil end
                if STRUCT_OPEN[tag] then
                    parts[#parts + 1] = STRUCT_OPEN[tag]
                    openEnd = STRUCT_END[tag]
                end
                pos = en + 1
            end
            scan = en + 1
        end
        emit(line:sub(pos))
        -- An empty line inside a block is a blank line there
        if carried and line == "" then parts[1] = "<BR/>" end
        line = table.concat(parts)

        -- 9. Spacer after block closes for visual breathing room.
        --    WoW SimpleHTML has no CSS margins; inject a <P><br/></P> after
        --    heading and paragraph closes to separate sections visually.
        --    These spacers only affect SimpleHTML rendering (view mode / rich
        --    preview); they do not impact editbox cursor positioning.
        --    Empty <P></P> tags are dropped — they add no visual output.
        if line == "<P></P>" then
            line = ""
        elseif line:match("</h%d>$") or line:match("</P>$") then
            line = line .. "<P><br/></P>"
        end

        table.insert(out, line)
    end
    if openEnd then
        -- Never closed: close it, so the text in it still shows (ALL-236)
        table.insert(out, openEnd .. "<P><br/></P>")
    end

    -- SimpleHTML requires a complete <HTML><BODY>...</BODY></HTML> document.
    -- Join WITHOUT newlines — WoW's SimpleHTML parser treats newlines between
    -- block elements as orphan text nodes, which causes the parser to fall back
    -- to plain-text rendering for the entire document.
    return "<HTML><BODY>" .. table.concat(out) .. "</BODY></HTML>"
end

--------------------------------------------------------------------------------
-- FONT OBJECTS
-- Shared by every render frame (PERF-03): an object is fully set by its key
-- (tag, font file, pixel size, flags), so frames that want the same font get
-- the same object, and no frame ever changes one another frame uses. They were
-- named per frame, which made four new global font objects (more with an
-- outline) for every sticky ever opened.
-- Must be deferred: called after PLAYER_LOGIN via AM.ApplyFontsToRenderFrame.
--------------------------------------------------------------------------------
local _fontObjs = {}  -- cache: key = "tag|path|px|flags"
local _fontCount = 0
local FONT_RESET_SECS = 15   -- how long a new object is set again per use (ALL-16)

-- Resolve note.fontOutline to a SetFont flag string.
-- Handles SLUG, SLUG Outline, and SLUG Thick Outline as first-class options.
function AM.OutlineFlagStr(fontOutline)
    local o = fontOutline or "None"
    if     o == "Outline"            then return "OUTLINE"
    elseif o == "Thick Outline"      then return "THICKOUTLINE"
    elseif o == "Monochrome Outline" then return "MONOCHROME,OUTLINE"
    elseif o == "SLUG"               then return "SLUG"
    elseif o == "SLUG Outline"       then return "OUTLINE, SLUG"
    elseif o == "SLUG Thick Outline" then return "THICKOUTLINE, SLUG"
    end
    return ""  -- None or any drop shadow variant
end

-- Display label for a stored fontOutline value. The stored value stays English on
-- purpose: it is compared as a key everywhere and travels between locales in shared
-- notes, so only what the dropdown shows is translated. Unknown values pass through.
local OUTLINE_LABEL_KEYS = {
    ["None"]                  = "OUTLINE_NONE",
    ["Outline"]               = "OUTLINE_OUTLINE",
    ["Thick Outline"]         = "OUTLINE_THICK",
    ["Monochrome Outline"]    = "OUTLINE_MONO",
    ["SLUG"]                  = "OUTLINE_SLUG",
    ["SLUG Outline"]          = "OUTLINE_SLUG_OUTLINE",
    ["SLUG Thick Outline"]    = "OUTLINE_SLUG_THICK",
    ["Drop Shadow"]           = "OUTLINE_SHADOW",
    ["Strong Drop Shadow"]    = "OUTLINE_SHADOW_STRONG",
    ["Strongest Drop Shadow"] = "OUTLINE_SHADOW_STRONGEST",
}
function AM.OutlineLabel(fontOutline)
    local o = fontOutline or "None"
    local key = OUTLINE_LABEL_KEYS[o]
    return (key and BNB.L and BNB.L[key]) or o
end

local function GetOrCreateFontObj(tag, path, size, flags)
    local px
    if path and path ~= "" then
        size = BNB.FontPx and BNB.FontPx(path, size) or size   -- per-font factor (ALL-60)
        px = math.max(math.floor(size + 0.5), 6)
    end
    local cacheKey = tag .. "|" .. (path or "") .. "|" .. (px or "") .. "|" .. flags
    local fo = _fontObjs[cacheKey]
    if not fo then
        -- Numbered names: one global per distinct font, never per frame
        _fontCount = _fontCount + 1
        fo = CreateFont("BNBRichFont" .. _fontCount)
        _fontObjs[cacheKey] = fo
        fo._bnbSetUntil = GetTime() + FONT_RESET_SECS
    end
    -- Set again only while the object is new: a bundled TTF that was not
    -- loaded yet on a cold login draws blank until it is set again (ALL-16).
    -- After that never: every SetFont makes the client walk all text using the
    -- object, and SimpleHTML frees its lines on each render. Setting it on every
    -- render is the lead for the Forever crashes (FOR-30, use-after-free in a walk).
    if px and GetTime() <= fo._bnbSetUntil then
        pcall(fo.SetFont, fo, path, px, flags)
    end
    return fo
end

-- Binds a tag's font object only when it changed for this frame (FOR-30)
local function SetTagFont(f, tag, fo)
    f._bnbTagFonts = f._bnbTagFonts or {}
    if f._bnbTagFonts[tag] == fo then return end
    f._bnbTagFonts[tag] = fo
    f:SetFontObject(tag, fo)
end

-- flagStr (optional): pass AM.OutlineFlagStr(note.fontOutline).
-- Defaults to "" when omitted (callers without a note reference, or no outline set).
function AM.ApplyFontsToRenderFrame(f, bodySize, flagStr)
    if not f then return end
    bodySize = bodySize or (BigNoteBoxDB and BigNoteBoxDB.fontSize) or BNB.DEFAULTS.fontSize
    flagStr  = flagStr or ""

    local bodyPath = BNB.GetBodyFont and select(1, BNB.GetBodyFont()) or nil
    local boldPath = BNB.GetBoldFont and BNB.GetBoldFont() or bodyPath

    -- Independent size mode: user has set explicit pixel sizes for each heading level.
    -- Multiplier mode (default): sizes derived from bodySize using fixed ratios.
    local db = BigNoteBoxDB
    local h1sz, h2sz, h3sz, psz
    if db and db.richIndependentSizes then
        h1sz = db.richH1Size   or 25
        h2sz = db.richH2Size   or 20
        h3sz = db.richH3Size   or 16
        psz  = db.richBodySize or BNB.DEFAULTS.richBodySize
    else
        h1sz = bodySize * 2.0
        h2sz = bodySize * 1.6
        h3sz = bodySize * 1.3
        psz  = bodySize
    end

    SetTagFont(f, "h1", GetOrCreateFontObj("h1", boldPath, h1sz, flagStr))
    SetTagFont(f, "h2", GetOrCreateFontObj("h2", boldPath, h2sz, flagStr))
    SetTagFont(f, "h3", GetOrCreateFontObj("h3", boldPath, h3sz, flagStr))
    SetTagFont(f, "p",  GetOrCreateFontObj("p",  bodyPath, psz,  flagStr))

    -- White text for headings/body; colour tags in markup override per-span.
    -- Note: SimpleHTML does not support SetFontObject/SetTextColor for "a" tags —
    -- link colour is applied by wrapping <a> content in WoW colour codes in ToHTML.
    f:SetTextColor("h1", 1, 1, 1)
    f:SetTextColor("h2", 1, 1, 1)
    f:SetTextColor("h3", 1, 1, 1)
    f:SetTextColor("p",  0.90, 0.90, 0.90)
end

--------------------------------------------------------------------------------
-- RENDER FRAME FACTORY
--------------------------------------------------------------------------------
function AM.CreateRenderFrame(name, parent)
    -- BNBSimpleHTMLTemplate (defined in UI/RichNote.xml) seeds the font slots
    -- that SimpleHTML requires. Without XML-defined font slots the frame
    -- renders nothing regardless of SetFontObject calls made at runtime.
    local f = CreateFrame("SimpleHTML", name, parent, "BNBSimpleHTMLTemplate")
    -- Anchoring and width are set by the caller (UpdateBodyTopAnchor + SetWidth).
    -- Do NOT call SetAllPoints here — SimpleHTML needs an explicit SetWidth to reflow.

    local rawSetText = getmetatable(f).__index.SetText
    f.SetHTML = function(self, html)
        rawSetText(self, html)
        self:SetHeight(self:GetContentHeight())
    end

    -- Item/spell hyperlink tooltip on hover
    f:SetScript("OnHyperlinkEnter", function(self, link)
        local linkType = link:match("^(%a+):")
        if linkType == "item" or linkType == "spell"
           or linkType == "achievement" or linkType == "quest" then
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            pcall(function() GameTooltip:SetHyperlink(link) end)
            GameTooltip:Show()
        end
    end)

    f:SetScript("OnHyperlinkLeave", function()
        GameTooltip:Hide()
    end)

    -- Clickable links: WoW item/spell links are informational; plain URLs copy
    f:SetScript("OnHyperlinkClick", function(self, link, text, button)
        if button ~= "LeftButton" then return end
        local linkType = link:match("^(%a+):")
        -- Plain http/https URLs or unknown types → clipboard hint
        if not linkType or linkType == "https" or linkType == "http" then
            if BNB.ShowClipboardHint then BNB.ShowClipboardHint(link) end
        end
        -- WoW item/spell/quest links are handled by OnHyperlinkEnter tooltip only
    end)

    return f
end

--------------------------------------------------------------------------------
-- IS RICH
--------------------------------------------------------------------------------
function AM.IsRich(note)
    return note ~= nil and note.richMode == true
end

--------------------------------------------------------------------------------
-- CONVERT TO PLAIN (strips all markup tags)
-- Calls onDone(confirmed) after user confirms or cancels the dialog.
--------------------------------------------------------------------------------
local TAG_PATTERNS = {
    "{br}",
    "{h%d+:?[cr]?}",   -- {h1} {h1:c} {h1:r}
    "{/h%d+}",          -- {/h1}
    "{p:?[cr]?}",       -- {p} {p:c} {p:r}
    "{/p}",
    "{img:[^}]+}",
    "{icon:[^}]+}",
    "{col:%x%x%x%x%x%x}",
    "{/col}",
    "{link%*[^*}]+%*[^}]*}",
}

local function StripMarkup(text)
    if not text then return "" end
    for _, pat in ipairs(TAG_PATTERNS) do
        text = text:gsub(pat, "")
    end
    return text
end
AM.StripMarkup = StripMarkup  -- exposed for sticky note plain-text rendering

-- The conversion itself, no confirm: the popup below and the Select mode
-- menu (ALL-234, which confirms once for all its notes) both call it
function AM.StripToPlain(noteID)
    local note = BNB.GetNote(noteID)
    if not note then return end
    -- Create a history snapshot before stripping so user can revert
    if BNB.HistorySnapshotNote then BNB.HistorySnapshotNote(noteID) end
    local stripped = StripMarkup(note.body or "")
    BNB.UpdateNote(noteID, { body = stripped, richMode = false })
    if BNB._currentNoteID == noteID and BNB.LoadNoteInEditor then
        BNB.LoadNoteInEditor(noteID)
    end
    if BNB.Sticky and BNB.Sticky.RefreshNote then
        BNB.Sticky.RefreshNote(noteID)
    end
end

function AM.ConvertToPlain(id, onDone)
    if not id then
        if onDone then onDone(false) end
        return
    end

    -- Register the confirm popup once
    if not StaticPopupDialogs["BNB_RICH_CONVERT_PLAIN"] then
        StaticPopupDialogs["BNB_RICH_CONVERT_PLAIN"] = {
            preferredIndex = 3,
            text     = BNB.L["ADV_CONVERT_PLAIN_CONFIRM"],
            button1  = BNB.L["ADV_REMOVE_TAGS_BTN"],
            button2  = BNB.L["CANCEL"],
            OnAccept = function(self, data)
                AM.StripToPlain(data.id)
                if data.onDone then data.onDone(true) end
            end,
            OnCancel = function(self, data)
                if data and data.onDone then data.onDone(false) end
            end,
            timeout      = 0,
            whileDead    = true,
            hideOnEscape = true,
        }
    end

    local popup = StaticPopup_Show("BNB_RICH_CONVERT_PLAIN")
    if popup then
        popup.data = { id = id, onDone = onDone }
    end
end

--------------------------------------------------------------------------------
-- CONVERT TO RICH
-- Sets richMode = true on the note. No content changes — user adds tags manually.
--------------------------------------------------------------------------------
function AM.ConvertToRich(id)
    if not id then return end
    local note = BNB.GetNote(id)
    if not note then return end
    -- Create a history snapshot before converting so user can revert
    if BNB.HistorySnapshotNote then BNB.HistorySnapshotNote(id) end
    BNB.UpdateNote(id, { richMode = true })
    if BNB._currentNoteID == id and BNB.LoadNoteInEditor then
        BNB.LoadNoteInEditor(id)
    end
end

--------------------------------------------------------------------------------
-- USER IMAGE MANIFEST
-- Reads BNB_UserImageManifest global (populated by UserImages.lua).
-- Entries may be short names relative to the UserImages/ folder:
--   "mymap.tga"            -> Interface\AddOns\BigNoteBox\UserImages\mymap.tga
--   "Horde/mymap.tga"      -> Interface\AddOns\BigNoteBox\UserImages\Horde\mymap.tga
-- Full paths (starting with "Interface") are passed through unchanged so
-- existing manifests with full paths continue to work without edits.
--------------------------------------------------------------------------------
local USER_IMG_PREFIX = "Interface\\AddOns\\BigNoteBox\\UserImages\\"
AM.USER_IMG_PREFIX = USER_IMG_PREFIX

-- Images registered by the player's own addon (SUG-09). The shipped
-- UserImages.lua sits inside BigNoteBox/, so every update overwrote it; a tiny
-- addon of the player's own (e.g. BigNoteBox_UserImages, with
-- "## Dependencies: BigNoteBox") survives updates:
--   BigNoteBox.RegisterUserImages("BigNoteBox_UserImages", { "mymap.tga", "Horde/emblem.tga" })
-- Names are relative to that addon's folder. UserImages/README.txt explains it.
local _userSets = {}   -- { prefix, names }
function BNB.RegisterUserImages(folder, names)
    if type(folder) ~= "string" or not folder:match("^[%w_%-%.]+$") or type(names) ~= "table" then
        return false
    end
    _userSets[#_userSets + 1] = { prefix = "Interface\\AddOns\\" .. folder .. "\\", names = names }
    return true
end

local function AddEntry(out, seen, prefix, entry)
    if type(entry) ~= "string" or entry == "" then return end
    local full
    -- Already a full path? Pass through. Otherwise prepend the folder, with any
    -- forward slashes the user typed turned into backslashes.
    if entry:sub(1, 9):lower() == "interface" then
        full = entry
    else
        full = prefix .. entry:gsub("/", "\\")
    end
    if not seen[full:lower()] then
        seen[full:lower()] = true
        out[#out + 1] = full
    end
end

function AM.GetUserImages()
    local out, seen = {}, {}
    for _, entry in ipairs(BNB_UserImageManifest or {}) do
        AddEntry(out, seen, USER_IMG_PREFIX, entry)
    end
    for _, set in ipairs(_userSets) do
        for _, entry in ipairs(set.names) do AddEntry(out, seen, set.prefix, entry) end
    end
    return out
end

-- The short name the image picker shows for a full path ("Horde/emblem.tga"):
-- the part after a registered folder, else the file name.
function AM.UserImageShortName(full)
    local low = full:lower()
    local prefixes = { USER_IMG_PREFIX }
    for _, set in ipairs(_userSets) do prefixes[#prefixes + 1] = set.prefix end
    for _, p in ipairs(prefixes) do
        if low:sub(1, #p) == p:lower() then return (full:sub(#p + 1):gsub("\\", "/")) end
    end
    return ((full:match("[/\\]([^/\\]+)$") or full):gsub("\\", "/"))
end

-- A typed image name to a full path: full paths pass through, a short name
-- that a registered image has resolves to it, anything else is taken as a
-- file in BigNoteBox/UserImages/ (as before).
function AM.ResolveUserImage(raw)
    local s = raw and raw:match("^%s*(.-)%s*$") or ""
    if s == "" then return nil end
    if s:sub(1, 9):lower() == "interface" then return s end
    local want = s:gsub("\\", "/"):lower()
    for _, full in ipairs(AM.GetUserImages()) do
        if AM.UserImageShortName(full):lower() == want then return full end
    end
    return USER_IMG_PREFIX .. s:gsub("/", "\\")
end

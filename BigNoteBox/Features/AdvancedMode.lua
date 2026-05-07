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
    local inBlock = false  -- true when inside a {h*} or {p} block

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

        -- 6. Structure open tags — set inBlock before step 7 decides to wrap
        for tag, html in pairs(STRUCT_OPEN) do
            if line:find(tag, 1, true) then
                line = line:gsub(tag:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1"), html)
                inBlock = true
            end
        end

        -- 7. Structure close tags
        for tag, html in pairs(STRUCT_CLOSE) do
            if line:find(tag, 1, true) then
                line = line:gsub(tag:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1"), html)
                inBlock = false
            end
        end

        -- 8. Bare lines (not inside a block tag, not empty) → wrap in <P>…</P>
        -- Skip wrapping if the line already contains block-level HTML elements
        -- (<h1>/<h2>/<h3>/<P>/<img>) — nesting them inside <P> kills the parser.
        if not inBlock and line ~= "" then
            local hasBlock = line:match("<h%d") or line:match("<P") or line:match("<img ")
            if not hasBlock then
                line = "<P>" .. line .. "</P>"
            end
        end

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

    -- SimpleHTML requires a complete <HTML><BODY>...</BODY></HTML> document.
    -- Join WITHOUT newlines — WoW's SimpleHTML parser treats newlines between
    -- block elements as orphan text nodes, which causes the parser to fall back
    -- to plain-text rendering for the entire document.
    return "<HTML><BODY>" .. table.concat(out) .. "</BODY></HTML>"
end

--------------------------------------------------------------------------------
-- FONT OBJECTS
-- Named per frame so multiple render frames don't share the same font object.
-- Must be deferred: called after PLAYER_LOGIN via AM.ApplyFontsToRenderFrame.
--------------------------------------------------------------------------------
local _fontObjs = {}  -- cache: key = "BNBRich_frameName_tag_flags"

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

local function GetOrCreateFontObj(key, path, size, flags)
    -- Include flags in cache key so outline changes don't reuse a stale object.
    local cacheKey = key .. (flags ~= "" and ("_" .. flags) or "")
    if not _fontObjs[cacheKey] then
        -- Named global font for the no-flag variant; anonymous for flagged ones.
        local fo
        if flags == "" then
            fo = _G[key]
            if not fo then fo = CreateFont(key) end
        else
            fo = CreateFont(nil)
        end
        _fontObjs[cacheKey] = fo
    end
    local fo = _fontObjs[cacheKey]
    if path and path ~= "" then
        pcall(function() fo:SetFont(path, math.max(math.floor(size + 0.5), 6), flags) end)
    end
    return fo
end

-- flagStr (optional): pass AM.OutlineFlagStr(note.fontOutline).
-- Defaults to "" when omitted (callers without a note reference, or no outline set).
function AM.ApplyFontsToRenderFrame(f, bodySize, flagStr)
    if not f then return end
    bodySize = bodySize or (BigNoteBoxDB and BigNoteBoxDB.fontSize) or 12
    flagStr  = flagStr or ""

    local bodyPath = BNB.GetBodyFont and select(1, BNB.GetBodyFont()) or nil
    local boldPath = BNB.GetBoldFont and BNB.GetBoldFont() or bodyPath

    local fname = f:GetName() or tostring(f)

    -- Independent size mode: user has set explicit pixel sizes for each heading level.
    -- Multiplier mode (default): sizes derived from bodySize using fixed ratios.
    local db = BigNoteBoxDB
    local h1sz, h2sz, h3sz, psz
    if db and db.richIndependentSizes then
        h1sz = db.richH1Size   or 25
        h2sz = db.richH2Size   or 20
        h3sz = db.richH3Size   or 16
        psz  = db.richBodySize or 12
    else
        h1sz = bodySize * 2.0
        h2sz = bodySize * 1.6
        h3sz = bodySize * 1.3
        psz  = bodySize
    end

    f:SetFontObject("h1", GetOrCreateFontObj("BNBRich_"..fname.."_h1", boldPath, h1sz, flagStr))
    f:SetFontObject("h2", GetOrCreateFontObj("BNBRich_"..fname.."_h2", boldPath, h2sz, flagStr))
    f:SetFontObject("h3", GetOrCreateFontObj("BNBRich_"..fname.."_h3", boldPath, h3sz, flagStr))
    f:SetFontObject("p",  GetOrCreateFontObj("BNBRich_"..fname.."_p",  bodyPath, psz,  flagStr))

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

function AM.ConvertToPlain(id, onDone)
    if not id then
        if onDone then onDone(false) end
        return
    end

    -- Register the confirm popup once
    if not StaticPopupDialogs["BNB_RICH_CONVERT_PLAIN"] then
        StaticPopupDialogs["BNB_RICH_CONVERT_PLAIN"] = {
            text     = "This will remove all formatting tags from this note. This cannot be undone.\n\nContinue?",
            button1  = "Remove tags",
            button2  = "Cancel",
            OnAccept = function(self, data)
                local noteID = data.id
                local note   = BNB.GetNote(noteID)
                if note then
                    -- Create a history snapshot before stripping so user can revert
                    if BNB.HistorySnapshotNote then BNB.HistorySnapshotNote(noteID) end
                    local stripped = StripMarkup(note.body or "")
                    BNB.UpdateNote(noteID, { body = stripped, richMode = false })
                    if BNB._currentNoteID == noteID and BNB.LoadNoteInEditor then
                        BNB.LoadNoteInEditor(noteID)
                    end
                    if BNB.RefreshNoteList then BNB.RefreshNoteList() end
                    if BNB.Sticky and BNB.Sticky.RefreshNote then
                        BNB.Sticky.RefreshNote(noteID)
                    end
                end
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
    if BNB.RefreshNoteList then BNB.RefreshNoteList() end
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

function AM.GetUserImages()
    local raw = BNB_UserImageManifest
    if not raw or #raw == 0 then return {} end
    local out = {}
    for _, entry in ipairs(raw) do
        if type(entry) == "string" and entry ~= "" then
            -- Already a full path? Pass through. Otherwise prepend prefix.
            if entry:sub(1, 9):lower() == "interface" then
                out[#out + 1] = entry
            else
                -- Normalise any forward slashes the user typed to backslashes
                local normalised = entry:gsub("/", "\\")
                out[#out + 1] = USER_IMG_PREFIX .. normalised
            end
        end
    end
    return out
end

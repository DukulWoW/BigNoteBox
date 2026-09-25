-- BigNoteBox Features/NoteExport.lua - Note export / import codec
-- JSON, Markdown and HTML encoders, the backup serializer and both import
-- parsers. No UI: the Backup tab and export window are UI/Config/Backup.lua.
-- Split out of ConfigWindow.lua (ALL-65.10).

local BNB = BigNoteBox
local L   = BNB.L

-- ── Export version — bump when the serialized format changes ─────────────────
local EXPORT_VERSION = 1

-- ── Format constants ──────────────────────────────────────────────────────────
local FMT_MARKDOWN = "markdown"
local FMT_JSON     = "json"

-- ── Minimal JSON helpers (no library required) ────────────────────────────────
-- Handles only the types present in our note schema:
--   string, number, boolean, nil, array-of-strings, {r,g,b} color table.
-- Does NOT handle arbitrary nested tables — intentional.

local function JsonEscapeStr(s)
    s = tostring(s)
    s = s:gsub("\\", "\\\\")
    s = s:gsub("\"", "\\\"")
    s = s:gsub("\n", "\\n")
    s = s:gsub("\r", "\\r")
    s = s:gsub("\t", "\\t")
    return "\"" .. s .. "\""
end

local function JsonEncodeNote(note)
    -- Encode tags array
    local tagParts = {}
    for _, t in ipairs(note.tags or {}) do
        tagParts[#tagParts + 1] = JsonEscapeStr(t)
    end
    local tagsJson = "[" .. table.concat(tagParts, ",") .. "]"

    -- Encode titleColor table or null
    local colorJson
    if note.titleColor then
        colorJson = string.format("{\"r\":%.4f,\"g\":%.4f,\"b\":%.4f}",
            note.titleColor.r or 1, note.titleColor.g or 1, note.titleColor.b or 1)
    else
        colorJson = "null"
    end

    -- Encode attachments array or null
    local attJson
    if note.attachments and #note.attachments > 0 then
        local attParts = {}
        for _, att in ipairs(note.attachments) do
            if att.type == "item" or att.type == "spell" then
                attParts[#attParts + 1] = string.format("{\"type\":\"%s\",\"id\":%d}", att.type, att.id)
            end
        end
        attJson = "[" .. table.concat(attParts, ",") .. "]"
    else
        attJson = "null"
    end

    -- Encode inspectGearItems array or null: [{id,slot,slotIdx}, ...]
    local gearJson
    if note.inspectGearItems and #note.inspectGearItems > 0 then
        local gp = {}
        for _, g in ipairs(note.inspectGearItems) do
            gp[#gp + 1] = string.format("{\"id\":%d,\"slot\":%s,\"slotIdx\":%d}",
                g.id or 0, JsonEscapeStr(g.slot or ""), g.slotIdx or 0)
        end
        gearJson = "[" .. table.concat(gp, ",") .. "]"
    else
        gearJson = "null"
    end

    -- Encode inspectTransmogItems array or null: [{id,slot,slotIdx,appearanceID}, ...]
    local tmogJson
    if note.inspectTransmogItems and #note.inspectTransmogItems > 0 then
        local tp = {}
        for _, t in ipairs(note.inspectTransmogItems) do
            tp[#tp + 1] = string.format("{\"id\":%d,\"slot\":%s,\"slotIdx\":%d,\"appearanceID\":%d}",
                t.id or 0, JsonEscapeStr(t.slot or ""), t.slotIdx or 0, t.appearanceID or 0)
        end
        tmogJson = "[" .. table.concat(tp, ",") .. "]"
    else
        tmogJson = "null"
    end

    -- Encode inspectTransmogAppearances object or null: {"slotIdx":appearanceID, ...}
    local tmogAppJson
    if note.inspectTransmogAppearances and next(note.inspectTransmogAppearances) then
        local ap = {}
        for slotIdx, appID in pairs(note.inspectTransmogAppearances) do
            ap[#ap + 1] = string.format("\"%d\":%d", slotIdx, appID)
        end
        tmogAppJson = "{" .. table.concat(ap, ",") .. "}"
    else
        tmogAppJson = "null"
    end

    -- Encode alarm sub-object or null
    local alarmJson
    if note.alarm then
        local a = note.alarm
        local gc = a.glowColor
        local glowColorJson = gc
            and string.format("[%.4f,%.4f,%.4f,%.4f]", gc[1] or 0, gc[2] or 0, gc[3] or 0, gc[4] or 1)
            or "null"
        local function abool(v) if v == nil then return "null" end return v and "true" or "false" end
        local function anum(v)  if v == nil then return "null" end return tostring(v) end
        local function astr(v)  if v == nil then return "null" end return JsonEscapeStr(tostring(v)) end
        -- recurDays is an array of booleans [{1=bool,...,7=bool}]
        local recurDaysJson = "null"
        if a.recurDays then
            local dp = {}
            for i = 1, 7 do dp[i] = a.recurDays[i] and "true" or "false" end
            recurDaysJson = "[" .. table.concat(dp, ",") .. "]"
        end
        alarmJson = string.format(
            "{\"time\":%s,\"timeType\":%s,\"fired\":%s,\"snoozedUntil\":%s," ..
            "\"recur\":%s,\"recurDays\":%s,\"recurEvery\":%s," ..
            "\"label\":%s,\"sound\":%s,\"fireMode\":%s," ..
            "\"combatMode\":%s,\"combatPost\":%s," ..
            "\"snoozeEnabled\":%s,\"snoozeDefault\":%s,\"igTime\":%s," ..
            "\"glowType\":%s,\"glowMode\":%s,\"glowColor\":%s," ..
            "\"glowLines\":%s,\"glowFrequency\":%s,\"glowLength\":%s," ..
            "\"glowParticles\":%s,\"glowScale\":%s,\"glowDuration\":%s}",
            anum(a.time),        astr(a.timeType),    abool(a.fired),      anum(a.snoozedUntil),
            astr(a.recur),       recurDaysJson,        anum(a.recurEvery),
            astr(a.label),       astr(a.sound),        astr(a.fireMode),
            astr(a.combatMode),  abool(a.combatPost),
            abool(a.snoozeEnabled), anum(a.snoozeDefault), anum(a.igTime),
            anum(a.glowType),    astr(a.glowMode),     glowColorJson,
            anum(a.glowLines),   anum(a.glowFrequency), anum(a.glowLength),
            anum(a.glowParticles), anum(a.glowScale),  anum(a.glowDuration))
    else
        alarmJson = "null"
    end

    local function field(k, v)
        if v == nil then return "\"" .. k .. "\":null" end
        if type(v) == "boolean" then return "\"" .. k .. "\":" .. (v and "true" or "false") end
        if type(v) == "number"  then return "\"" .. k .. "\":" .. tostring(v) end
        return "\"" .. k .. "\":" .. JsonEscapeStr(v)
    end

    local parts = {
        field("title",         note.title),
        field("body",          note.body),
        "\"tags\":"            .. tagsJson,
        field("context",       note.context),
        field("contextDisplay",note.contextDisplay),
        field("contextLeave",  note.contextLeave),
        field("pinned",        note.pinned or false),
        field("favorited",     note.favorited),
        field("locked",        note.locked),
        field("icon",          note.icon),
        "\"titleColor\":"      .. colorJson,
        field("fontOverride",  note.fontOverride),
        field("textAlign",     note.textAlign),
        field("fontOutline",   note.fontOutline),
        field("borderOverride",note.borderOverride),
        field("borderScale",   note.borderScale),
        field("borderOffset",  note.borderOffset),
        field("borderBrightness", note.borderBrightness),
        field("lineHeight",    note.lineHeight),
        field("scope",         note.scope),
        -- Waypoint: {mapID, x, y, label} table or null
        "\"waypoint\":"        .. (note.waypoint and string.format(
            "{\"mapID\":%d,\"x\":%.6f,\"y\":%.6f,\"label\":%s}",
            note.waypoint.mapID or 0,
            note.waypoint.x     or 0,
            note.waypoint.y     or 0,
            JsonEscapeStr(note.waypoint.label or "")) or "null"),
        field("wpClearOnLeave",note.wpClearOnLeave),
        field("richMode",      note.richMode),
        field("iconSource",    note.iconSource),
        field("source",        note.source),
        field("targetNpcID",       note.targetNpcID),
        field("targetPlayerKey",   note.targetPlayerKey),
        field("targetIsPet",       note.targetIsPet),
        field("inspectRaceID",     note.inspectRaceID),
        field("inspectSexID",      note.inspectSexID),
        field("created",       note.created),
        field("updated",       note.updated),
        "\"attachments\":"              .. attJson,
        "\"inspectGearItems\":"         .. gearJson,
        "\"inspectTransmogItems\":"     .. tmogJson,
        "\"inspectTransmogAppearances\":" .. tmogAppJson,
        "\"alarm\":"                    .. alarmJson,
    }
    return "  {" .. table.concat(parts, ",") .. "}"
end

local function JsonDecodeStr(s)
    -- Unescape a JSON string value (content between outer quotes already stripped)
    s = s:gsub("\\n",  "\n")
    s = s:gsub("\\r",  "\r")
    s = s:gsub("\\t",  "\t")
    s = s:gsub("\\\"", "\"")
    s = s:gsub("\\\\", "\\")
    return s
end

-- ── Markdown helpers ──────────────────────────────────────────────────────────

local function MdEscapeBody(body)
    -- The body goes between frontmatter and the next note separator (===).
    -- The only sequence that needs escaping is a line that is exactly "==="
    -- (our record separator). We prefix it with a zero-width space substitute
    -- — a single backslash, which is idiomatic in Markdown and easy to strip.
    body = body:gsub("\n===\n", "\n\\===\n")
    -- Also handle === at start or end of body
    if body:sub(1, 3) == "===" then body = "\\" .. body end
    return body
end

local function MdUnescapeBody(body)
    body = body:gsub("\n\\===\n", "\n===\n")
    if body:sub(1, 4) == "\\===" then body = body:sub(2) end
    return body
end

local function MdEncodeNote(note)
    local lines = {}
    lines[#lines + 1] = "title: " .. (note.title or "")
    if note.tags and #note.tags > 0 then
        lines[#lines + 1] = "tags: " .. table.concat(note.tags, ", ")
    end
    if note.context       then lines[#lines + 1] = "context: "        .. note.context        end
    if note.contextDisplay then lines[#lines + 1] = "contextDisplay: " .. note.contextDisplay end
    if note.contextLeave   then lines[#lines + 1] = "contextLeave: "   .. note.contextLeave   end
    if note.pinned         then lines[#lines + 1] = "pinned: true"                            end
    if note.favorited      then lines[#lines + 1] = "favorited: true"                         end
    if note.richMode       then lines[#lines + 1] = "richMode: true"                          end
    if note.locked ~= nil  then lines[#lines + 1] = "locked: " .. (note.locked and "true" or "false") end
    if note.icon           then lines[#lines + 1] = "icon: "           .. tostring(note.icon) end
    if note.titleColor     then
        lines[#lines + 1] = string.format("titleColor: %.4f,%.4f,%.4f",
            note.titleColor.r or 1, note.titleColor.g or 1, note.titleColor.b or 1)
    end
    if note.fontOverride   then lines[#lines + 1] = "fontOverride: "   .. note.fontOverride   end
    if note.textAlign      then lines[#lines + 1] = "textAlign: "      .. note.textAlign      end
    if note.fontOutline    then lines[#lines + 1] = "fontOutline: "    .. note.fontOutline    end
    if note.borderOverride then lines[#lines + 1] = "borderOverride: " .. note.borderOverride end
    if note.borderScale    then lines[#lines + 1] = "borderScale: "    .. tostring(note.borderScale)  end
    if note.borderOffset   then lines[#lines + 1] = "borderOffset: "   .. tostring(note.borderOffset) end
    if note.lineHeight     then lines[#lines + 1] = "lineHeight: "     .. note.lineHeight     end
    if note.created        then lines[#lines + 1] = "created: "        .. tostring(note.created)      end
    if note.updated        then lines[#lines + 1] = "updated: "        .. tostring(note.updated)      end
    if note.iconSource     then lines[#lines + 1] = "iconSource: "     .. note.iconSource             end
    if note.source         then lines[#lines + 1] = "source: "         .. note.source                 end
    if note.targetNpcID    then lines[#lines + 1] = "targetNpcID: "    .. tostring(note.targetNpcID)  end
    if note.targetPlayerKey then lines[#lines + 1] = "targetPlayerKey: " .. note.targetPlayerKey      end
    if note.targetIsPet    then lines[#lines + 1] = "targetIsPet: true"                               end
    if note.inspectRaceID  then lines[#lines + 1] = "inspectRaceID: "  .. tostring(note.inspectRaceID) end
    if note.inspectSexID ~= nil then lines[#lines + 1] = "inspectSexID: " .. tostring(note.inspectSexID) end
    if note.attachments and #note.attachments > 0 then
        local attParts = {}
        for _, att in ipairs(note.attachments) do
            if att.type and att.id then
                attParts[#attParts + 1] = att.type .. ":" .. att.id
            end
        end
        if #attParts > 0 then
            lines[#lines + 1] = "attachments: " .. table.concat(attParts, ",")
        end
    end

    lines[#lines + 1] = ""   -- blank line between frontmatter and body
    lines[#lines + 1] = MdEscapeBody(note.body or "")
    return table.concat(lines, "\n")
end

-- ── HTML export (three modes: note-only, plain, stylized) ─────────────────────

local HTML_ICON_CDN = "https://wow.zamimg.com/images/wow/icons/large/"
local HTML_IMG_DIR  = "img/"
local BNB_URL       = "https://www.curseforge.com/wow/addons/bignotebox"

-- Google Fonts import URL for each BNB built-in font ID.
-- LSM fonts have no web equivalent and fall back to Noto Serif.
local GOOGLE_FONT_MAP = {
    notoserif        = { import = "Noto+Serif:ital,wght@0,400;0,700;1,400",  family = "'Noto Serif', Georgia, serif" },
    ebgaramond       = { import = "EB+Garamond:ital,wght@0,400;0,700;1,400", family = "'EB Garamond', Georgia, serif" },
    notosans         = { import = "Noto+Sans:ital,wght@0,400;0,700;1,400",   family = "'Noto Sans', Arial, sans-serif" },
    jetbrains        = { import = "JetBrains+Mono:wght@400;700",             family = "'JetBrains Mono', monospace" },
    gloriahallelujah = { import = "Gloria+Hallelujah",                       family = "'Gloria Hallelujah', cursive" },
    opendyslexic     = { import = "Open+Sans:wght@400;700",                  family = "'Open Sans', sans-serif" }, -- OpenDyslexic not on GFonts; fallback
    fredoka          = { import = "Fredoka:wght@400;700",                    family = "'Fredoka', sans-serif" },
    playwrite        = { import = "Playwrite+IE",                            family = "'Playwrite IE', cursive" },
}
local DEFAULT_FONT = GOOGLE_FONT_MAP.notoserif

local function HtmlEsc(s)
    s = s:gsub("&", "&amp;")
    s = s:gsub("<", "&lt;")
    s = s:gsub(">", "&gt;")
    s = s:gsub("\"", "&quot;")
    return s
end

-- Resolve the Google Font for a note based on its fontOverride or global setting.
local function ResolveFont(note)
    -- Same resolution as the editor (ALL-14): an override or global pick that
    -- cannot be shown under the active font set exports as what is on screen.
    local id = BNB.ResolveFontID(note.fontOverride) or BNB.GetEffectiveFontID()
    return GOOGLE_FONT_MAP[id] or DEFAULT_FONT
end

-- Convert rich note markup body to browser HTML.
local function ConvertRichBody(body)
    if not body or body == "" then return "", false end
    local hasImages = body:find("{img:") ~= nil

    local lines = {}
    for line in (body .. "\n"):gmatch("([^\n]*)\n") do
        lines[#lines + 1] = line
    end

    local out = {}
    local inBlock = false

    local STRUCT_O = {
        ["{h1}"]   = "<h1>",       ["{h1:c}"] = '<h1 style="text-align:center;">',
        ["{h1:r}"] = '<h1 style="text-align:right;">',
        ["{h2}"]   = "<h2>",       ["{h2:c}"] = '<h2 style="text-align:center;">',
        ["{h2:r}"] = '<h2 style="text-align:right;">',
        ["{h3}"]   = "<h3>",       ["{h3:c}"] = '<h3 style="text-align:center;">',
        ["{h3:r}"] = '<h3 style="text-align:right;">',
        ["{p}"]    = "<p>",        ["{p:c}"]  = '<p style="text-align:center;">',
        ["{p:r}"]  = '<p style="text-align:right;">',
    }
    local STRUCT_C = {
        ["{/h1}"] = "</h1>", ["{/h2}"] = "</h2>",
        ["{/h3}"] = "</h3>", ["{/p}"]  = "</p>",
    }

    for _, rawLine in ipairs(lines) do
        local line = HtmlEsc(rawLine)

        -- {img:path:w:h[:align]}
        line = line:gsub("{img:([^:}]+):([^:}]+):([^:}]+):?([^:}]*)}", function(src, w, h, align)
            local a = align ~= "" and align or "center"
            if a == "c" then a = "center" elseif a == "l" then a = "left" elseif a == "r" then a = "right" end
            w = math.abs(tonumber(w) or 128); h = math.abs(tonumber(h) or 128)
            local filename = src:match("([^/\\]+)$") or src
            local st = a == "center" and ' style="display:block;margin:0.5em auto;"'
                    or a == "right"  and ' style="display:block;margin:0.5em 0 0.5em auto;"'
                    or ' style="display:block;margin:0.5em 0;"'
            return string.format('<img src="%s%s" width="%d" height="%d" alt="%s"%s/>',
                HTML_IMG_DIR, filename, w, h, filename, st)
        end)

        -- {icon:name:size[:align]}
        line = line:gsub("{icon:([^:}]+):(%d+):([lcr])}", function(name, size, align)
            size = tonumber(size) or 25; local lname = name:lower()
            local a = (align == "c") and "center" or (align == "r") and "right" or "left"
            local st = a == "center" and ' style="display:block;margin:0.5em auto;"'
                    or a == "right"  and ' style="display:block;margin:0.5em 0 0.5em auto;"' or ""
            return string.format('<img src="%s%s.jpg" width="%d" height="%d" alt="%s"%s/>',
                HTML_ICON_CDN, lname, size, size, name, st)
        end)
        line = line:gsub("{icon:([^:}]+):(%d+)}", function(name, size)
            size = tonumber(size) or 25; local lname = name:lower()
            return string.format('<img src="%s%s.jpg" width="%d" height="%d" alt="%s" style="vertical-align:middle;"/>',
                HTML_ICON_CDN, lname, size, size, name)
        end)

        -- {col:rrggbb}/{/col}
        line = line:gsub("{col:(%x%x%x%x%x%x)}", function(hex) return '<span style="color:#' .. hex .. ';">' end)
        line = line:gsub("{/col}", "</span>")

        -- {link*url*text}
        line = line:gsub("{link%*([^*}]+)%*([^}]*)}", function(url, lt) if lt == "" then lt = url end return '<a href="' .. url .. '">' .. lt .. '</a>' end)

        -- {br}
        line = line:gsub("{br}", "<br>")

        -- Structure tags
        for tag, html in pairs(STRUCT_O) do
            if line:find(tag, 1, true) then
                line = line:gsub(tag:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1"), html); inBlock = true
            end
        end
        for tag, html in pairs(STRUCT_C) do
            if line:find(tag, 1, true) then
                line = line:gsub(tag:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1"), html); inBlock = false
            end
        end

        -- Bare lines -> <p>
        if not inBlock and line ~= "" then
            local hasBlock = line:match("<h%d") or line:match("<p") or line:match("<img ")
            if not hasBlock then line = "<p>" .. line .. "</p>" end
        end

        out[#out + 1] = line
    end

    return table.concat(out, "\n"), hasImages
end

-- Convert plain note body to browser HTML preserving line structure.
-- Double newline = new <p>, single newline = <br>.
local function ConvertPlainBody(body)
    if not body or body == "" then return "" end
    -- Split on double newlines to get paragraphs
    local paragraphs = {}
    local current = {}
    for line in (body .. "\n"):gmatch("([^\n]*)\n") do
        if line == "" then
            if #current > 0 then
                paragraphs[#paragraphs + 1] = table.concat(current, "<br>\n")
                current = {}
            end
        else
            current[#current + 1] = HtmlEsc(line)
        end
    end
    if #current > 0 then
        paragraphs[#paragraphs + 1] = table.concat(current, "<br>\n")
    end
    local parts = {}
    for _, p in ipairs(paragraphs) do
        parts[#parts + 1] = "<p>" .. p .. "</p>"
    end
    return table.concat(parts, "\n")
end

-- Build the refbox HTML sidebar for a note's attachments.
-- WoW item quality hex colours (index matches Enum.ItemQuality)
local QUALITY_COLORS = {
    [0] = "#9d9d9d",  -- Poor (grey)
    [1] = "#ffffff",  -- Common (white)
    [2] = "#1eff00",  -- Uncommon (green)
    [3] = "#0070dd",  -- Rare (blue)
    [4] = "#a335ee",  -- Epic (purple)
    [5] = "#ff8000",  -- Legendary (orange)
    [6] = "#e6cc80",  -- Artifact (warm gold)
    [7] = "#00ccff",  -- Heirloom (cyan)
    [8] = "#00ccff",  -- WoW Token (cyan)
}

local function BuildRefboxHtml(note)
    local atts = note.attachments
    if not atts or #atts == 0 then return "" end
    local cards = {}
    for _, a in ipairs(atts) do
        local label, url, typeLabel, qualityHex
        if a.type == "item" then
            local name, _, quality = C_Item.GetItemInfo(a.id)
            label     = name or ("Item " .. a.id)
            url       = "https://www.wowhead.com/item=" .. a.id
            typeLabel = "Item"
            qualityHex = QUALITY_COLORS[quality or 1] or QUALITY_COLORS[1]
        elseif a.type == "spell" then
            local si = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(a.id)
            label     = (si and si.name) or ("Spell " .. a.id)
            url       = "https://www.wowhead.com/spell=" .. a.id
            typeLabel = "Spell"
            qualityHex = "#4db8ff"
        elseif a.type == "quest" then
            local title = C_QuestLog and C_QuestLog.GetTitleForQuestID
                and C_QuestLog.GetTitleForQuestID(a.id)
            label     = (title and title ~= "") and title
                or (a.title and a.title ~= "") and a.title
                or ("Quest " .. a.id)
            url       = "https://www.wowhead.com/quest=" .. a.id
            typeLabel = "Quest"
            qualityHex = "#ffd100"
        else
            label     = (a.type or "?") .. " " .. (a.id or "?")
            url       = nil
            typeLabel = a.type or "Unknown"
            qualityHex = QUALITY_COLORS[1]
        end

        -- Build the icon <img> via Wowhead tooltip integration:
        -- Wowhead's tooltip.js will enhance <a> tags with data-wowhead attributes,
        -- but for a static icon we use the Wowhead icon endpoint.
        -- Format: https://wow.zamimg.com/images/wow/icons/medium/ICONNAME.jpg
        -- Since we can't resolve FileID->iconName in-game, we use a placeholder
        -- icon div that Wowhead's script will populate via the link.
        local iconHtml = string.format(
            '<img class="rb-icon" src="%swow_store.jpg" width="36" height="36" alt="icon"/>',
            HTML_ICON_CDN)
        local nameHtml
        if url then
            nameHtml = string.format('<a href="%s" style="color:%s;">%s</a>',
                url, qualityHex, HtmlEsc(label))
        else
            nameHtml = string.format('<span style="color:%s;">%s</span>',
                qualityHex, HtmlEsc(label))
        end

        cards[#cards + 1] = '<div class="rb-card">'
            .. iconHtml
            .. '<div class="rb-info">'
            .. '<span class="rb-type">' .. HtmlEsc(typeLabel) .. '</span>'
            .. '<span class="rb-name">' .. nameHtml .. '</span>'
            .. '</div></div>'
    end
    if #cards == 0 then return "" end
    return '<div class="refbox"><h3>Reference Box</h3>'
        .. table.concat(cards, "\n") .. "</div>"
end

-- Build metadata HTML block.
local function BuildMetaHtml(note)
    local parts = {}
    if note.tags and #note.tags > 0 then
        parts[#parts + 1] = "<strong>Tags:</strong> " .. HtmlEsc(table.concat(note.tags, ", "))
    end
    if note.context and note.context ~= "" then
        parts[#parts + 1] = "<strong>Context:</strong> " .. HtmlEsc(note.context)
    end
    if note.created then
        parts[#parts + 1] = "<strong>Created:</strong> " .. date("%Y-%m-%d %H:%M", note.created)
    end
    if note.updated then
        parts[#parts + 1] = "<strong>Updated:</strong> " .. date("%Y-%m-%d %H:%M", note.updated)
    end
    if #parts == 0 then return "" end
    return '<div class="meta">' .. table.concat(parts, " &middot; ") .. "</div>"
end

-- Build <head> meta tags for Plain and Stylized modes.
local function BuildHeadMeta(note, isStylized)
    local title = (note.title and note.title ~= "") and HtmlEsc(note.title) or L["CFG_EXPORT_UNTITLED"]
    local author = UnitName("player") or L["CFG_EXPORT_UNKNOWN_AUTHOR"]
    local desc = L["CFG_EXPORT_META_DESC"]
    local m = {}
    m[#m + 1] = '<meta name="description" content="' .. desc .. '">'
    m[#m + 1] = '<meta name="author" content="' .. HtmlEsc(author) .. '">'
    m[#m + 1] = '<meta name="generator" content="' .. L["CFG_EXPORT_META_GENERATOR"] .. '">'
    m[#m + 1] = '<link rel="canonical" href="' .. BNB_URL .. '">'
    -- Open Graph
    m[#m + 1] = '<meta property="og:title" content="' .. title .. '">'
    m[#m + 1] = '<meta property="og:description" content="' .. desc .. '">'
    m[#m + 1] = '<meta property="og:type" content="article">'
    m[#m + 1] = '<meta property="og:site_name" content="BigNoteBox">'
    -- Copyright
    if isStylized then
        m[#m + 1] = '<meta name="copyright" content="Note by ' .. HtmlEsc(author) .. '. Template design by BigNoteBox.">'
    else
        m[#m + 1] = '<meta name="copyright" content="' .. HtmlEsc(author) .. '">'
    end
    return table.concat(m, "\n")
end

-- Get the title HTML with optional colour styling.
local function BuildTitleHtml(note)
    local title = (note.title and note.title ~= "") and HtmlEsc(note.title) or L["CFG_EXPORT_UNTITLED"]
    if note.titleColor then
        local r = math.floor((note.titleColor.r or 1) * 255 + 0.5)
        local g = math.floor((note.titleColor.g or 1) * 255 + 0.5)
        local b = math.floor((note.titleColor.b or 1) * 255 + 0.5)
        return string.format('<h1 style="color:rgb(%d,%d,%d);">%s</h1>', r, g, b, title)
    end
    return "<h1>" .. title .. "</h1>"
end

-- Convert the note body (dispatches to rich or plain converter).
local function ConvertBody(note)
    if note.richMode then
        return ConvertRichBody(note.body)
    else
        return ConvertPlainBody(note.body), (note.body or ""):find("{img:") ~= nil
    end
end

--------------------------------------------------------------------------------
-- MODE 1: NOTE ONLY
-- Fragment: title + body + refbox + meta, wrapped in START/END comments.
--------------------------------------------------------------------------------
local function HtmlExportNoteOnly(note)
    local bodyHtml, hasImages = ConvertBody(note)
    local refbox  = BuildRefboxHtml(note)
    local meta    = BuildMetaHtml(note)
    local parts   = {}
    parts[#parts + 1] = "<!-- START Exported from BigNoteBox - " .. BNB_URL .. " -->"
    parts[#parts + 1] = BuildTitleHtml(note)
    parts[#parts + 1] = bodyHtml
    if refbox ~= "" then parts[#parts + 1] = refbox end
    if meta   ~= "" then parts[#parts + 1] = meta end
    parts[#parts + 1] = "<!-- END Exported from BigNoteBox - " .. BNB_URL .. " -->"
    return table.concat(parts, "\n"), hasImages
end

--------------------------------------------------------------------------------
-- MODE 2: PLAIN HTML
-- Full document with skin-aware theming, refbox sidebar, metadata footer.
--------------------------------------------------------------------------------
local function HtmlExportPlain(note)
    local bodyHtml, hasImages = ConvertBody(note)
    local font    = ResolveFont(note)
    local title   = (note.title and note.title ~= "") and HtmlEsc(note.title) or L["CFG_EXPORT_UNTITLED"]
    local headMeta = BuildHeadMeta(note, false)
    local refbox  = BuildRefboxHtml(note)
    local meta    = BuildMetaHtml(note)

    -- Skin-aware colours
    local bgR, bgG, bgB       = 0.10, 0.10, 0.12
    local borderR, borderG, borderB = 0.28, 0.28, 0.28
    local textR, textG, textB = 0.88, 0.88, 0.88
    local linkR, linkG, linkB = 0.40, 0.85, 0.40

    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset then
        local p   = BNB.GetSkinPreset()
        local brt = BNB.GetSkinBrightness and BNB.GetSkinBrightness() or 1.0
        bgR = math.min(1, p.r * brt)
        bgG = math.min(1, p.g * brt)
        bgB = math.min(1, p.b * brt)
        borderR = math.min(1, p.br * brt)
        borderG = math.min(1, p.bg_ * brt)
        borderB = math.min(1, p.bb * brt)
        -- Lighten border colour for links
        linkR = math.min(1, borderR * 2.5)
        linkG = math.min(1, borderG * 2.5)
        linkB = math.min(1, borderB * 2.5)
    end

    local function css255(r, g, b) return math.floor(r*255+0.5), math.floor(g*255+0.5), math.floor(b*255+0.5) end
    local bR, bG, bB = css255(bgR, bgG, bgB)
    local brR, brG, brB = css255(borderR, borderG, borderB)
    local lR, lG, lB = css255(linkR, linkG, linkB)
    local tR, tG, tB = css255(textR, textG, textB)

    -- Slightly lighter bg for the refbox sidebar
    local rbR = math.min(255, bR + 12)
    local rbG = math.min(255, bG + 12)
    local rbB = math.min(255, bB + 12)

    local css = string.format(
        "@import url('https://fonts.googleapis.com/css2?family=%s&display=swap');\n", font.import)
        .. "* { box-sizing: border-box; }\n"
        .. string.format("body { font-family: %s; max-width: 900px; margin: 2em auto; padding: 0 1em; color: rgb(%d,%d,%d); background: rgb(%d,%d,%d); line-height: 1.6; font-size: 16px; }\n",
            font.family, tR, tG, tB, bR, bG, bB)
        .. string.format(".page { display: flex; gap: 1.5em; border: 1px solid rgb(%d,%d,%d); border-radius: 4px; padding: 2em; }\n", brR, brG, brB)
        .. ".page-body { flex: 1; min-width: 0; }\n"
        .. string.format(".refbox { width: 240px; flex-shrink: 0; background: rgb(%d,%d,%d); border: 1px solid rgb(%d,%d,%d); border-radius: 4px; padding: 1em; font-size: 0.9em; align-self: flex-start; }\n",
            rbR, rbG, rbB, brR, brG, brB)
        .. ".refbox h3 { margin: 0 0 0.8em; font-size: 1em; }\n"
        .. string.format(".rb-card { display: flex; gap: 0.6em; align-items: center; border: 1px solid rgb(%d,%d,%d); border-radius: 3px; padding: 0.5em; margin-bottom: 0.5em; background: rgba(%d,%d,%d,0.4); }\n",
            brR, brG, brB, rbR, rbG, rbB)
        .. ".rb-icon { width: 36px; height: 36px; flex-shrink: 0; background: #222; border-radius: 3px; }\n"
        .. ".rb-info { display: flex; flex-direction: column; min-width: 0; }\n"
        .. string.format(".rb-type { font-size: 0.75em; color: rgb(%d,%d,%d); text-transform: uppercase; letter-spacing: 0.05em; }\n",
            math.min(255, tR - 40), math.min(255, tG - 40), math.min(255, tB - 40))
        .. ".rb-name { font-size: 0.9em; font-weight: bold; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }\n"
        .. ".rb-name a { text-decoration: none; }\n"
        .. ".rb-name a:hover { text-decoration: underline; }\n"
        .. "h1 { font-size: 2em; margin: 0 0 0.5em; }\n"
        .. "h2 { font-size: 1.6em; margin: 0.8em 0 0.4em; }\n"
        .. "h3 { font-size: 1.3em; margin: 0.6em 0 0.3em; }\n"
        .. "p { margin: 0.4em 0; }\n"
        .. string.format("a { color: rgb(%d,%d,%d); }\n", lR, lG, lB)
        .. "img { max-width: 100%; height: auto; }\n"
        .. string.format(".meta { font-size: 0.85em; color: rgb(%d,%d,%d); border-top: 1px solid rgb(%d,%d,%d); padding-top: 0.5em; margin-top: 2em; }\n",
            math.min(255, tR - 60), math.min(255, tG - 60), math.min(255, tB - 60), brR, brG, brB)
        .. string.format(".footer { font-size: 0.8em; color: rgb(%d,%d,%d); margin-top: 1em; }\n",
            math.min(255, tR - 100), math.min(255, tG - 100), math.min(255, tB - 100))
        .. ".footer a { font-size: inherit; }\n"
        .. string.format(".font-controls { position: fixed; bottom: 1em; right: 1em; display: flex; gap: 0.3em; background: rgb(%d,%d,%d); border: 1px solid rgb(%d,%d,%d); border-radius: 4px; padding: 0.3em; }\n",
            bR, bG, bB, brR, brG, brB)
        .. string.format(".font-controls button { width: 2em; height: 2em; border: 1px solid rgb(%d,%d,%d); border-radius: 3px; background: rgb(%d,%d,%d); color: rgb(%d,%d,%d); font-size: 1em; cursor: pointer; font-weight: bold; }\n",
            brR, brG, brB, rbR, rbG, rbB, tR, tG, tB)
        .. ".font-controls button:hover { opacity: 0.8; }\n"

    local fontSizeJS = '<script>'
        .. 'var fs=16;'
        .. 'function bnbFS(d){fs=Math.max(10,Math.min(28,fs+d));document.body.style.fontSize=fs+"px";}'
        .. '</script>\n'

    local html = "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n"
        .. '<meta charset="utf-8">\n'
        .. '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
        .. "<title>" .. title .. "</title>\n"
        .. headMeta .. "\n"
        .. "<style>\n" .. css .. "</style>\n"
        .. "</head>\n<body>\n"
        .. '<div class="font-controls"><button onclick="bnbFS(-2)" title="' .. L["CFG_EXPORT_DECREASE_FONT"] .. '">-</button><button onclick="bnbFS(2)" title="' .. L["CFG_EXPORT_INCREASE_FONT"] .. '">+</button></div>\n'
        .. '<div class="page">\n'
        .. '<div class="page-body">\n'
        .. BuildTitleHtml(note) .. "\n"
        .. bodyHtml .. "\n"
        .. (meta ~= "" and (meta .. "\n") or "")
        .. '<div class="footer">Exported from <a href="' .. BNB_URL .. '">BigNoteBox</a></div>\n'
        .. "</div>\n"
        .. (refbox ~= "" and (refbox .. "\n") or "")
        .. "</div>\n"
        .. fontSizeJS
        .. '<script src="https://wow.zamimg.com/js/tooltips.js"></script>\n'
        .. "</body>\n</html>"

    return html, hasImages
end

--------------------------------------------------------------------------------
-- MODE 3: STYLIZED
-- Uses the book/tome template from HtmlTemplate.lua with content injected.
--------------------------------------------------------------------------------
local function HtmlExportStylized(note)
    local tpl = BNB.HtmlTemplate and BNB.HtmlTemplate.Get and BNB.HtmlTemplate.Get()
    if not tpl then return "<!-- Error: HtmlTemplate not loaded -->", false end

    local bodyHtml, hasImages = ConvertBody(note)
    local title   = (note.title and note.title ~= "") and HtmlEsc(note.title) or L["CFG_EXPORT_UNTITLED"]
    local headMeta = BuildHeadMeta(note, true)
    local refbox  = BuildRefboxHtml(note)
    local meta    = BuildMetaHtml(note)

    -- Build the title HTML (with optional colour)
    local titleHtml = title
    if note.titleColor then
        local r = math.floor((note.titleColor.r or 1) * 255 + 0.5)
        local g = math.floor((note.titleColor.g or 1) * 255 + 0.5)
        local b = math.floor((note.titleColor.b or 1) * 255 + 0.5)
        titleHtml = string.format('<span style="color:rgb(%d,%d,%d);">%s</span>', r, g, b, title)
    end

    -- Extra CSS for refbox cards and font controls (injected via %%META%%)
    local extraCSS = "<style>\n"
        .. ".rb-card { display: flex; gap: 0.6em; align-items: center; border: 1px solid rgba(180,160,120,0.3); border-radius: 3px; padding: 0.5em; margin-bottom: 0.5em; background: rgba(0,0,0,0.2); }\n"
        .. ".rb-icon { width: 36px; height: 36px; flex-shrink: 0; background: #222; border-radius: 3px; }\n"
        .. ".rb-info { display: flex; flex-direction: column; min-width: 0; }\n"
        .. ".rb-type { font-size: 0.75em; color: rgba(200,180,140,0.7); text-transform: uppercase; letter-spacing: 0.05em; }\n"
        .. ".rb-name { font-size: 0.9em; font-weight: bold; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }\n"
        .. ".rb-name a { text-decoration: none; }\n"
        .. ".rb-name a:hover { text-decoration: underline; }\n"
        .. ".refbox { margin-top: 1.5em; padding: 0.8em; border: 1px solid rgba(180,160,120,0.3); border-radius: 4px; background: rgba(0,0,0,0.15); }\n"
        .. ".refbox h3 { margin: 0 0 0.8em; font-size: 1em; }\n"
        .. ".meta { font-size: 0.85em; color: rgba(200,180,140,0.6); border-top: 1px solid rgba(180,160,120,0.2); padding-top: 0.5em; margin-top: 1.5em; }\n"
        .. "</style>"

    headMeta = headMeta .. "\n" .. extraCSS

    -- Build the body with refbox, meta, font controls, and Wowhead tooltips
    local fullBody = bodyHtml
    if refbox ~= "" then fullBody = fullBody .. "\n" .. refbox end
    if meta   ~= "" then fullBody = fullBody .. "\n" .. meta end

    -- Font size controls are intentionally omitted from stylized export —
    -- the tome/book template has its own fixed layout. Controls are available
    -- in the Plain HTML export mode only.
    local beforeBody = '\n<script src="https://wow.zamimg.com/js/tooltips.js"></script>\n'

    -- Replace placeholders in the template
    -- gsub treats % as special in replacements, so escape them
    local function safeReplace(s, pattern, repl)
        return s:gsub(pattern, function() return repl end)
    end
    local html = tpl
    html = safeReplace(html, "%%%%TITLE%%%%", title)
    html = safeReplace(html, "%%%%META%%%%", headMeta)
    html = safeReplace(html, "%%%%NOTE_TITLE%%%%", titleHtml)
    html = safeReplace(html, "%%%%NOTE_BODY%%%%", fullBody)
    -- Inject controls and scripts before </body>
    html = safeReplace(html, "</body>", beforeBody .. "</body>")

    return html, hasImages
end

-- Master dispatcher. mode: "noteonly", "plain", "stylized"
local function HtmlEncodeNote(note, mode)
    mode = mode or "plain"
    if mode == "noteonly" then
        return HtmlExportNoteOnly(note)
    elseif mode == "stylized" then
        return HtmlExportStylized(note)
    else
        return HtmlExportPlain(note)
    end
end

-- ── Serialize all notes ───────────────────────────────────────────────────────

local function SerializeNotes(fmt)
    local ndb   = BigNoteBoxNotesDB
    local order = ndb and ndb.noteOrder or {}
    local notes = ndb and ndb.notes     or {}
    local count = 0
    for _ in pairs(notes) do count = count + 1 end

    if fmt == FMT_JSON then
        local noteParts = {}
        for _, id in ipairs(order) do
            local note = notes[id]
            if note then noteParts[#noteParts + 1] = JsonEncodeNote(note) end
        end
        -- Also include any notes not in noteOrder (shouldn't happen, but safe)
        local seen = {}
        for _, id in ipairs(order) do seen[id] = true end
        for id, note in pairs(notes) do
            if not seen[id] then noteParts[#noteParts + 1] = JsonEncodeNote(note) end
        end

        local header = string.format(
            "{\"export_version\":%d,\"addon_version\":%s,\"note_count\":%d,\"notes\":[\n",
            EXPORT_VERSION,
            JsonEscapeStr(BNB.ADDON_VERSION or "1.0.0"),
            #noteParts)
        return header .. table.concat(noteParts, ",\n") .. "\n]}", #noteParts

    else  -- Markdown
        local chunks = {}
        local hdr = string.format(
            "# BigNoteBox Export v%d | %s | %d note(s)\n",
            EXPORT_VERSION,
            date("%Y-%m-%d %H:%M"),
            count)
        chunks[#chunks + 1] = hdr

        for _, id in ipairs(order) do
            local note = notes[id]
            if note then
                chunks[#chunks + 1] = "===\n" .. MdEncodeNote(note)
            end
        end
        local seen = {}
        for _, id in ipairs(order) do seen[id] = true end
        for id, note in pairs(notes) do
            if not seen[id] then
                chunks[#chunks + 1] = "===\n" .. MdEncodeNote(note)
            end
        end

        return table.concat(chunks, "\n"), count
    end
end

-- ── Deserialize — JSON ────────────────────────────────────────────────────────
-- Returns array of raw note tables, or nil on failure.

local function ParseJsonNotes(text)
    -- Quick sanity: must look like our envelope
    if not text:find("\"export_version\"") then return nil end
    if not text:find("\"notes\"") then return nil end

    -- Check version
    local expVer = tonumber(text:match("\"export_version\"%s*:%s*(%d+)"))
    if not expVer then return nil end
    if expVer > EXPORT_VERSION then
        BNB:Print(string.format(L["BACKUP_IMPORT_VERSION_WARN"], expVer, EXPORT_VERSION))
    end

    local parsed = {}

    -- Extract each note object {...} from the notes array.
    -- We use a simple brace-matching scan rather than a full recursive parser,
    -- which is safe because our values never contain unescaped { or }.
    local noteArray = text:match("\"notes\"%s*:%s*%[(.-)%]%s*}%s*$")
    if not noteArray then return nil end

    -- Split on top-level commas between objects
    local depth, start = 0, 1
    local objects = {}
    for i = 1, #noteArray do
        local c = noteArray:sub(i, i)
        if     c == "{" then depth = depth + 1; if depth == 1 then start = i end
        elseif c == "}" then
            depth = depth - 1
            if depth == 0 then objects[#objects + 1] = noteArray:sub(start, i) end
        end
    end

    for _, obj in ipairs(objects) do
        local note = {}

        -- Extract string fields
        for key, val in obj:gmatch("\"([^\"]+)\"%s*:%s*\"(.-[^\\])\"") do
            note[key] = JsonDecodeStr(val)
        end
        -- Also catch empty strings
        for key in obj:gmatch("\"([^\"]+)\"%s*:%s*\"\"") do
            note[key] = ""
        end
        -- Extract number fields
        for key, val in obj:gmatch("\"([^\"]+)\"%s*:%s*(%-?%d+%.?%d*)") do
            if not note[key] then  -- don't overwrite string already captured
                note[key] = tonumber(val)
            end
        end
        -- Extract boolean fields
        for key, val in obj:gmatch("\"([^\"]+)\"%s*:%s*(true|false)") do
            note[key] = (val == "true")
        end
        -- Extract titleColor sub-object
        local cr, cg, cb = obj:match("\"titleColor\"%s*:%s*{[^}]*\"r\"%s*:%s*(%-?[%d.]+)[^}]*\"g\"%s*:%s*(%-?[%d.]+)[^}]*\"b\"%s*:%s*(%-?[%d.]+)")
        if cr then
            note.titleColor = { r = tonumber(cr), g = tonumber(cg), b = tonumber(cb) }
        end
        -- Extract waypoint sub-object {mapID, x, y, label}
        local wpRaw = obj:match("\"waypoint\"%s*:%s*({[^}]*})")
        if wpRaw then
            local mid  = tonumber(wpRaw:match("\"mapID\"%s*:%s*(%d+)"))
            local wx   = tonumber(wpRaw:match("\"x\"%s*:%s*(%-?[%d.]+)"))
            local wy   = tonumber(wpRaw:match("\"y\"%s*:%s*(%-?[%d.]+)"))
            local wlbl = wpRaw:match("\"label\"%s*:%s*\"(.-[^\\])\"") or ""
            if mid then
                note.waypoint = { mapID = mid, x = wx or 0, y = wy or 0, label = JsonDecodeStr(wlbl) }
            end
        end
        -- Fix tags: re-parse as array from raw object text
        local tagsRaw = obj:match("\"tags\"%s*:%s*(%b[])")
        if tagsRaw then
            note.tags = {}
            for tv in tagsRaw:gmatch("\"(.-[^\\])\"") do
                note.tags[#note.tags + 1] = JsonDecodeStr(tv)
            end
        else
            note.tags = {}
        end
        -- Null fields become nil (already nil in Lua — just ensure booleans aren't set)
        for key in obj:gmatch("\"([^\"]+)\"%s*:%s*null") do
            note[key] = nil
        end
        -- Extract attachments array: [{type,id}, ...]
        -- Must be parsed explicitly; the generic string/number regexes would only
        -- extract the last "type" and "id" values as spurious top-level fields.
        local attRaw = obj:match("\"attachments\"%s*:%s*(%b[])")
        if attRaw then
            note.attachments = {}
            -- Each sub-object is {...}; extract type+id from each one.
            for attObj in attRaw:gmatch("{([^}]+)}") do
                local atype = attObj:match("\"type\"%s*:%s*\"([^\"]+)\"")
                local aid   = tonumber(attObj:match("\"id\"%s*:%s*(%d+)"))
                if atype and aid then
                    note.attachments[#note.attachments + 1] = { type = atype, id = aid }
                end
            end
            if #note.attachments == 0 then note.attachments = nil end
        end
        -- Extract inspectGearItems array: [{id,slot,slotIdx}, ...]
        local gearRaw = obj:match("\"inspectGearItems\"%s*:%s*(%b[])")
        if gearRaw then
            note.inspectGearItems = {}
            for gObj in gearRaw:gmatch("{([^}]+)}") do
                local gid  = tonumber(gObj:match("\"id\"%s*:%s*(%d+)"))
                local gsl  = gObj:match("\"slot\"%s*:%s*\"([^\"]*)\"")
                local gsli = tonumber(gObj:match("\"slotIdx\"%s*:%s*(%d+)"))
                if gid then
                    note.inspectGearItems[#note.inspectGearItems + 1] =
                        { id = gid, slot = gsl or "", slotIdx = gsli or 0 }
                end
            end
            if #note.inspectGearItems == 0 then note.inspectGearItems = nil end
        end
        -- Extract inspectTransmogItems array: [{id,slot,slotIdx,appearanceID}, ...]
        local tmogRaw = obj:match("\"inspectTransmogItems\"%s*:%s*(%b[])")
        if tmogRaw then
            note.inspectTransmogItems = {}
            for tObj in tmogRaw:gmatch("{([^}]+)}") do
                local tid  = tonumber(tObj:match("\"id\"%s*:%s*(%d+)"))
                local tsl  = tObj:match("\"slot\"%s*:%s*\"([^\"]*)\"")
                local tsli = tonumber(tObj:match("\"slotIdx\"%s*:%s*(%d+)"))
                local tapp = tonumber(tObj:match("\"appearanceID\"%s*:%s*(%d+)"))
                if tid then
                    note.inspectTransmogItems[#note.inspectTransmogItems + 1] =
                        { id = tid, slot = tsl or "", slotIdx = tsli or 0, appearanceID = tapp or 0 }
                end
            end
            if #note.inspectTransmogItems == 0 then note.inspectTransmogItems = nil end
        end
        -- Extract inspectTransmogAppearances object: {"slotIdx":appearanceID, ...}
        local tmogAppRaw = obj:match("\"inspectTransmogAppearances\"%s*:%s*({[^}]*})")
        if tmogAppRaw and tmogAppRaw ~= "{}" then
            note.inspectTransmogAppearances = {}
            for k, v in tmogAppRaw:gmatch("\"(%d+)\"%s*:%s*(%d+)") do
                note.inspectTransmogAppearances[tonumber(k)] = tonumber(v)
            end
            if not next(note.inspectTransmogAppearances) then
                note.inspectTransmogAppearances = nil
            end
        end
        -- Extract alarm sub-object
        local alarmRaw = obj:match("\"alarm\"%s*:%s*({.-})")
        if alarmRaw then
            local a = {}
            -- Scalar fields via generic pass
            for k, v in alarmRaw:gmatch("\"([^\"]+)\"%s*:%s*\"(.-[^\\])\"") do a[k] = JsonDecodeStr(v) end
            for k in alarmRaw:gmatch("\"([^\"]+)\"%s*:%s*\"\"") do a[k] = "" end
            for k, v in alarmRaw:gmatch("\"([^\"]+)\"%s*:%s*(%-?%d+%.?%d*)") do
                if not a[k] then a[k] = tonumber(v) end
            end
            for k, v in alarmRaw:gmatch("\"([^\"]+)\"%s*:%s*(true|false)") do
                if a[k] == nil then a[k] = (v == "true") end
            end
            -- glowColor array [r,g,b,a]
            local gcRaw = alarmRaw:match("\"glowColor\"%s*:%s*(%b[])")
            if gcRaw then
                local vals = {}
                for n in gcRaw:gmatch("(%-?[%d.]+)") do vals[#vals+1] = tonumber(n) end
                if #vals >= 3 then
                    a.glowColor = { vals[1], vals[2], vals[3], vals[4] or 1 }
                end
            end
            -- recurDays boolean array
            local rdRaw = alarmRaw:match("\"recurDays\"%s*:%s*(%b[])")
            if rdRaw then
                a.recurDays = {}
                local i = 1
                for v in rdRaw:gmatch("(true|false)") do
                    a.recurDays[i] = (v == "true"); i = i + 1
                end
            end
            -- null cleanup for alarm
            for k in alarmRaw:gmatch("\"([^\"]+)\"%s*:%s*null") do a[k] = nil end
            if next(a) then note.alarm = a end
        end
        -- Clean up spurious top-level keys that leaked from sub-object parsing
        note.type = nil; note.id = nil
        note.r = nil; note.g = nil; note.b = nil
        note.mapID = nil; note.x = nil; note.y = nil; note.label = nil
        note.slot = nil; note.slotIdx = nil; note.appearanceID = nil

        if note.title then parsed[#parsed + 1] = note end
    end

    return #parsed > 0 and parsed or nil
end

-- ── Deserialize — Markdown ────────────────────────────────────────────────────

local function ParseMarkdownNotes(text)
    -- Must start with our header line
    if not text:find("^# BigNoteBox Export v") then return nil end

    local expVer = tonumber(text:match("^# BigNoteBox Export v(%d+)"))
    if not expVer then return nil end
    if expVer > EXPORT_VERSION then
        BNB:Print(string.format(L["BACKUP_IMPORT_VERSION_WARN"], expVer, EXPORT_VERSION))
    end

    local parsed = {}

    -- Split into records on lines that are exactly "==="
    local records = {}
    local cur = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        if line == "===" then
            if #cur > 0 then records[#records + 1] = table.concat(cur, "\n") end
            cur = {}
        else
            cur[#cur + 1] = line
        end
    end
    if #cur > 0 then records[#records + 1] = table.concat(cur, "\n") end

    for _, rec in ipairs(records) do
        if rec ~= "" and not rec:find("^# BigNoteBox Export") then
            local note  = { tags = {} }
            local lines = {}
            for l in (rec .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = l end

            -- Separate frontmatter (key: value lines) from body (after blank line)
            local bodyStart = #lines + 1
            for i, l in ipairs(lines) do
                if l == "" then bodyStart = i + 1; break end
            end

            for i = 1, bodyStart - 2 do
                local key, val = lines[i]:match("^([%w]+):%s*(.-)%s*$")
                if key and val then
                    if     key == "title"          then note.title          = val
                    elseif key == "context"        then note.context        = val
                    elseif key == "contextDisplay" then note.contextDisplay = val
                    elseif key == "contextLeave"   then note.contextLeave   = val
                    elseif key == "fontOverride"   then note.fontOverride   = val
                    elseif key == "textAlign"      then note.textAlign      = val
                    elseif key == "fontOutline"    then note.fontOutline    = val
                    elseif key == "borderOverride" then note.borderOverride = val
                    elseif key == "lineHeight"     then note.lineHeight     = val
                    elseif key == "icon"           then note.icon           = tonumber(val) or val
                    elseif key == "borderScale"      then note.borderScale      = tonumber(val)
                    elseif key == "borderOffset"     then note.borderOffset     = tonumber(val)
                    elseif key == "borderBrightness" then note.borderBrightness = tonumber(val)
                    elseif key == "scope"            then note.scope            = val
                    elseif key == "wpClearOnLeave"   then note.wpClearOnLeave   = (val == "true") or nil
                    elseif key == "waypoint" and val ~= "" and val ~= "null" then
                        -- Format: mapID:x:y:label
                        local mid, wx, wy, wlbl = val:match("^(%d+):(%-?[%d.]+):(%-?[%d.]+):(.*)$")
                        if mid then
                            note.waypoint = {
                                mapID = tonumber(mid),
                                x     = tonumber(wx),
                                y     = tonumber(wy),
                                label = wlbl or "",
                            }
                        end
                    elseif key == "iconSource"      then note.iconSource      = val
                    elseif key == "source"          then note.source          = val
                    elseif key == "targetNpcID"     then note.targetNpcID     = tonumber(val)
                    elseif key == "targetPlayerKey" then note.targetPlayerKey = val
                    elseif key == "targetIsPet"     then note.targetIsPet     = (val == "true") or nil
                    elseif key == "inspectRaceID"   then note.inspectRaceID   = tonumber(val)
                    elseif key == "inspectSexID"    then note.inspectSexID    = tonumber(val)
                    elseif key == "created"        then note.created        = tonumber(val)
                    elseif key == "updated"        then note.updated        = tonumber(val)
                    elseif key == "pinned"         then note.pinned         = (val == "true")
                    elseif key == "favorited"      then note.favorited      = (val == "true") or nil
                    elseif key == "richMode"       then note.richMode       = (val == "true") or nil
                    elseif key == "locked"         then note.locked         = (val == "true")
                    elseif key == "titleColor"     then
                        local r, g, b = val:match("(%-?[%d.]+),(%-?[%d.]+),(%-?[%d.]+)")
                        if r then note.titleColor = {r=tonumber(r),g=tonumber(g),b=tonumber(b)} end
                    elseif key == "tags" and val ~= "" then
                        for tag in val:gmatch("[^,]+") do
                            local t = tag:match("^%s*(.-)%s*$")
                            if t ~= "" then note.tags[#note.tags + 1] = t end
                        end
                    elseif key == "attachments" and val ~= "" and val ~= "null" then
                        -- Format: type:id,type:id,...
                        note.attachments = {}
                        for entry in val:gmatch("[^,]+") do
                            local atype, aid = entry:match("^([^:]+):(%d+)$")
                            if atype and aid then
                                note.attachments[#note.attachments + 1] = {
                                    type = atype, id = tonumber(aid)
                                }
                            end
                        end
                        if #note.attachments == 0 then note.attachments = nil end
                    end
                end
            end

            -- Body: everything from bodyStart to end, unescape separator
            local bodyLines = {}
            for i = bodyStart, #lines do bodyLines[#bodyLines + 1] = lines[i] end
            -- Trim trailing blank lines
            while #bodyLines > 0 and bodyLines[#bodyLines] == "" do
                table.remove(bodyLines)
            end
            note.body = MdUnescapeBody(table.concat(bodyLines, "\n"))

            if note.title then parsed[#parsed + 1] = note end
        end
    end

    return #parsed > 0 and parsed or nil
end

-- ── Import notes into NoteManager ────────────────────────────────────────────

local function ImportNotes(noteList, remapScope)
    -- remapScope: if true, any note with scope "char:X" is rewritten to current char.
    if not noteList or #noteList == 0 then return 0 end
    local now = time()
    local count = 0
    for _, src in ipairs(noteList) do
        if src.title and src.title ~= "" then
            local id = BNB.CreateNote(src.title, src.body or "")
            -- Resolve scope: remap char-scoped notes to current char if requested
            local resolvedScope = src.scope
            if remapScope and resolvedScope and resolvedScope:find("^char:") then
                resolvedScope = "char:" .. (BNB.currentChar or resolvedScope:sub(6))
            end
            local fields = {
                tags             = src.tags or {},
                context          = src.context,
                contextDisplay   = src.contextDisplay,
                contextLeave     = src.contextLeave,
                pinned           = src.pinned or false,
                locked           = src.locked,
                icon             = src.icon,
                titleColor       = src.titleColor,
                fontOverride     = src.fontOverride,
                textAlign        = src.textAlign,
                fontOutline      = src.fontOutline,
                borderOverride   = src.borderOverride,
                borderScale      = src.borderScale,
                borderOffset     = src.borderOffset,
                borderBrightness = src.borderBrightness,
                lineHeight       = src.lineHeight,
                scope            = resolvedScope,
                waypoint         = src.waypoint,
                wpClearOnLeave   = src.wpClearOnLeave,
                iconSource       = src.iconSource,
                source           = src.source,
                targetNpcID      = src.targetNpcID,
                targetPlayerKey  = src.targetPlayerKey,
                targetIsPet      = src.targetIsPet,
                inspectRaceID    = src.inspectRaceID,
                inspectSexID     = src.inspectSexID,
                inspectGearItems          = src.inspectGearItems,
                inspectTransmogItems      = src.inspectTransmogItems,
                inspectTransmogAppearances = src.inspectTransmogAppearances,
                alarm            = src.alarm,
                created          = src.created or now,
                updated          = src.updated or now,
            }
            -- favorited: only set if truthy (nil-safe)
            if src.favorited then fields.favorited = true end
            -- attachments: only set if non-empty
            if src.attachments and #src.attachments > 0 then
                fields.attachments = src.attachments
            end
            BNB.UpdateNote(id, fields)
            count = count + 1
        end
    end
    if BNB.RefreshNoteList then BNB.RefreshNoteList() end
    return count
end

-- Public wrapper so the BNB_IMPORT_SCOPE_REMAP popup callback (defined in
-- SlashCommands.lua, which loads before this file) can call ImportNotes.
-- Set after the local is defined so the closure captures the correct function.
BNB._DoImport       = ImportNotes
BNB._ParseJsonNotes = ParseJsonNotes

-- Used by UI/Config/Backup.lua, which reads it at call time: Features/ loads
-- after UI/ in the TOC.
BNB.NoteExport = {
    FMT_MARKDOWN       = FMT_MARKDOWN,
    FMT_JSON           = FMT_JSON,
    JsonEncodeNote     = JsonEncodeNote,
    MdEncodeNote       = MdEncodeNote,
    HtmlEncodeNote     = HtmlEncodeNote,
    SerializeNotes     = SerializeNotes,
    ParseJsonNotes     = ParseJsonNotes,
    ParseMarkdownNotes = ParseMarkdownNotes,
}

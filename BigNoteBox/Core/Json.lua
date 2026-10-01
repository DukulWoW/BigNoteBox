-- BigNoteBox Core/Json.lua
-- A small JSON encoder and string-aware recursive-descent decoder (BUG-17,
-- ALL-136.5), used by the JSON backup in Features/NoteExport.lua.
--
-- The backup used to be read with Lua patterns that counted braces without
-- knowing about strings, so one unbalanced "{" in a note body (rich markup,
-- or plain text) merged or lost the notes after it, and a value ending in a
-- backslash broke the string match.
--
-- Encoding rules (and what Decode gives back):
--   a table whose keys are exactly 1..n is an array, anything else an object;
--   object keys are written as strings, and Decode turns a key that is a
--   whole number ("5") back into a number, so sparse maps keyed by slot
--   index round-trip; an empty table is written as [] and read as {}.
--   Functions and other non-data values are skipped.
--
-- Public API:
--   BNB.Json.Encode(value)        -> string
--   BNB.Json.EncodeString(s)      -> quoted, escaped string
--   BNB.Json.Decode(text)         -> value, or nil + error message
--
-- No dependencies, so the luajit tools in _work/tools can load it on its own.

local BNB = BigNoteBox
BNB.Json = BNB.Json or {}
local Json = BNB.Json

local byte, sub, find, format = string.byte, string.sub, string.find, string.format
local concat = table.concat

--------------------------------------------------------------------------------
-- ENCODE
--------------------------------------------------------------------------------
local ESC = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
local function EscChar(c)
    return ESC[c] or format("\\u%04x", byte(c))
end

local function EncodeString(s)
    return '"' .. s:gsub('[%c"\\]', EscChar) .. '"'
end
Json.EncodeString = EncodeString

local function EncodeNumber(n)
    if n ~= n or n == math.huge or n == -math.huge then return "null" end
    -- %.0f, not %d: %d goes through a C long, 32 bits on Windows
    if n == math.floor(n) and n > -1e15 and n < 1e15 then return format("%.0f", n) end
    return format("%.14g", n)
end

local Encode
local function EncodeTable(t, depth)
    if depth > 32 then return "null" end
    local n, count = #t, 0
    for _ in pairs(t) do count = count + 1 end
    if count == n then
        local parts = {}
        for i = 1, n do parts[i] = Encode(t[i], depth + 1) end
        return "[" .. concat(parts, ",") .. "]"
    end
    -- Object: sorted keys, so the same note always gives the same text
    local keys = {}
    for k, v in pairs(t) do
        local tk, tv = type(k), type(v)
        if (tk == "string" or tk == "number")
           and (tv == "string" or tv == "number" or tv == "boolean" or tv == "table") then
            keys[#keys + 1] = k
        end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for i, k in ipairs(keys) do
        local ks = type(k) == "number" and EncodeNumber(k) or k
        parts[i] = EncodeString(ks) .. ":" .. Encode(t[k], depth + 1)
    end
    return "{" .. concat(parts, ",") .. "}"
end

Encode = function(v, depth)
    local tv = type(v)
    if tv == "string"  then return EncodeString(v) end
    if tv == "number"  then return EncodeNumber(v) end
    if tv == "boolean" then return v and "true" or "false" end
    if tv == "table"   then return EncodeTable(v, depth or 1) end
    return "null"
end
function Json.Encode(v) return Encode(v, 1) end

--------------------------------------------------------------------------------
-- DECODE
--------------------------------------------------------------------------------
local MAX_DEPTH = 64

local function Fail(pos, msg)
    error({ pos = pos, msg = msg }, 0)
end

local function SkipWs(s, i)
    local _, e = find(s, "^[ \n\r\t]*", i)
    return e + 1
end

local function Utf8(cp)
    if cp < 0x80 then return string.char(cp) end
    if cp < 0x800 then
        return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
    end
    if cp < 0x10000 then
        return string.char(0xE0 + math.floor(cp / 0x1000),
            0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
    end
    return string.char(0xF0 + math.floor(cp / 0x40000),
        0x80 + math.floor(cp / 0x1000) % 0x40,
        0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
end

-- Escapes by the byte after the backslash
local UNESC = { [34] = '"', [92] = "\\", [47] = "/", [98] = "\b", [102] = "\f",
                [110] = "\n", [114] = "\r", [116] = "\t" }

-- i is the opening quote; returns the string and the position after it
local function ParseString(s, i)
    local parts, n, j = {}, 0, i + 1
    while true do
        local k = find(s, '["\\]', j)
        if not k then Fail(i, "unterminated string") end
        if k > j then n = n + 1; parts[n] = sub(s, j, k - 1) end
        if byte(s, k) == 34 then return concat(parts), k + 1 end
        local c = byte(s, k + 1)
        if c == 117 then   -- \uXXXX, with surrogate pairs joined
            local hex = sub(s, k + 2, k + 5)
            if not find(hex, "^%x%x%x%x$") then Fail(k, "bad \\u escape") end
            local cp, nxt = tonumber(hex, 16), k + 6
            if cp >= 0xD800 and cp <= 0xDBFF and sub(s, nxt, nxt + 1) == "\\u" then
                local lo = tonumber(sub(s, nxt + 2, nxt + 5), 16)
                if lo and lo >= 0xDC00 and lo <= 0xDFFF then
                    cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
                    nxt = nxt + 6
                end
            end
            n = n + 1; parts[n] = Utf8(cp); j = nxt
        else
            local e = c and UNESC[c]
            if not e then Fail(k, "bad escape") end
            n = n + 1; parts[n] = e; j = k + 2
        end
    end
end

local ParseValue

local function ParseArray(s, i, depth)
    local arr, n = {}, 0
    i = SkipWs(s, i + 1)
    if byte(s, i) == 93 then return arr, i + 1 end   -- ]
    while true do
        local v
        v, i = ParseValue(s, i, depth)
        n = n + 1; arr[n] = v
        i = SkipWs(s, i)
        local c = byte(s, i)
        if c == 93 then return arr, i + 1 end
        if c ~= 44 then Fail(i, "expected , or ]") end
        i = SkipWs(s, i + 1)
    end
end

local function ParseObject(s, i, depth)
    local obj = {}
    i = SkipWs(s, i + 1)
    if byte(s, i) == 125 then return obj, i + 1 end   -- }
    while true do
        if byte(s, i) ~= 34 then Fail(i, "expected a key") end
        local k
        k, i = ParseString(s, i)
        i = SkipWs(s, i)
        if byte(s, i) ~= 58 then Fail(i, "expected :") end
        local v
        v, i = ParseValue(s, SkipWs(s, i + 1), depth)
        if find(k, "^%-?%d+$") then k = tonumber(k) end
        obj[k] = v   -- null leaves the key out
        i = SkipWs(s, i)
        local c = byte(s, i)
        if c == 125 then return obj, i + 1 end
        if c ~= 44 then Fail(i, "expected , or }") end
        i = SkipWs(s, i + 1)
    end
end

ParseValue = function(s, i, depth)
    if depth > MAX_DEPTH then Fail(i, "nested too deep") end
    local c = byte(s, i)
    if c == 34  then return ParseString(s, i) end
    if c == 123 then return ParseObject(s, i, depth + 1) end
    if c == 91  then return ParseArray(s, i, depth + 1) end
    if c == 116 and sub(s, i, i + 3) == "true"  then return true,  i + 4 end
    if c == 102 and sub(s, i, i + 4) == "false" then return false, i + 5 end
    if c == 110 and sub(s, i, i + 3) == "null"  then return nil,   i + 4 end
    local _, e = find(s, "^%-?%d+%.?%d*[eE]?[%-+]?%d*", i)
    local num = e and tonumber(sub(s, i, e))
    if num then return num, e + 1 end
    Fail(i, "unexpected character")
end

function Json.Decode(text)
    if type(text) ~= "string" then return nil, "not a string" end
    local ok, v, i = pcall(function()
        local val, pos = ParseValue(text, SkipWs(text, 1), 0)
        return val, SkipWs(text, pos)
    end)
    if not ok then
        local e = type(v) == "table" and v or { pos = 0, msg = tostring(v) }
        return nil, format("JSON error at %d: %s", e.pos or 0, e.msg or "?")
    end
    if i <= #text then return nil, format("JSON error at %d: text after the end", i) end
    return v
end

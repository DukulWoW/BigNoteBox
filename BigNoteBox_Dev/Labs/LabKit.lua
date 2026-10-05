-- BigNoteBox_Dev Labs/LabKit.lua
-- Pieces shared by the developer labs: Background Lab (Labs/BackgroundLab.lua)
-- and Icon Lab (Labs/IconLab.lua), ALL-126. File ID checks, atlas lookup, the
-- native size probe, listfile parsing and the small controls both panels use.
-- Dev tools only; nothing here is translated.

-- Queued for BigNoteBox's Core/DevTools.lua, which runs it once BigNoteBox
-- has loaded (this addon loads first, ARCH-04). The body is not indented.
BigNoteBoxDevLabs = BigNoteBoxDevLabs or {}
BigNoteBoxDevLabs[#BigNoteBoxDevLabs + 1] = function()

local BNB = BigNoteBox
if not BNB then return end

local K = {}
BNB._LabKit = K

-- A usable file ID: a whole, finite, positive number
function K.ValidID(id)
    return type(id) == "number" and id > 0 and id < 2^53 and id == math.floor(id)
end

-- An atlas name -> its file ID and atlas info, or nil. GetAtlasInfo gives the
-- file as an ID; a client that gives only a path goes through GetFileIDFromPath.
function K.ResolveAtlas(name)
    if not name or name == "" or not (C_Texture and C_Texture.GetAtlasInfo) then return nil end
    local ok, info = pcall(C_Texture.GetAtlasInfo, name)
    if not ok or type(info) ~= "table" then return nil end
    local id = info.file
    if type(id) ~= "number" and type(info.filename) == "string" and GetFileIDFromPath then
        local ok2, fid = pcall(GetFileIDFromPath, info.filename)
        if ok2 then id = fid end
    end
    if K.ValidID(id) then return id, info end
end

-- Texture coordinates x file size -> x, y, w, h in file pixels, or nil
function K.CropFromTexCoords(l, r, t, b, W, H)
    local function R(v) return math.floor(v + 0.5) end
    local cw, ch = R((r - l) * W), R((b - t) * H)
    if cw <= 0 or ch <= 0 then return nil end
    return R(l * W), R(t * H), cw, ch
end

-- A wow.export listfile line ("path;fileID", anything after the ID ignored)
-- or a bare file ID -> id, path (lower-case, forward slashes; "" when none)
function K.ParseListfileLine(line)
    line = (line or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local path, id = line:match("^([^;]+);%s*(%d+)")
    if not id then id = line:match("^(%d+)$") end
    id = tonumber(id)
    if not K.ValidID(id) then return nil end
    path = (path or ""):gsub("\\", "/"):lower():gsub("^%s+", ""):gsub("%s+$", "")
    return id, path
end

-- The key an entry is saved under: the atlas name, else the file's base name
function K.EntryKey(id, path, atlas)
    if atlas and atlas ~= "" then return atlas end
    local base = path ~= "" and path:match("([^/]+)$") or nil
    base = base and base:gsub("%.[^.]+$", "") or nil
    return (base and base ~= "") and base or ("file" .. id)
end

-- The atlas regions known for a file, from the full atlas table
-- (Labs/IconLabAtlas.lua, dev builds only), keyed by file ID or by lower-case
-- path without extension. Each region is { name, w, h, l, r, t, b }. nil
-- when none are known or the table is not loaded.
function K.AtlasRegions(id, path)
    local A = BNB.IconLabAtlas
    if not A then return nil end
    local p = (path or ""):gsub("\\", "/"):lower():gsub("%.[^./]+$", "")
    return A[id] or (p ~= "" and A[p]) or nil
end

-- A region rectangle cache for one lab: rect(fileID, reg, W, H) -> x, y, w,
-- h in file pixels and live (true when this client's own atlas lies on the
-- same file, which wins; false = the generated Retail coordinates), or nil
-- while the size is unknown. Cached per file and size: a sheet asks for
-- every region on each pointer move.
function K.NewRegionRects()
    local cache = {}   -- [file id] = { W, H, [name] = { x, y, w, h, live } or false }
    return function(fileID, reg, W, H)
        if not (W and H) then return nil end
        local c = cache[fileID]
        if not (c and c.W == W and c.H == H) then
            c = { W = W, H = H }
            cache[fileID] = c
        end
        local r = c[reg[1]]
        if r == nil then
            r = false
            local id, info = K.ResolveAtlas(reg[1])
            if id == fileID and info then
                local x, y, w, h = K.CropFromTexCoords(info.leftTexCoord, info.rightTexCoord,
                    info.topTexCoord, info.bottomTexCoord, W, H)
                if x then r = { x, y, w, h, true } end
            end
            if not r and reg[4] then
                local x, y, w, h = K.CropFromTexCoords(reg[4], reg[5], reg[6], reg[7], W, H)
                if x then r = { x, y, w, h, false } end
            end
            c[reg[1]] = r
        end
        if r then return r[1], r[2], r[3], r[4], r[5] end
    end
end

-- ── Native size probe ────────────────────────────────────────────────────────
-- A texture with one anchor and no size of its own takes the file's size once
-- it has loaded. Polled for up to 3 s. A fresh texture per probe: a reused one
-- reports the previous file's size until the new file loads (read 512x256 as
-- 256x256, ALL-120). One prober per lab; p.sizes[id] = { w, h }, or false
-- when the file did not load.
function K.NewProber()
    local p = { sizes = {} }
    function p:Probe(owner, id, onDone)
        if self.sizes[id] ~= nil then onDone(); return end
        if self.tex then self.tex:SetTexture(nil); self.tex:Hide() end
        local tex = owner:CreateTexture(nil, "BACKGROUND")
        self.tex = tex
        tex:SetAlpha(0)
        tex:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", -5000, 0)
        local ok = pcall(function() tex:SetTexture(id) end)
        tex._id = id
        local tries = 0
        local function Poll()
            -- Moved on before this one loaded: drop it, it re-probes when revisited
            if self.tex ~= tex then return end
            tries = tries + 1
            local w, h = tex:GetSize()
            if ok and w and w > 1 and h and h > 1 then
                self.sizes[id] = { math.floor(w + 0.5), math.floor(h + 0.5) }
                onDone()
            elseif tries >= 30 then
                self.sizes[id] = false
                onDone()
            else
                C_Timer.After(0.1, Poll)
            end
        end
        Poll()
    end
    return p
end

-- ── Controls ─────────────────────────────────────────────────────────────────
function K.SmallBtn(parent, text, w, onClick)
    local b = BNB.CreateButton(nil, parent, text, w, 20)
    b:SetScript("OnClick", onClick)
    return b
end

-- Gold ring shown around the selected button of a group
function K.Ring(parent)
    local r = BNB.CreateBackdropFrame("Frame", nil, parent)
    r:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    r:SetBackdropBorderColor(1, 0.82, 0, 1)
    r:EnableMouse(false)
    return r
end
function K.PutRing(r, btn)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", btn, "TOPLEFT", -2, 2)
    r:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 2, -2)
    r:SetFrameLevel(btn:GetFrameLevel() + 2)
    r:Show()
end

-- Text box on a dark backdrop (host.eb is the EditBox)
function K.PlainBox(parent, w, h)
    local host = BNB.CreateBackdropFrame("Frame", nil, parent)
    host:SetSize(w, h or 20)
    BNB.SetBackdropDark(host)
    local eb = CreateFrame("EditBox", nil, host)
    eb:SetAllPoints()
    eb:SetTextInsets(6, 6, 0, 0)
    eb:SetFontObject("GameFontHighlightSmall")
    eb:SetAutoFocus(false)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    host.eb = eb
    return host
end

-- Number box: onSet(number or nil) on Enter and on focus loss; Esc cancels
-- through onCancel (the lab's Refresh, which puts the saved value back)
function K.NumBox(parent, w, onSet, onCancel)
    local host = K.PlainBox(parent, w)
    local eb = host.eb
    eb:SetScript("OnEnterPressed", function(self) onSet(tonumber(self:GetText())); self:ClearFocus() end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); if onCancel then onCancel() end end)
    eb:SetScript("OnEditFocusLost", function(self) onSet(tonumber(self:GetText())) end)
    return host
end

-- Tab / Shift+Tab steps through hosts (NumBox / PlainBox) in list order,
-- wrapping at both ends. Leaving a box commits it through its focus-lost.
function K.TabChain(hosts)
    for i, host in ipairs(hosts) do
        host.eb:SetScript("OnTabPressed", function()
            local n = #hosts
            local j = IsShiftKeyDown() and ((i - 2) % n + 1) or (i % n + 1)
            local eb = hosts[j].eb
            eb:SetFocus()
            eb:HighlightText()
        end)
    end
end

end

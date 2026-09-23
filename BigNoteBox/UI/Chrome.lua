-- BigNoteBox UI/Chrome.lua -- Client-aware seating of the ButtonFrameTemplate chrome (FOR-05)
--
-- Every normal-mode window is a ButtonFrameTemplate whose content is anchored
-- to the frame edges through file-local PAD / TITLE_H / TOOLBAR_H constants,
-- all tuned against Retail's border art. Forever draws the same template with
-- different art, so its border lands somewhere else relative to that content.
--
-- Instead of adding an offset to every content anchor, SeatChrome moves the
-- template's own pieces (border, background, title, close button) by one
-- per-side delta, so the border sits where Retail's does and every content
-- anchor stays exactly as tuned. Retail's delta is zero: there the call only
-- takes a snapshot and touches no anchor.
--
-- Call BNB.SeatChrome(f) right after ButtonFrameTemplate_HidePortrait /
-- HideButtonBar / Inset:Hide and before any content is created. Whatever is a
-- child or region of f at that moment is template chrome; anything created
-- later is ours and is never moved.
--
-- Skin mode builds its own frames (BNB.CreateSkinFrame) and never gets here.
--
-- Dev tools, debug mode only (wired in Core/SlashCommands.lua):
--   /bnb chromeprobe       dump the template layout, to compare clients
--   /bnb chrome l t r b    re-seat every window live with a trial delta
--   /bnb chrome reset      back to the built-in delta
-- Live, not saved: Forever does not keep SavedVariables yet (FOR-10).
--------------------------------------------------------------------------------

local BNB = BigNoteBox

-- Pixels each side of the chrome moves: positive = outward (the frame looks
-- bigger), negative = inward. Measured, never guessed by eye on Forever: take
-- the numbers from /bnb chromeprobe on both clients, confirm with /bnb chrome.
-- Forever, measured 2026-09-23 (_work/forever-chrome-probe.md): same frame on both
-- clients, screenshots at 1.5 px per UI unit, inner edge of the border art vs
-- Retail's: left 5px, top 4px (below the title separator), right 6.5px,
-- bottom 4px further in. /1.5 and rounded: 3.3, 2.7, 4.3, 2.7.
local FOREVER_DELTA = { l = 3, t = 3, r = 4, b = 3 }

local function DefaultDelta()
    local d = BNB.IsForever and FOREVER_DELTA or { l = 0, t = 0, r = 0, b = 0 }
    return { l = d.l, t = d.t, r = d.r, b = d.b }
end

BNB.CHROME_DELTA = DefaultDelta()

-- frame -> list of { obj, pts }, the template's own anchors as first laid out
local _seated = {}

local function IsZero(d)
    return d.l == 0 and d.t == 0 and d.r == 0 and d.b == 0
end

-- How far a point on the frame moves when each edge moves by d
local function EdgeShift(relPoint, d)
    local dx, dy
    relPoint = relPoint or "CENTER"
    if relPoint:find("LEFT") then dx = -d.l
    elseif relPoint:find("RIGHT") then dx = d.r
    else dx = (d.r - d.l) / 2 end
    if relPoint:find("TOP") then dy = d.t
    elseif relPoint:find("BOTTOM") then dy = -d.b
    else dy = (d.t - d.b) / 2 end
    return dx, dy
end

local function Snapshot(f)
    local pieces = {}
    local function add(obj)
        local pts, onFrame = {}, false
        for i = 1, obj:GetNumPoints() do
            local p, rel, rp, x, y = obj:GetPoint(i)
            pts[#pts + 1] = { p, rel, rp, x or 0, y or 0 }
            if rel == f then onFrame = true end
        end
        -- Pieces hung off another piece (NineSlice corners, title text) follow
        -- their parent piece; only the ones pinned to the frame need moving
        if onFrame then pieces[#pieces + 1] = { obj = obj, pts = pts } end
    end
    for _, r in ipairs({ f:GetRegions() })  do add(r) end
    for _, c in ipairs({ f:GetChildren() }) do add(c) end
    return pieces
end

local function Apply(f, d)
    for _, pc in ipairs(_seated[f]) do
        local o = pc.obj
        o:ClearAllPoints()
        for _, a in ipairs(pc.pts) do
            local x, y = a[4], a[5]
            if a[2] == f then
                local dx, dy = EdgeShift(a[3], d)
                x, y = x + dx, y + dy
            end
            o:SetPoint(a[1], a[2], a[3], x, y)
        end
    end
end

-- Forever's own windows draw wood grain (atlas UI-Character-Info-General-BG,
-- found on CharacterFrameLeftPaneHost) instead of the template's grey rock.
-- That atlas is one fixed pane and does not tile, so this is our own 512x512
-- tileable version of it. Retail keeps the template's Bg untouched.
local FOREVER_BG = "Interface\\AddOns\\BigNoteBox\\Assets\\UI\\ui-bg-forever"

local function SkinBg(f)
    local bg = f.Bg
    if not bg then return end
    bg:SetTexture(FOREVER_BG, "REPEAT", "REPEAT")
    bg:SetHorizTile(true)
    bg:SetVertTile(true)
end

function BNB.SeatChrome(f)
    if not f or _seated[f] then return end
    if BNB.IsForever then pcall(SkinBg, f) end
    local ok, pieces = pcall(Snapshot, f)
    if not ok then return end
    _seated[f] = pieces
    if not IsZero(BNB.CHROME_DELTA) then pcall(Apply, f, BNB.CHROME_DELTA) end
end

-- Re-seat every window built so far. d = nil restores the built-in delta.
function BNB.SetChromeDelta(d)
    BNB.CHROME_DELTA = d or DefaultDelta()
    local n = 0
    for f in pairs(_seated) do
        if pcall(Apply, f, BNB.CHROME_DELTA) then n = n + 1 end
    end
    return n
end

--------------------------------------------------------------------------------
-- PROBE  (/bnb chromeprobe)
-- Builds a throwaway ButtonFrameTemplate exactly the way the windows do,
-- unseated, and dumps every piece: type, texture, rect against the frame
-- edges and raw anchors. Run on Retail and on Forever; the difference between
-- the two dumps is the delta.
--------------------------------------------------------------------------------
local function KeyOf(obj, owner)
    if not owner then return nil end
    for k, v in pairs(owner) do
        if v == obj and type(k) == "string" then return k end
    end
end

local function NameOf(obj, f)
    if obj == nil then return "nil" end
    if obj == f then return "f" end
    if obj == UIParent then return "UIParent" end
    local parent = obj.GetParent and obj:GetParent()
    local key = KeyOf(obj, parent)
    if key then
        if parent == f then return key end
        return NameOf(parent, f) .. "." .. key
    end
    local n = obj.GetName and obj:GetName()
    if n then return n end
    return (obj.GetObjectType and obj:GetObjectType() or "?") .. "@" .. NameOf(parent, f)
end

-- Edge distances from the frame's own edges, in the frame's scale.
-- Positive = inside the frame, negative = sticks out past it.
local function RectOf(obj, f)
    local l, b, w, h = obj:GetRect()
    local fl, fb, fw, fh = f:GetRect()
    if not (l and fl) then return "rect=?" end
    local fs = f:GetEffectiveScale() or 1
    local s  = (obj.GetEffectiveScale and obj:GetEffectiveScale() or fs) / fs
    l, b, w, h = l * s, b * s, w * s, h * s
    return string.format("in L%.1f R%.1f T%.1f B%.1f  size %.1fx%.1f",
        l - fl, (fl + fw) - (l + w), (fb + fh) - (b + h), b - fb, w, h)
end

local function TexOf(obj)
    if obj:GetObjectType() ~= "Texture" then return "" end
    local atlas = obj.GetAtlas and obj:GetAtlas()
    if atlas and atlas ~= "" then return "  atlas=" .. atlas end
    local tex = obj.GetTexture and obj:GetTexture()
    return tex and ("  tex=" .. tostring(tex)) or ""
end

local function Dump(f)
    local out = {}
    local function line(s) out[#out + 1] = s end

    local ver, build, date, iface = GetBuildInfo()
    line(string.format("BNB chrome probe  %s  build %s (%s)  interface %s  IsForever=%s",
        tostring(BNB.ADDON_VERSION), tostring(build), tostring(date),
        tostring(iface), tostring(BNB.IsForever)))
    line(string.format("client %s  UIParent scale %.4f  frame scale %.4f  frame %.1fx%.1f",
        tostring(ver), UIParent:GetEffectiveScale(), f:GetEffectiveScale(),
        f:GetWidth(), f:GetHeight()))
    if f.NineSlice then
        line("NineSlice layoutType=" .. tostring(f.NineSlice.layoutType)
            .. "  layoutTextureKit=" .. tostring(f.NineSlice.layoutTextureKit))
    end
    line("Rect: 'in' = distance inside each frame edge (negative = outside the frame)")
    line("")

    local function walk(obj, depth)
        local ok = pcall(function()
            local pts = {}
            for i = 1, obj:GetNumPoints() do
                local p, rel, rp, x, y = obj:GetPoint(i)
                pts[#pts + 1] = string.format("%s>%s.%s(%s,%s)", p, NameOf(rel, f),
                    tostring(rp), tostring(x), tostring(y))
            end
            line(string.format("%s%s [%s%s]  %s%s",
                string.rep("  ", depth), NameOf(obj, f), obj:GetObjectType(),
                obj:IsShown() and "" or ", hidden", RectOf(obj, f), TexOf(obj)))
            if #pts > 0 then
                line(string.rep("  ", depth + 2) .. table.concat(pts, "  "))
            end
        end)
        if not ok then line(string.rep("  ", depth) .. "(unreadable piece)") end
        if depth < 2 and obj.GetRegions then
            for _, r in ipairs({ obj:GetRegions() })  do walk(r, depth + 1) end
            for _, c in ipairs({ obj:GetChildren() }) do walk(c, depth + 1) end
        end
    end
    for _, r in ipairs({ f:GetRegions() })  do walk(r, 0) end
    for _, c in ipairs({ f:GetChildren() }) do walk(c, 0) end
    return table.concat(out, "\n")
end

function BNB.ChromeProbe()
    local f = BNB._chromeProbeFrame
    if not f then
        f = CreateFrame("Frame", "BNBChromeProbeFrame", UIParent, "ButtonFrameTemplate")
        f:SetSize(400, 300)
        f:SetPoint("CENTER")
        ButtonFrameTemplate_HidePortrait(f)
        ButtonFrameTemplate_HideButtonBar(f)
        if f.Inset then f.Inset:Hide() end
        f:SetTitle("BNB chrome probe")
        BNB._chromeProbeFrame = f
    end
    f:Show()
    -- One layout pass before reading rects; a just-shown frame reports 0
    C_Timer.After(0.1, function()
        local ok, text = pcall(Dump, f)
        if not ok then
            BNB:Print("|cffff6666Chrome probe failed:|r " .. tostring(text))
            return
        end
        local n = select(2, text:gsub("\n", "\n")) + 1
        BNB:Print(string.format("|cff88bbffChrome probe:|r %d lines ready. Press Ctrl+C to copy, then close the probe window.", n))
        BNB.ShowClipboardHint(text, f)
    end)
end

-- BigNoteBox Features/VendorNote.lua
-- The vendor list (ALL-644, Dukul 2026-11-01): a "createnote" button on the
-- vendor window writes everything the vendor sells into the vendor's own NPC
-- note (the note F6 makes, found by creature id, made if missing), one line
-- per item (link, stack, price, limited stock), and puts every item in that
-- note's Reference Box past the box limit. A later click replaces the list.
-- The note gets the tags "Vendor" and, while anything is limited, "Limited
-- stock". The Oracle then finds the vendor by an item name.
--
-- Read on the click, while the window is open: GetMerchantNumItems counts
-- every item, whatever page the window shows. Retail / Forever filter the list
-- by class: the filter is set to All for the read and put back at once.
-- Retail / Forever: C_MerchantFrame.GetItemInfo; Classic: GetMerchantItemInfo.

local BNB = BigNoteBox
local L   = BNB.L

BNB.VendorNote = BNB.VendorNote or {}
local VN = BNB.VendorNote

local BTN_SZ     = 24
local COIN_ICON  = "{icon:Interface\\MoneyFrame\\UI-%sIcon:13}"   -- as QuickNote's
local LOAD_TRIES = 6     -- uncached item links: 6 x 0.5 s, then the merchant's name
local LOAD_STEP  = 0.5

local function DB() return BigNoteBoxDB end
-- A failed read / write: said in chat in debug mode only
local function Fail(where, err)
    if BNB.IsDebugMode and BNB.IsDebugMode() then BNB:Print("VendorNote " .. where .. ": " .. tostring(err)) end
end
-- Note Capture on, and Player & NPC Notes on (the list goes into the NPC note)
local function IsEnabled()
    return DB() and DB().quickNoteEnabled ~= false and BNB.UnitNotesEnabled and BNB.UnitNotesEnabled()
end

-- 1g 20s 5c; rich: the coin pictures after each number
local function MoneyText(copper, rich)
    local out = {}
    local function Add(n, sfx, coin)
        if n > 0 then out[#out + 1] = rich and (n .. string.format(COIN_ICON, coin)) or (n .. sfx) end
    end
    Add(math.floor(copper / 10000), "g", "Gold")
    Add(math.floor((copper % 10000) / 100), "s", "Silver")
    Add(copper % 100, "c", "Copper")
    return table.concat(out, " ")
end

-- One merchant slot: { id, link, name, texture, price, stack, limited, costs }
local function ReadSlot(i)
    local name, texture, price, stack, numAvailable, extended
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local info = C_MerchantFrame.GetItemInfo(i)
        if type(info) == "table" then
            name, texture, price = info.name, info.texture, info.price
            stack, numAvailable, extended = info.stackCount, info.numAvailable, info.hasExtendedCost
        end
    elseif GetMerchantItemInfo then
        -- name, texture, price, quantity, numAvailable, isPurchasable, isUsable, extendedCost
        local r = { GetMerchantItemInfo(i) }
        name, texture, price, stack, numAvailable, extended = r[1], r[2], r[3], r[4], r[5], r[8]
    end
    local id = GetMerchantItemID and tonumber(GetMerchantItemID(i))
    if not id then return nil end
    local e = {
        id = id, name = name, texture = texture, price = tonumber(price) or 0,
        stack = tonumber(stack) or 1, link = GetMerchantItemLink and GetMerchantItemLink(i) or nil,
        -- numAvailable -1 = no limit
        limited = tonumber(numAvailable) ~= nil and numAvailable >= 0,
    }
    if extended and GetMerchantItemCostInfo then
        local n = tonumber((GetMerchantItemCostInfo(i))) or 0
        for c = 1, n do
            local tex, value, link, cname = GetMerchantItemCostItem(i, c)
            if value and value > 0 then
                e.costs = e.costs or {}
                e.costs[#e.costs + 1] = { texture = tex, value = value, link = link, name = cname }
            end
        end
    end
    return e
end

-- Everything the vendor sells, in its order (Retail / Forever: with the class
-- filter on All for the read, then put back)
local function ReadMerchant()
    local list = {}
    local prev, setAll
    if GetMerchantFilter and SetMerchantFilter and LE_LOOT_FILTER_ALL then
        prev = GetMerchantFilter()
        if prev ~= LE_LOOT_FILTER_ALL then setAll = pcall(SetMerchantFilter, LE_LOOT_FILTER_ALL) end
    end
    local ok, err = pcall(function()
        for i = 1, (GetMerchantNumItems and GetMerchantNumItems() or 0) do
            local e = ReadSlot(i)
            if e then list[#list + 1] = e end
        end
    end)
    if setAll then pcall(SetMerchantFilter, prev) end
    if not ok then Fail("read", err) end
    return list
end

-- An item link that is not cached yet: the game's link once loaded, else one
-- made from the merchant's name (hover still shows the item)
local function FillLink(e)
    if e.link then return true end
    local link = select(2, C_Item.GetItemInfo(e.id))
    if link then e.link = link; return true end
    return false
end
local function FallbackLink(e)
    if e.link then return end
    local name = e.name or (C_Item.GetItemNameByID and C_Item.GetItemNameByID(e.id))
    e.link = "|cffffffff|Hitem:" .. e.id .. "|h[" .. (name or ("Item " .. e.id)) .. "]|h|r"
end

local function ItemLine(e, rich)
    local parts = {}
    local head = e.link
    if rich and e.texture then head = "{icon:" .. tostring(e.texture) .. ":16} " .. head end
    if e.stack > 1 then head = head .. " x" .. e.stack end
    parts[#parts + 1] = head
    local cost = {}
    if e.price > 0 then cost[#cost + 1] = MoneyText(e.price, rich) end
    for _, c in ipairs(e.costs or {}) do
        local what = c.link or c.name or "?"
        if rich and c.texture then what = "{icon:" .. tostring(c.texture) .. ":13} " .. what end
        cost[#cost + 1] = c.value .. " " .. what
    end
    if #cost > 0 then parts[#parts + 1] = table.concat(cost, " + ") end
    local line = table.concat(parts, " - ")
    if e.limited then line = line .. " " .. L["VENDOR_LIMITED"] end
    return line
end

-- The header line of a vendor list, as a pattern that also finds an older
-- list (any date): the format with its %s as ".-"
local function HeaderPattern(rich)
    local fmt = L["VENDOR_HDR_FMT"]
    local a, b = fmt:find("%s", 1, true)
    local function Esc(t) return (t:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")) end
    local pat = a and (Esc(fmt:sub(1, a - 1)) .. ".-" .. Esc(fmt:sub(b + 1))) or Esc(fmt)
    return rich and ("^{h3}" .. pat .. "{/h3}%s*$") or ("^%-%-%-%-%- " .. pat .. " %-%-%-%-%-%s*$")
end

-- The player's words are never touched (Dukul, 2026-11-01: "a safety that
-- they don't remove what people write ... like we have on Player notes"):
-- the note keeps the fingerprint of the exact list text last written
-- (note.vendorFp, UN.Fingerprint as the player notes' unitAuto.fp). A later
-- list replaces only lines whose text still has that fingerprint; anything
-- around them, or an edited list, stays. Returns first, last line or nil.
local function FindOwnList(lines, pat, fp)
    local Fp = BNB.UnitNotes and BNB.UnitNotes.Fingerprint
    if not (fp and Fp) then return nil end
    for i, line in ipairs(lines) do
        if line:find(pat) then
            -- UN.Fingerprint fed line by line, "\n" between: one pass per header
            local h = 5381
            for k = i, #lines do
                local l = lines[k]
                for b = 1, #l do h = (h * 33 + l:byte(b)) % 4294967296 end
                if tostring(h) == fp and Fp(table.concat(lines, "\n", i, k)) == fp then return i, k end
                h = (h * 33 + 10) % 4294967296
            end
        end
    end
end

-- The body with the vendor list in it, and whether an edited (or older) list
-- was left as it is. Rich: above the player's Notes part, which stays last
-- (TN.AddAboveNotes): our unedited earlier list is replaced where it stands,
-- or, below Notes, taken out with the divider over it and put above. Plain
-- (no Notes heading): replaced where it stands, else at the bottom.
local function BodyWithList(body, section, rich, fp)
    body = (body or ""):gsub("\r", "")
    local TN = BNB.TargetNote
    local lines, pat = {}, HeaderPattern(rich)
    for line in (body .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
    local from, to = FindOwnList(lines, pat, fp)
    if not from then
        local kept = false
        for _, line in ipairs(lines) do if line:find(pat) then kept = true; break end end
        if rich then return TN.AddAboveNotes(body, section), kept end
        body = body:gsub("%s+$", "")
        return (body ~= "" and (body .. "\n\n") or "") .. section, kept
    end
    -- Rich: replaced where it stands while above the Notes heading (text the
    -- player wrote around it keeps its place); one below Notes moves up
    local below = false
    if rich then
        local notesHdr = "{h3}" .. L["TGT_HDR_NOTES"] .. "{/h3}"
        for i = 1, from - 1 do
            if lines[i]:gsub("%s+$", "") == notesHdr then below = true; break end
        end
    end
    local cut = from
    if below then
        local j = from - 1
        while j > 0 and lines[j]:match("^%s*$") do j = j - 1 end
        if j > 0 and lines[j]:find("^{div:") then cut = j end
    end
    local before = table.concat(lines, "\n", 1, cut - 1):gsub("%s+$", "")
    local after  = to < #lines and table.concat(lines, "\n", to + 1, #lines) or ""
    after = after:gsub("^%s+", ""):gsub("%s+$", "")
    if below then
        local rest = before .. ((before ~= "" and after ~= "") and "\n\n" or "") .. after
        return TN.AddAboveNotes(rest, section), false
    end
    if before ~= "" then before = before .. "\n\n" end
    return before .. section .. (after ~= "" and ("\n\n" .. after) or ""), false
end

local function Section(list, rich)
    local hdr = string.format(L["VENDOR_HDR_FMT"], BNB.FmtDate())
    local out = {}
    for i, e in ipairs(list) do out[i] = ItemLine(e, rich) end
    if rich then
        -- One {p} block: the lines belong together (one <P>, <BR/> between)
        return "{h3}" .. hdr .. "{/h3}\n\n{p}" .. table.concat(out, "\n") .. "{/p}"
    end
    return "----- " .. hdr .. " -----\n" .. table.concat(out, "\n")
end

-- note.tags with "Vendor" in, and "Limited stock" in while anything is
local function VendorTags(tags, limited)
    local out, tagV, tagL = {}, L["VENDOR_TAG"], L["VENDOR_TAG_LIMITED"]
    local hasV = false
    for _, t in ipairs(tags or {}) do
        local low = t:lower()
        if low == tagV:lower() then hasV = true; out[#out + 1] = t
        elseif low ~= tagL:lower() then out[#out + 1] = t end
    end
    if not hasV then out[#out + 1] = tagV end
    if limited then out[#out + 1] = tagL end
    return out
end

-- id: the NPC note, found or made on the click (the "npc" unit is gone once
-- the window closes). Read again here: a delayed write sees the latest body
local function Write(list, id)
    local note = BNB.GetNote(id)
    if not note then return end
    for _, e in ipairs(list) do FallbackLink(e) end
    local rich, limited, ids = note.richMode and true or false, false, {}
    for i, e in ipairs(list) do
        ids[i] = e.id
        if e.limited then limited = true end
    end
    local section = Section(list, rich)
    local body, kept = BodyWithList(note.body, section, rich, note.vendorFp)
    BNB.UpdateNote(id, {
        body = body,
        tags = VendorTags(note.tags, limited),
        vendorFp = BNB.UnitNotes.Fingerprint(section),
    })
    if BNB.RBSetVendorItems then BNB.RBSetVendorItems(id, ids) end
    if BNB.UnitNotes and BNB.UnitNotes.RefreshNoteViews then BNB.UnitNotes.RefreshNoteViews(id) end
    if BNB.RefreshNoteList then BNB.RefreshNoteList() end
    BNB:Print(string.format(L["VENDOR_SAVED_FMT"], #list, note.title or "?"))
    if kept then BNB:Print(L["VENDOR_KEPT_EDITED"]) end
    -- Note Capture set to "open": show the note, as dialogue capture does
    if DB().quickNoteAction == "open" then
        if BNB.mainFrame and not BNB.mainFrame:IsShown() then BNB.mainFrame:Show() end
        if BNB._currentNoteID ~= id and BNB.SelectNote then
            if BNB.SaveCurrentNote then BNB.SaveCurrentNote() end
            BNB.SelectNote(id)
        end
    end
end

-- The click: read the vendor and find or make its note now (the window is
-- open), write once every link is known or after LOAD_TRIES.
local _busy = false
function VN.Capture()
    if _busy or not IsEnabled() then return end
    local list = ReadMerchant()
    if #list == 0 then BNB:Print(L["VENDOR_EMPTY"]); return end
    local TN = BNB.TargetNote
    local id, note, made
    if TN and TN.NpcNoteForTalk then id, note, made = TN.NpcNoteForTalk() end
    if not id then BNB:Print(L["VENDOR_NO_NPC"]); return end
    -- A locked note stays as it is; one made just now is the vendor's list
    if not made and BNB.IsNoteLockedInEditor and BNB.IsNoteLockedInEditor(id) then
        BNB:Print(string.format(L["VENDOR_LOCKED_FMT"], note.title or "?"))
        return
    end
    local function AllLinks()
        local all = true
        for _, e in ipairs(list) do if not FillLink(e) then all = false end end
        return all
    end
    if AllLinks() then Write(list, id); return end
    for _, e in ipairs(list) do
        if not e.link and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, e.id) end
    end
    _busy = true
    local tries = 0
    local function Step()
        tries = tries + 1
        if AllLinks() or tries >= LOAD_TRIES then
            _busy = false
            local ok, err = pcall(Write, list, id)
            if not ok then Fail("write", err) end
            return
        end
        C_Timer.After(LOAD_STEP, Step)
    end
    C_Timer.After(LOAD_STEP, Step)
end

-- The button, left of the window's close X (every client has
-- MerchantFrameCloseButton, the API dumps)
local _btn
local function BuildButton()
    if _btn or not MerchantFrame then return end
    _btn = BNB.CreateIconButton(MerchantFrame, BTN_SZ, "createnote", { name = "BNBVendorNoteBtn", skin = false,
        tip = L["VENDOR_BTN_TIP1"], tipSub = L["VENDOR_BTN_TIP2"], tipAnchor = "ANCHOR_BOTTOMRIGHT",
        onClick = function()
            local ok, err = pcall(VN.Capture)
            if not ok then _busy = false; Fail("click", err) end
        end })
    local close = MerchantFrameCloseButton or MerchantFrame.CloseButton
    if close then _btn:SetPoint("RIGHT", close, "LEFT", -2, 0)
    else _btn:SetPoint("TOPRIGHT", MerchantFrame, "TOPRIGHT", -30, 0) end
    _btn:SetFrameStrata("HIGH")
    _btn:SetFrameLevel((MerchantFrame:GetFrameLevel() or 0) + 10)
    -- Module off: no button, rather than one that does nothing (as the quest one)
    _btn:SetShown(IsEnabled())
    MerchantFrame:HookScript("OnShow", function() _btn:SetShown(IsEnabled()) end)
end

function VN.Init()
    pcall(BuildButton)
end

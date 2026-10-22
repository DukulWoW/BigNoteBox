-- BigNoteBox UI/Config/Accessibility.lua - Settings > Modules > Accessibility (ALL-548)
--
-- A settings page, not a module switch (Dukul 2026-10-22): no page.enableCb and
-- no setup-wizard entry, so it is always there and never moves the Minimal /
-- Full badges. First part: Motion, the sticky Hide all / Show all animation
-- (ALL-501, UI/StickyNote.lua). Later: Reduce motion, contrast, colours (ALL-548).

local BNB = BigNoteBox
local L   = BNB.L

local K = BNB._ConfigKit
local CONTENT_W, ROW_GAP, SLIDER_H = K.CONTENT_W, K.ROW_GAP, K.SLIDER_H
local AddHeader, AddCheck = K.AddHeader, K.AddCheck

function K.BuildAccessibilityPage(sf, ct, y, page)
    local db = BigNoteBoxDB
    local D  = BNB.DEFAULTS

    y = AddHeader(ct, y, L["CFG_ACC_HDR_MOTION"])

    local sliders = {}
    local function Sync()
        local on = db.stickyAnim ~= false
        for _, s in ipairs(sliders) do s:SetEnabled(on) end
    end

    local cb
    y, cb = AddCheck(ct, y, L["CFG_ACC_STICKY_ANIM"],
        function() return db.stickyAnim ~= false end,
        function(v) db.stickyAnim = v and true or false; Sync() end,
        L["CFG_ACC_STICKY_ANIM_TIP"])
    K.ReadOnShow(cb, function() return db.stickyAnim ~= false end)

    local function Slider(label, key, mn, mx, step, fmt, tip)
        local s = BNB.CreateStackedSlider(ct, CONTENT_W - 14, {
            label = label, min = mn, max = mx, step = step,
            value = db[key] or D[key], default = D[key],
            fmt = fmt,
            onChange = function(v) db[key] = v end,
            tip = tip,
        })
        s:SetPoint("TOPLEFT", ct, "TOPLEFT", 14, y)
        y = y - (SLIDER_H + ROW_GAP)
        sliders[#sliders + 1] = s
        return s
    end
    local function Secs(v) return string.format(L["CFG_ACC_SECS_FMT"], v) end
    Slider(L["CFG_ACC_STICKY_TIME"], "stickyAnimTime", 0.05, 1.0, 0.05, Secs,
        { L["CFG_ACC_STICKY_TIME_TIP"] })
    Slider(L["CFG_ACC_STICKY_SCALE"], "stickyAnimScale", 1.0, 2.0, 0.05,
        function(v) return string.format(L["CFG_ACC_SCALE_FMT"], v) end,
        { L["CFG_ACC_STICKY_SCALE_TIP"] })
    Slider(L["CFG_ACC_STICKY_TEXT"], "stickyAnimText", 0, 0.5, 0.01, Secs,
        { L["CFG_ACC_STICKY_TEXT_TIP"] })
    Sync()

    sf:FinaliseHeight(math.abs(y) + 12)
end

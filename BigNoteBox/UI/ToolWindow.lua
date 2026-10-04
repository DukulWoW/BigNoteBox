-- BigNoteBox UI/ToolWindow.lua
-- Shared shell for every BNB window that is not the main window, the Focus
-- editor or the rich preview (ALL-65.8, CMP-02). Builds the chrome once for
-- both modes: ButtonFrameTemplate in normal mode (seated for Forever, with the
-- Forever glow), a skin frame with its own title strip in skin mode. Either
-- way the window gets the same title, close button and drag (jump-free,
-- BNB.StartDragMoving), and optionally a footer divider and two footer
-- buttons; the caller only builds its content. The window is returned hidden.
--
-- Public API:
--   BNB.CreateToolWindow(opts) -> frame, leftButton, rightButton
--     opts.name         global frame name
--     opts.w, opts.h    size (may be set again later, once the content is laid out)
--     opts.title        title text
--     opts.pad          side padding (footer divider and buttons)
--     opts.cw           content width (the two buttons share it)
--     opts.footH        footer height; the divider sits on its top edge
--                       (nil = no divider)
--     opts.btn1/btn2    footer button labels, left and right (nil = no footer
--                       buttons; both are returned nil)
--     opts.onClose      close button handler (nil = hide the window)
--     opts.onDragStart  optional, runs after the drag starts (frame or title strip)
--     opts.onDragStop   optional, runs after the drag ends
--     opts.onHide       optional, hooked to OnHide
--     opts.strata       frame strata, nil = "DIALOG"
--     opts.toplevel     SetToplevel(true)
--     opts.escClose     add to UISpecialFrames
--     opts.keyEsc       ESC closes it through its own key handler
--                       (BNB.AttachEscClose with onClose), for windows that
--                       must close on ESC where UISpecialFrames does not reach
--   frame:SetWindowTitle(text)   works in both modes
--   frame._isSkin                true when built as a skin frame
--   BNB.TOOL_SKIN_TITLE_H        the skin title strip height
--   BNB.PlaceBeside(f, anchor, w)

local BNB = BigNoteBox
if not BNB then return end

local SK_TITLE_H = 28   -- skin title strip height
BNB.TOOL_SKIN_TITLE_H = SK_TITLE_H

local function DragStart(f, o)
    BNB.StartDragMoving(f)
    if o.onDragStart then o.onDragStart() end
end
local function DragStop(f, o)
    BNB.StopDragMoving(f)
    if o.onDragStop then o.onDragStop() end
end

local function BuildNormal(o)
    local f = CreateFrame("Frame", o.name, UIParent, "ButtonFrameTemplate")
    f:SetSize(o.w, o.h)   -- before SeatChrome, as every other window does
    ButtonFrameTemplate_HidePortrait(f)
    ButtonFrameTemplate_HideButtonBar(f)
    if f.Inset then f.Inset:Hide() end
    BNB.SeatChrome(f)   -- FOR-05: Forever border offset (UI/Chrome.lua)
    f._forGlow = BNB.AddForeverGlow(f, f.Bg)   -- Forever: glow over the wood grain
    f:SetTitle(o.title)
    if f.CloseButton then
        f.CloseButton:SetScript("OnClick", function() o.onClose() end)
    end
    function f:SetWindowTitle(text) self:SetTitle(text) end

    if o.footH then
        local footerDiv = f:CreateTexture(nil, "ARTWORK")
        footerDiv:SetHeight(1)
        footerDiv:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  o.pad, o.footH)
        footerDiv:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -o.pad, o.footH)
        footerDiv:SetColorTexture(0.28, 0.28, 0.30, 1)
    end
    return f
end

local function BuildSkin(o)
    local f = BNB.CreateSkinFrame(UIParent, false, o.name, false)
    _G[o.name] = f
    f:SetSize(o.w, o.h)
    f._isSkin = true

    local titleBar = BNB.CreateSkinStrip(f, true, false)
    titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    titleBar:SetHeight(SK_TITLE_H)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() DragStart(f, o) end)
    titleBar:SetScript("OnDragStop",  function() DragStop(f, o) end)

    local titleLbl = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleLbl:SetPoint("CENTER", titleBar, "CENTER", -15, 0)
    titleLbl:SetTextColor(1, 0.82, 0)
    titleLbl:SetText(o.title)
    function f:SetWindowTitle(text) titleLbl:SetText(text) end

    local closeBtn = BNB.CreateSkinCloseButton(titleBar, function() o.onClose() end)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -3, 0)

    if o.footH then
        local footerHost = CreateFrame("Frame", nil, f)
        footerHost:SetHeight(1)
        footerHost:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  o.pad, o.footH)
        footerHost:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -o.pad, o.footH)
        local footerDiv = BNB.CreateDivider(footerHost, "HORIZONTAL", 0.28, 0.28, 0.30, 1)
        footerDiv:SetPoint("TOPLEFT",  footerHost, "TOPLEFT",  0, 0)
        footerDiv:SetPoint("TOPRIGHT", footerHost, "TOPRIGHT", 0, 0)
    end

    f:HookScript("OnShow", function()
        if BNB.ApplyMainWindowSkin then BNB.ApplyMainWindowSkin() end
    end)
    return f
end

function BNB.CreateToolWindow(o)
    local f
    -- The close handlers are built before the window exists: look it up then
    local userClose = o.onClose
    o.onClose = function() if userClose then userClose() else f:Hide() end end
    if BigNoteBoxDB and BigNoteBoxDB.skinMode then f = BuildSkin(o)
    else f = BuildNormal(o) end

    f:SetFrameStrata(o.strata or "DIALOG")
    if o.toplevel then f:SetToplevel(true) end
    f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) DragStart(self, o) end)
    f:SetScript("OnDragStop",  function(self) DragStop(self, o) end)
    f:SetAlpha(BNB.WindowAlpha(f))
    if o.onHide then f:HookScript("OnHide", o.onHide) end

    local btn1, btn2
    if o.btn1 then
        local bW = math.floor(o.cw / 2) - 4
        btn1 = BNB.CreateButton(nil, f, o.btn1, bW, 26)
        btn1:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", o.pad, 6)
        btn2 = BNB.CreateButton(nil, f, o.btn2, bW, 26)
        btn2:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", o.pad + bW + 8, 6)
    end

    f:Hide()
    if o.escClose then tinsert(UISpecialFrames, o.name) end
    if o.keyEsc then BNB.AttachEscClose(f, o.onClose) end
    return f, btn1, btn2
end

-- Place f (w wide) beside anchor: to its right when it fits on screen,
-- otherwise to its left. No anchor: slightly above screen centre.
function BNB.PlaceBeside(f, anchor, w)
    f:ClearAllPoints()
    if anchor and anchor.GetWidth then
        local cx = anchor:GetCenter()
        local aw = anchor:GetWidth()
        if ((cx or 0) + (aw or 0) / 2 + 8 + w) <= UIParent:GetWidth() then
            f:SetPoint("LEFT", anchor, "RIGHT", 8, 0)
        else
            f:SetPoint("RIGHT", anchor, "LEFT", -8, 0)
        end
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    end
end

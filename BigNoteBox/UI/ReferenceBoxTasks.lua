-- BigNoteBox UI/ReferenceBoxTasks.lua - Reference box task panel
-- Split out of ReferenceBox.lua (ALL-65.10e); built by its two frame builders.
-- Loads after ReferenceBox.lua: layout constants, helpers and the live frame /
-- note / mode values come through BNB._RefBoxKit, and this file hands its
-- entry points back through the same table.
--
-- Public API:
--   BNB.FocusTaskEditBox(taskID)
--   BNB.ShowTaskContextMenu(anchor, noteID, taskID)

local BNB = BigNoteBox
local L   = BNB.L

local K = BNB._RefBoxKit
local RBW, TITLE_H, SK_RB_TITLE_H, PAD, SCROLL_PAD = K.RBW, K.TITLE_H, K.SK_RB_TITLE_H, K.PAD, K.SCROLL_PAD
local MANUAL_H, MANUAL_GAP, COUNT_H, BOTTOM_PAD   = K.MANUAL_H, K.MANUAL_GAP, K.COUNT_H, K.BOTTOM_PAD
local ASSETS = K.ASSETS
-- Owned and reassigned by ReferenceBox.lua: always read through the getter,
-- never kept in a local, since the closures here run long after they are built.
local RBFrame, NoteID, RBMode = K.RBFrame, K.NoteID, K.RBMode
local IsInspectNote, OnModeClick = K.IsInspectNote, K.OnModeClick
local UpdateModeStrip, UpdateModelViewer, UpdateDynamicTitle =
    K.UpdateModeStrip, K.UpdateModelViewer, K.UpdateDynamicTitle

-- ── Task panel constants ──────────────────────────────────────────────────────
local TASK_HDR_H            = 24     -- height of the task panel header row
local TASK_SPLIT_MIN_PX     = 60     -- minimum px for either task or attachment pane
local TASK_CB_SCALE         = 0.65   -- UICheckButtonTemplate scale ~17px
local ADD_TASKS_H           = 40     -- reserved strip height for the wide Add Tasks button
local TASK_FOOTER_H         = 26     -- height of Clear/Delete footer strip

-- Returns { rowH, subRowH, gap } based on BigNoteBoxDB.taskSpacing.
local function GetTaskSpacing()
    local s = BigNoteBoxDB and BigNoteBoxDB.taskSpacing or "normal"
    if s == "compact"  then return 18, 16, 1 end
    if s == "spacious" then return 30, 28, 4 end
    return 24, 22, 2   -- normal (original values)
end

-- ── Task panel state ──────────────────────────────────────────────────────────
local _taskRows      = {}   -- pool of task row frames
local _taskCallbackRegistered = false  -- ensures TasksChanged callback is registered once
local _collapsedTasks = {}  -- taskID → true when user has collapsed that parent row
-- Inline task edit in progress, { id = taskID, eb = editbox }, set on focus gain.
-- Rebuilding the rows hides a focused editbox, and its OnEditFocusLost used to
-- read that as "the user left the field": an empty task was deleted from inside
-- RenderTaskPanel, and the 0.05s re-composite in RenderList then re-showed a
-- panel with no rows and no + button (ALL-76). While _taskTeardown is set a
-- focus loss is ignored, and RenderTaskPanel carries the edit over to the new row.
local _taskEdit       = nil
local _taskTeardown   = false
-- What the task rows were last built from. ApplyTaskLayout re-renders before
-- showing the panel when they are stale, so the panel is never shown over rows
-- a no-tasks render tore down ("Tasks (0/1)", no rows, no + button, ALL-76).
local _taskDataGen    = 0      -- bumped on every TasksChanged
local _taskRowsGen    = -1     -- _taskDataGen when the rows were built
local _taskRowsNoteID = nil    -- note the rows were built for; nil = none built
local _taskRendering  = false  -- RenderTaskPanel running: a nested call reruns it after
local _taskRenderAgain = false

local RenderTaskPanel          -- forward declaration
local ApplyTaskLayout          -- forward declaration
local StartTaskEdit            -- forward declaration
local RegisterTaskCallback     -- forward declaration

-- ApplyTaskLayout: positions all panes based on note content and _rbMode.
-- UpdateModelViewer must be called AFTER this when model is involved.
ApplyTaskLayout = function(f)
    if not f then return end
    local sf      = f._scrollFrame
    local taskPnl = f._taskPanel
    local sp      = f._taskSplitter
    local addWide = f._addTasksWide

    local hasTasks   = BNB.Task and BNB.Task.HasTasks(NoteID())
    local hasModel   = IsInspectNote(NoteID())
    local hasAtts    = NoteID() and (function()
        local note = BNB.GetNote(NoteID())
        if not note then return false end
        if note.attachments and #note.attachments > 0 then return true end
        -- Inspect notes store gear separately — treat those as "has attachments"
        if note.inspectGearItems and #note.inspectGearItems > 0 then return true end
        if note.inspectTransmogItems and #note.inspectTransmogItems > 0 then return true end
        return false
    end)()
    local isSkin     = BigNoteBoxDB and BigNoteBoxDB.skinMode
    local titleH     = isSkin and SK_RB_TITLE_H or TITLE_H
    local contentTop = -(titleH + 4 + MANUAL_H + MANUAL_GAP + COUNT_H + 4)
    local botPad     = BOTTOM_PAD

    -- Update external mode strip button states
    UpdateModeStrip()

    -- Hide wide add-tasks button by default
    if addWide then addWide:Hide() end

    -- ── STATE: inspect/target note, model mode ────────────────────────────────
    if hasModel and RBMode() == "model" then
        if taskPnl then taskPnl:Hide() end
        if sp      then sp:Hide()      end
        if sf then
            sf:ClearAllPoints()
            sf:SetPoint("TOPLEFT",     f, "TOPLEFT",    0, contentTop)
            sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -SCROLL_PAD, botPad)
        end
        return  -- UpdateModelViewer runs after and splits the scroll area
    end

    -- ── STATE: no tasks exist ─────────────────────────────────────────────────
    if not hasTasks then
        if taskPnl then taskPnl:Hide() end
        if sp      then sp:Hide()      end
        -- Scroll frame leaves room for the Add Tasks button at the bottom
        if sf then
            sf:ClearAllPoints()
            sf:SetPoint("TOPLEFT",     f, "TOPLEFT",    0, contentTop)
            sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -SCROLL_PAD, botPad + ADD_TASKS_H)
        end
        -- Wide "Add Tasks" button pinned just above the bottom edge
        if addWide then
            addWide:ClearAllPoints()
            addWide:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  PAD,  botPad + 4)
            addWide:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, botPad + 4)
            addWide:SetHeight(26)
            addWide:Show()
        end
        return
    end

    -- ── Tasks exist: splitter only when attachments also present ──────────────
    local useSplitter = hasAtts

    local db    = BigNoteBoxDB
    local ratio = (db and db.taskSplitRatio and NoteID() and db.taskSplitRatio[NoteID()])
        or 0.5

    local SPLITTER_H = 12   -- must match sp:SetHeight() in BuildTaskPanel

    -- Use rbFrame's actual rendered height when valid.
    -- mainFrame:GetHeight() is a fallback for the very first open before rbFrame
    -- has been laid out. After SyncRefBoxHeight() runs, rbFrame:GetHeight() is
    -- correct and must be used — using mainFrame as proxy causes sf to be sized
    -- too tall, overlapping taskPnl because the two heights can differ slightly.
    local fH = f:GetHeight()
    if not fH or fH < 100 then
        fH = (BNB.mainFrame and BNB.mainFrame:GetHeight()) or 300
    end

    -- Total usable height, minus the splitter gap when both panels are shown
    local totalH = math.max(1,
        fH - math.abs(contentTop) - botPad
        - (useSplitter and SPLITTER_H or 0))

    -- Clamp ratio so each panel gets at least TASK_SPLIT_MIN_PX
    local minRatio = TASK_SPLIT_MIN_PX / math.max(1, totalH)
    ratio = math.max(minRatio, math.min(1.0 - minRatio, ratio))

    local taskH, attH
    if useSplitter then
        taskH = math.max(TASK_SPLIT_MIN_PX,
            math.min(totalH - TASK_SPLIT_MIN_PX,
                math.floor(totalH * (1.0 - ratio))))
        attH  = totalH - taskH
    else
        taskH = totalH
        attH  = 0
    end

    -- taskTop: below the attachment area and the splitter
    local taskTop = contentTop - attH - (useSplitter and SPLITTER_H or 0)

    if taskPnl then
        -- Rows built for another note or older data: rebuild first (ALL-76)
        if _taskRowsNoteID ~= NoteID() or _taskRowsGen ~= _taskDataGen then
            RenderTaskPanel()
        end
        taskPnl:Show()
        -- Refresh frame level each layout pass so taskPnl stays above attachment
        -- rows even after rbFrame is Raised (SetToplevel raises the whole stack,
        -- but taskPnl's level was captured at build time and becomes stale).
        taskPnl:SetFrameLevel(f:GetFrameLevel() + 50)
        taskPnl:ClearAllPoints()
        taskPnl:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, taskTop)
        taskPnl:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, taskTop)
        taskPnl:SetHeight(taskH)
    end

    -- Attachment empty-state strip height (shown even with no attachments)
    local ATT_EMPTY_H = 60   -- tall enough for "Drag items here" message

    if useSplitter then
        if sp then
            sp:ClearAllPoints()
            -- Splitter sits at the boundary: below attachments, above tasks
            sp:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, contentTop - attH)
            sp:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, contentTop - attH)
            sp:Show()
        end
        if sf then
            sf:ClearAllPoints()
            sf:SetPoint("TOPLEFT",     f, "TOPLEFT",    0, contentTop)
            sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -SCROLL_PAD,
                botPad + taskH + SPLITTER_H)
        end
    else
        -- No attachments: give a fixed strip at the top for the empty label,
        -- task panel takes the rest below it.
        if sp then sp:Hide() end
        local attStripH = ATT_EMPTY_H
        if sf then
            sf:ClearAllPoints()
            sf:SetPoint("TOPLEFT", f, "TOPLEFT", 0, contentTop)
            sf:SetPoint("TOPRIGHT", f, "TOPRIGHT", -SCROLL_PAD, contentTop)
            sf:SetHeight(attStripH)
            -- Sync scroll child so its height never exceeds the frame,
            -- preventing a spurious scrollbar from appearing.
            local sc = f._scrollChild
            if sc then sc:SetHeight(attStripH) end
        end
        -- Reposition task panel to sit below the attachment strip
        if taskPnl then
            taskPnl:SetFrameLevel(f:GetFrameLevel() + 50)
            taskPnl:ClearAllPoints()
            taskPnl:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, contentTop - attStripH)
            taskPnl:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, contentTop - attStripH)
            taskPnl:SetHeight(totalH - attStripH)
        end
    end
end

-- BuildTaskPanel: creates the task panel frame + splitter. Called once per build.
local function BuildTaskPanel(f)
    -- Task panel container (sits at the BOTTOM, below attachment scroll)
    local pnl = CreateFrame("Frame", nil, f)
    pnl:SetFrameLevel(f:GetFrameLevel() + 50)  -- above attachment rows and gear
    pnl:Hide()
    f._taskPanel = pnl

    -- Opaque background so attachment content behind doesn't bleed through.
    -- Inset 6px on left/right so it doesn't overlap the refbox window borders.
    local bg = pnl:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT",     pnl, "TOPLEFT",      6, 0)
    bg:SetPoint("BOTTOMRIGHT", pnl, "BOTTOMRIGHT",  -3, 0)
    local isSkin = BigNoteBoxDB and BigNoteBoxDB.skinMode
    if isSkin then
        local preset = BNB.GetSkinPreset()
        local r, g, b = BNB.SkinColourOf(preset, false)
        bg:SetColorTexture(r, g, b, BNB.GetSkinBgAlpha())
    else
        -- Stone texture in normal mode — matches the ButtonFrameTemplate chrome
        -- and prevents attachment cards from bleeding through.
        bg:SetTexture(ASSETS .. "UI\\ui-bg-stone")
        -- Forever: the stone reads too light next to the wood grain; darken it
        -- (vertex colour survives the SetTexture in the skin callback below)
        if BNB.IsForever then bg:SetVertexColor(0.6, 0.6, 0.6) end
    end
    pnl._bg = bg

    -- Keep bg colour in sync when preset or brightness changes.
    if BNB.RegisterSkinBackdrop then
        BNB.RegisterSkinBackdrop(function()
            local isSkin = BigNoteBoxDB and BigNoteBoxDB.skinMode
            if isSkin then
                local preset = BNB.GetSkinPreset()
                local r, g, b = BNB.SkinColourOf(preset, false)
                bg:SetColorTexture(r, g, b, BNB.GetSkinBgAlpha())
            else
                bg:SetTexture(ASSETS .. "UI\\ui-bg-stone")
            end
        end)
    end

    -- Fixed header label on pnl (not tsc) so it doesn't scroll with task rows.
    -- Created once at build time; RenderTaskPanel updates its text each render.
    local pnlHdrLbl = pnl:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pnlHdrLbl:SetPoint("TOPLEFT",  pnl, "TOPLEFT",  PAD + 3, -4)
    pnlHdrLbl:SetPoint("TOPRIGHT", pnl, "TOPRIGHT", -4,      -4)
    pnlHdrLbl:SetHeight(TASK_HDR_H - 4)
    pnlHdrLbl:SetJustifyH("LEFT")
    pnlHdrLbl:SetText("")
    f._taskHdrLbl = pnlHdrLbl

    -- Inner scroll frame for task rows — top is offset by TASK_HDR_H so the
    -- fixed header above is not overlapped; TASK_FOOTER_H at bottom for footer.
    local tsf = CreateFrame("ScrollFrame", nil, pnl, "ScrollFrameTemplate")
    tsf:SetPoint("TOPLEFT",     pnl, "TOPLEFT",    3, -TASK_HDR_H)
    tsf:SetPoint("BOTTOMRIGHT", pnl, "BOTTOMRIGHT", -SCROLL_PAD, TASK_FOOTER_H)
    if tsf.ScrollBar then
        tsf.ScrollBar:SetAlpha(0)
        tsf:HookScript("OnScrollRangeChanged", function(_, _, yr)
            tsf.ScrollBar:SetAlpha((yr or 0) > 1 and 1.0 or 0)
        end)
    end
    local tsc = CreateFrame("Frame", nil, tsf)
    tsc:SetWidth(tsf:GetWidth()); tsc:SetHeight(1)
    tsf:SetScrollChild(tsc)
    tsf:SetScript("OnSizeChanged", function(self) tsc:SetWidth(self:GetWidth()) end)
    f._taskScrollFrame = tsf
    f._taskScrollChild = tsc

    -- Fixed footer: Clear and Delete buttons spanning full pnl width.
    -- Permanent pnl children so they don't scroll with tasks and are always visible.
    local footerBtnH = TASK_FOOTER_H - 2
    local clrFooter = BNB.CreateButton(nil, pnl, L["REFBOX_TASK_CLEAR_BTN"], 0, footerBtnH)
    -- 9 = the bg's 6px left inset + the 3px gap Delete has past the bg's right inset
    clrFooter:SetPoint("BOTTOMLEFT",  pnl, "BOTTOMLEFT",  9, 3)
    clrFooter:SetPoint("BOTTOMRIGHT", pnl, "BOTTOM",      -2, 3)
    clrFooter:SetScript("OnClick", function()
        if NoteID() then BNB.Task.ClearCompleted(NoteID()) end
    end)
    clrFooter:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["REFBOX_TASK_CLEAR_TIP"], 1, 1, 1)
        GameTooltip:AddLine(L["REFBOX_TASK_CLEAR_TIP_SUB"], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    clrFooter:SetScript("OnLeave", function() GameTooltip:Hide() end)
    clrFooter._lbl = clrFooter._lbl or clrFooter:GetFontString()
    f._taskClrBtn = clrFooter

    local delFooter = BNB.CreateButton(nil, pnl, L["REFBOX_TASK_DELETE_BTN"], 0, footerBtnH)
    delFooter:SetPoint("BOTTOMLEFT",  pnl, "BOTTOM",       2, 3)
    delFooter:SetPoint("BOTTOMRIGHT", pnl, "BOTTOMRIGHT", -6, 3)
    delFooter:SetScript("OnClick", function()
        if NoteID() then BNB.Task.DeleteCompleted(NoteID()) end
    end)
    delFooter:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["REFBOX_TASK_DELETE_TIP"], 1, 1, 1)
        GameTooltip:AddLine(L["REFBOX_TASK_DELETE_TIP_SUB"], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    delFooter:SetScript("OnLeave", function() GameTooltip:Hide() end)
    delFooter._lbl = delFooter._lbl or delFooter:GetFontString()
    f._taskDelBtn = delFooter

    -- Wide "Add Tasks" button — shown when note has no tasks yet (states 1, 4)
    local addWide = BNB.CreateButton(nil, f, L["REFBOX_TASK_ADD_WIDE_BTN"], RBW - PAD * 2, 26)
    addWide:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  PAD, BOTTOM_PAD + 4)
    addWide:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, BOTTOM_PAD + 4)
    addWide:SetFrameLevel(f:GetFrameLevel() + 70)  -- above task panel (f+50) and splitter (f+60)
    addWide:Hide()
    addWide:SetScript("OnClick", function()
        if not NoteID() or not BNB.Task then return end
        local taskID = BNB.Task.AddTask(NoteID(), "")
        RenderTaskPanel()
        ApplyTaskLayout(RBFrame())
        UpdateModelViewer()
        UpdateDynamicTitle()
        UpdateModeStrip()
        -- Focused the first row's editbox without showing it, so the new task
        -- stayed "(empty)" and was never cleaned up (ALL-76).
        if taskID then BNB.FocusTaskEditBox(taskID) end
    end)
    f._addTasksWide = addWide

    -- Splitter drag bar (between attachments above and tasks below).
    -- Matches the MainWindow vertical splitter exactly: three 3x3 grip dots,
    -- no line, no SetCursor (produces black box on some clients).
    local sp = CreateFrame("Button", nil, f)
    sp:SetHeight(12)   -- taller hit area, dots centred inside
    sp:SetFrameLevel(f:GetFrameLevel() + 60)
    sp:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
    sp:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    sp:Hide()

    local dotSize = 3
    local dotGap  = 5
    local dots    = {}
    for i = -1, 1 do
        local dot = sp:CreateTexture(nil, "OVERLAY")
        dot:SetSize(dotSize, dotSize)
        dot:SetPoint("CENTER", sp, "CENTER", i * dotGap, 0)  -- horizontal
        dot:SetColorTexture(0.65, 0.65, 0.65, 0.9)
        dots[#dots + 1] = dot
    end

    -- 1px line behind dots — hidden (alpha 0) for a cleaner look
    local spLine = sp:CreateTexture(nil, "ARTWORK")
    spLine:SetHeight(1)
    spLine:SetPoint("TOPLEFT",  sp, "TOPLEFT",  0, -6)
    spLine:SetPoint("TOPRIGHT", sp, "TOPRIGHT", 0, -6)
    spLine:SetColorTexture(0.65, 0.65, 0.65, 0)

    sp:SetScript("OnEnter", function()
        for _, d in ipairs(dots) do d:SetColorTexture(1, 0.82, 0, 1) end
    end)
    sp:SetScript("OnLeave", function()
        for _, d in ipairs(dots) do d:SetColorTexture(0.65, 0.65, 0.65, 0.9) end
    end)

    local dragging = false

    -- Mouse capture frame: covers the screen during drag so releasing the mouse
    -- anywhere stops the drag. Parented to UIParent so it sits above game world.
    local captureFrame = CreateFrame("Frame", nil, UIParent)
    captureFrame:SetAllPoints(UIParent)
    captureFrame:SetFrameStrata("TOOLTIP")
    captureFrame:EnableMouse(true)
    captureFrame:Hide()
    captureFrame:SetScript("OnMouseUp", function(self)
        dragging = false
        sp:SetScript("OnUpdate", nil)
        self:Hide()
    end)

    sp:SetScript("OnMouseDown", function(self, btn)
        if btn ~= "LeftButton" then return end
        dragging = true
        captureFrame:Show()
        self:SetScript("OnUpdate", function()
            if not dragging then self:SetScript("OnUpdate", nil); return end
            local _, cy = GetCursorPosition()
            local scale = f:GetEffectiveScale()
            cy = cy / scale
            local fTop = f:GetTop()
            local fBot = f:GetBottom()
            if not fTop or not fBot then return end
            local isSkin = BigNoteBoxDB and BigNoteBoxDB.skinMode
            local titleH = isSkin and SK_RB_TITLE_H or TITLE_H
            local contentTop = fTop -
                math.abs(titleH + 4 + MANUAL_H + MANUAL_GAP + COUNT_H + 4)
            local hasModel  = IsInspectNote(NoteID())
            local footerH   = BOTTOM_PAD
            local totalH    = contentTop - fBot - footerH
            if totalH < 1 then return end
            -- ratio = attachment fraction (1 - task fraction)
            local SP_H = 12  -- splitter height
            local attH  = math.max(TASK_SPLIT_MIN_PX,
                math.min(totalH - TASK_SPLIT_MIN_PX - SP_H, contentTop - cy))
            local ratio = attH / totalH   -- attachment fraction stored
            local db = BigNoteBoxDB
            if db and db.taskSplitRatio and NoteID() then
                db.taskSplitRatio[NoteID()] = ratio
            end
            ApplyTaskLayout(f)
        end)
    end)
    sp:SetScript("OnMouseUp", function(self)
        dragging = false
        sp:SetScript("OnUpdate", nil)
        captureFrame:Hide()
    end)
    f._taskSplitter = sp
end

-- Register the TasksChanged callback once, regardless of which build path
-- created the frame. Both OpenReferenceBox and SyncReferenceBox call this
-- after building rbFrame.
RegisterTaskCallback = function()
    if _taskCallbackRegistered then return end
    if not BNB.Task or not BNB.Task.RegisterCallback then return end
    _taskCallbackRegistered = true
    BNB.Task.RegisterCallback("TasksChanged", function(changedNoteID)
        _taskDataGen = _taskDataGen + 1
        if RBFrame() and RBFrame():IsShown() and changedNoteID == NoteID() then
            if BNB.Task then
                for _, task in ipairs(BNB.Task.GetTasks(NoteID())) do
                    if not task.parentID then
                        local subs = BNB.Task.GetSubTasks(NoteID(), task.id)
                        if #subs > 0 then
                            if task.completed then
                                -- Auto-collapse fully completed parents
                                local allDone = true
                                for _, sub in ipairs(subs) do
                                    if not sub.completed then allDone = false; break end
                                end
                                if allDone then
                                    _collapsedTasks[task.id] = true
                                end
                            else
                                -- Auto-expand parents that are no longer completed
                                _collapsedTasks[task.id] = nil
                            end
                        end
                    end
                end
            end
            RenderTaskPanel()
            ApplyTaskLayout(RBFrame())
            UpdateDynamicTitle()
        end
    end)
end

-- ── Task panel renderer ───────────────────────────────────────────────────────
-- Open the inline editbox of a rendered task row with the given text.
-- Returns true when the row was found.
StartTaskEdit = function(taskID, text)
    for _, row in ipairs(_taskRows) do
        if row._taskID == taskID and row._editBox then
            for _, region in ipairs({ row:GetRegions() }) do
                if region.SetWordWrap then region:Hide() end
            end
            row._editBox:SetText(text or "")
            row._editBox:Show()
            row._editBox:SetFocus()
            return true
        end
    end
    return false
end

-- Renders task rows into f._taskScrollChild. Called from RenderList.
local function DoRenderTaskPanel()
    if not RBFrame() then return end
    local tsc = RBFrame()._taskScrollChild
    if not tsc then return end

    -- Carry an inline edit over the rebuild (ALL-76): the new row reopens it
    -- with the typed text, if the task still exists.
    local keepEdit
    if _taskEdit and _taskEdit.eb:HasFocus() then
        keepEdit = { id = _taskEdit.id, text = _taskEdit.eb:GetText() }
    end
    local wasTeardown = _taskTeardown
    _taskTeardown = true
    if keepEdit then _taskEdit.eb:ClearFocus() end

    -- Release existing task row widgets — hide frames and fontstrings alike
    for _, tr in ipairs(_taskRows) do tr:Hide() end
    _taskRows = {}
    -- Also hide any orphaned children/regions from previous renders to prevent
    -- accumulation (FontStrings created on tsc can't be destroyed, only hidden).
    for _, child in ipairs({ tsc:GetChildren() }) do child:Hide() end
    for _, region in ipairs({ tsc:GetRegions() }) do region:Hide() end
    _taskTeardown = wasTeardown
    _taskEdit = nil
    _taskRowsNoteID, _taskRowsGen = nil, _taskDataGen

    local hasTasks = BNB.Task and BNB.Task.HasTasks(NoteID())
    local taskPnl  = RBFrame()._taskPanel

    -- No tasks: hide task panel, ApplyTaskLayout shows the wide button instead
    if not hasTasks then
        if taskPnl then taskPnl:Hide() end
        return
    end

    -- Tasks exist: ensure panel is visible (ApplyTaskLayout positions it)
    if taskPnl then taskPnl:Show() end
    _taskRowsNoteID = NoteID()

    local db           = BigNoteBoxDB
    local completedPos = (db and db.taskCompletedPosition) or "bottom"
    local T            = BNB.Task
    local done, total  = T.GetCompletionCount(NoteID())

    -- ── Header row ──────────────────────────────────────────────────────────
    -- "Tasks (done/total)" label + [GR] [GS] [+] buttons
    local topDone, topTotal = 0, 0
    for _, t in ipairs(T.GetTopLevel(NoteID())) do
        topTotal = topTotal + 1
        if t.completed then topDone = topDone + 1 end
    end

    -- Note-level global reset/situation for header prefix and [GR][GS] icons
    local note2      = BNB.GetNote(NoteID())
    local tl2        = note2 and note2.taskList
    local globalRst  = tl2 and tl2.resetType
    local globalSit  = tl2 and tl2.situation

    local hdrPrefix = L["REFBOX_TASK_HDR_DEFAULT"]
    if     globalRst == "daily"  then hdrPrefix = L["REFBOX_TASK_HDR_DAILY"]
    elseif globalRst == "weekly" then hdrPrefix = L["REFBOX_TASK_HDR_WEEKLY"] end

    -- Update the fixed header label on pnl (created at build time, doesn't scroll)
    if RBFrame()._taskHdrLbl then
        local hdrClr = (topTotal > 0 and topDone == topTotal) and "|cff66dd66" or ""
        RBFrame()._taskHdrLbl:SetText(hdrPrefix .. " " .. hdrClr .. "(" .. topDone .. "/" .. topTotal .. ")|r")
    end

    -- Invisible right-click hit area no longer needed — [GR][GS] icons handle global editing.

    -- Add task (+) and [GR][GS] icons — parented to pnl so they don't scroll.
    local pnlLevel = taskPnl:GetFrameLevel() + 56

    local addBtn = CreateFrame("Button", nil, taskPnl)
    addBtn:SetFrameLevel(pnlLevel)
    addBtn:SetSize(18, 18)
    -- Offset by SCROLL_PAD so the button sits left of the scrollbar track.
    addBtn:SetPoint("TOPRIGHT", taskPnl, "TOPRIGHT", -(4 + SCROLL_PAD), -3)
    local addN = addBtn:CreateTexture(nil, "ARTWORK"); addN:SetAllPoints()
    addN:SetTexture(ASSETS .. "Buttons\\bt-plus-normal")
    local addH = addBtn:CreateTexture(nil, "ARTWORK"); addH:SetAllPoints()
    addH:SetTexture(ASSETS .. "Buttons\\bt-plus-hover"); addH:Hide()
    local addP = addBtn:CreateTexture(nil, "ARTWORK"); addP:SetAllPoints()
    addP:SetTexture(ASSETS .. "Buttons\\bt-plus-press"); addP:Hide()
    addBtn:SetScript("OnEnter", function(self)
        addH:Show(); addN:Hide()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["REFBOX_TASK_ADD_TIP"], 1, 1, 1)
        GameTooltip:AddLine(L["REFBOX_TASK_ADD_TIP_SUB"], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    addBtn:SetScript("OnLeave", function() addH:Hide(); addN:Show(); GameTooltip:Hide() end)
    addBtn:SetScript("OnMouseDown", function() addP:Show(); addN:Hide(); addH:Hide() end)
    addBtn:SetScript("OnMouseUp",   function() addP:Hide(); addN:Show() end)
    addBtn:SetScript("OnClick", function()
        if not NoteID() then return end
        local taskID = BNB.Task.AddTask(NoteID(), "")
        if taskID then
            RenderTaskPanel(); ApplyTaskLayout(RBFrame())
            BNB.FocusTaskEditBox(taskID)
        end
    end)
    _taskRows[#_taskRows + 1] = addBtn

    -- [GR] and [GS] icons — chain left of [+], parented to pnl (fixed).
    -- Layout right-to-left: [+] <- [GS] <- [GR]
    -- Each icon is 14px wide + 2px gap = 16px step.
    local function MakeHdrIcon(texPath, xOffset, isActive, tipActive, tipInactive)
        local ico = CreateFrame("Button", nil, taskPnl)
        ico:SetFrameLevel(pnlLevel)
        ico:SetSize(14, 14)
        ico:SetPoint("RIGHT", addBtn, "LEFT", xOffset, 0)
        local tx = ico:CreateTexture(nil, "ARTWORK"); tx:SetAllPoints()
        tx:SetTexture(texPath)
        ico:SetAlpha(isActive and 0.85 or 0.35)
        pcall(function() tx:SetDesaturated(not isActive) end)
        ico:SetScript("OnEnter", function(self)
            self:SetAlpha(1.0)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(isActive and tipActive or tipInactive, 1, 1, 1)
            GameTooltip:AddLine(L["REFBOX_TASK_DEFAULTS_TIP"], 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        ico:SetScript("OnLeave", function(self)
            self:SetAlpha(isActive and 0.85 or 0.35); GameTooltip:Hide()
        end)
        ico:SetScript("OnClick", function()
            if BNB.TaskEditWindow and BNB.TaskEditWindow.OpenGlobal then
                BNB.TaskEditWindow.OpenGlobal(NoteID(), ico)
            end
        end)
        _taskRows[#_taskRows + 1] = ico
    end

    -- [GS] 2px left of [+], [GR] 2px left of [GS]
    local hasSit = globalSit and globalSit ~= ""
    local hasRst = globalRst and globalRst ~= ""
    MakeHdrIcon(ASSETS .. "UI\\ui-situation", -2, hasSit,
        string.format(L["REFBOX_TASK_GLOBAL_SIT_FMT"], globalSit or ""),
        L["REFBOX_TASK_GLOBAL_SIT_NONE"])
    MakeHdrIcon(ASSETS .. "UI\\ui-repeat", -18, hasRst,
        string.format(L["REFBOX_TASK_GLOBAL_RST_FMT"], globalRst or ""),
        L["REFBOX_TASK_GLOBAL_RST_NONE"])

    -- ── Task rows ────────────────────────────────────────────────────────────
    local y       = -4   -- small top pad; header is now fixed on pnl, not tsc
    local indent  = T.SUBTASK_INDENT or 14
    local contentW = (RBFrame():GetWidth() or RBW) - SCROLL_PAD - PAD * 2

    -- Gather top-level tasks, sort completed to bottom if configured
    local topLevel = T.GetTopLevel(NoteID())
    if completedPos == "bottom" then
        local active, completed = {}, {}
        for _, t in ipairs(topLevel) do
            if t.completed then completed[#completed + 1] = t
            else                active[#active + 1] = t end
        end
        topLevel = {}
        for _, t in ipairs(active)    do topLevel[#topLevel + 1] = t end
        for _, t in ipairs(completed) do topLevel[#topLevel + 1] = t end
    end

    local function RenderTaskRow(task, isSubTask)
        local TASK_ROW_H, TASK_SUBROW_H, TASK_ROW_GAP = GetTaskSpacing()
        local rowH  = isSubTask and TASK_SUBROW_H or TASK_ROW_H
        local xOff  = isSubTask and indent or 0
        local clr   = T.GetTaskColor(task)

        local row = CreateFrame("Button", nil, tsc)
        row:SetPoint("TOPLEFT",  tsc, "TOPLEFT",  PAD + xOff, y)
        row:SetPoint("TOPRIGHT", tsc, "TOPRIGHT", -PAD, y)
        row:SetHeight(rowH)
        row._taskID = task.id
        _taskRows[#_taskRows + 1] = row

        -- Checkbox (scaled UICheckButtonTemplate)
        local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        cb:SetScale(TASK_CB_SCALE)
        cb:SetChecked(task.completed)
        cb:SetPoint("LEFT", row, "LEFT", 0, 0)
        cb:SetScript("OnClick", function(self, btn)
            if btn ~= "RightButton" and NoteID() then T.ToggleTask(NoteID(), task.id) end
        end)
        -- Route right-clicks on the checkbox to the context menu
        cb:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        cb:HookScript("OnClick", function(_, btn)
            if btn == "RightButton" then
                cb:SetChecked(task.completed)  -- undo the toggle
                BNB.ShowTaskContextMenu(row, NoteID(), task.id)
            end
        end)
        row._cb = cb

        -- Task text / inline editbox
        local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("LEFT",  cb,  "RIGHT", 2,  0)
        lbl:SetPoint("RIGHT", row, "RIGHT", -22, 0)
        lbl:SetHeight(rowH)
        lbl:SetJustifyH("LEFT")
        lbl:SetWordWrap(false)
        lbl:SetTextColor(clr.r, clr.g, clr.b)
        -- For top-level tasks with sub-tasks, prefix with (done/total)
        local lblText = task.text ~= "" and task.text or "(empty)"
        if not isSubTask then
            local subs = T.GetSubTasks(NoteID(), task.id)
            if #subs > 0 then
                local subDone = 0
                for _, s in ipairs(subs) do if s.completed then subDone = subDone + 1 end end
                local cntClr = (subDone == #subs) and "|cff66dd66" or "|cffaaaaaa"
                lblText = cntClr .. "(" .. subDone .. "/" .. #subs .. ")|r " .. lblText
                -- When collapsed, append sub-task count so it's visible without expanding
                if _collapsedTasks[task.id] then
                    lblText = lblText .. " |cff888888(" .. #subs .. ")|r"
                end
            end
        end
        lbl:SetText(lblText)

        -- Inline edit box (hidden until clicked)
        local eb = CreateFrame("EditBox", nil, row, "BackdropTemplate")
        BNB.EnsureBackdrop(eb)
        BNB.SetBackdrop(eb, 0.06, 0.06, 0.08, 0.95, 0.20, 0.20, 0.25, 1)
        eb:SetPoint("LEFT",  cb,  "RIGHT", 2,  0)
        eb:SetPoint("RIGHT", row, "RIGHT", -22, 0)
        eb:SetHeight(rowH - 2)
        eb:SetAutoFocus(false)
        eb:SetMultiLine(false)
        eb:SetMaxLetters(500)
        eb:SetFontObject("GameFontNormalSmall")
        eb:SetTextInsets(4, 4, 1, 1)
        eb:Hide()
        row._editBox = eb

        lbl:SetScript("OnEnter", function(self)
            if self:IsTruncated() then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(task.text, 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        lbl:SetScript("OnLeave", function() GameTooltip:Hide() end)
        lbl:SetScript("OnMouseDown", function(_, btn)
            if btn == "RightButton" then
                BNB.ShowTaskContextMenu(row, NoteID(), task.id)
                return
            end
            lbl:Hide()
            eb:SetText(task.text)
            eb:Show()
            eb:SetFocus()
        end)
        eb:SetScript("OnEditFocusGained", function(self)
            _taskEdit = { id = task.id, eb = self }
        end)
        eb:SetScript("OnEnterPressed", function(self)
            _taskEdit = nil  -- edit ends here; the re-render below must not reopen it
            local newText = self:GetText()
            if IsShiftKeyDown() then
                -- Shift+Enter: save current task and create a new sibling below it
                if newText ~= "" then
                    T.UpdateTask(NoteID(), task.id, { text = newText })
                    task.text = newText
                end
                self:ClearFocus()
                local sibID = T.AddTask(NoteID(), "", isSubTask and task.parentID or nil)
                if sibID then
                    if task.parentID then _collapsedTasks[task.parentID] = nil end
                    RenderTaskPanel()
                    ApplyTaskLayout(RBFrame())
                    BNB.FocusTaskEditBox(sibID)
                end
                return
            end
            if newText == "" then
                -- Delete task if committed with empty text
                BNB.Task.DeleteTask(NoteID(), task.id)
            else
                T.UpdateTask(NoteID(), task.id, { text = newText })
                task.text = newText
                lbl:SetText(newText)
                self:Hide(); lbl:Show()
            end
            self:ClearFocus()
        end)
        eb:SetScript("OnEscapePressed", function(self)
            _taskEdit = nil
            if task.text == "" then
                -- Escape on a never-saved empty task removes it
                BNB.Task.DeleteTask(NoteID(), task.id)
            else
                self:Hide(); lbl:Show()
            end
            self:ClearFocus()
        end)
        eb:SetScript("OnEditFocusLost", function(self)
            -- Rows being rebuilt: not the user leaving the field (ALL-76)
            if _taskTeardown then return end
            _taskEdit = nil
            if self:IsShown() then
                -- Focus lost without Enter/Escape — save if non-empty, delete if empty
                local newText = self:GetText()
                if newText == "" then
                    BNB.Task.DeleteTask(NoteID(), task.id)
                else
                    T.UpdateTask(NoteID(), task.id, { text = newText })
                    task.text = newText
                    lbl:SetText(newText)
                    self:Hide(); lbl:Show()
                end
            end
        end)
        eb:SetScript("OnMouseUp", function(_, btn)
            if btn == "RightButton" then
                BNB.ShowTaskContextMenu(row, NoteID(), task.id)
            end
        end)

        -- Sub-task toggle / add button (top-level tasks only).
        -- No sub-tasks : dim >  → click adds an empty sub-task and focuses it.
        -- Has sub-tasks, expanded  : full v  → click collapses.
        -- Has sub-tasks, collapsed : full >  → click expands.
        local subTasks = T.GetSubTasks(NoteID(), task.id)
        -- rightAnchor is declared here (row scope) so the R/S icon blocks below
        -- can use it regardless of whether this is a top-level or sub-task row.
        local rightAnchor = nil
        if not isSubTask then
            local hasSubTasks = #subTasks > 0
            -- Collapse state persists across re-renders via _collapsedTasks.
            -- Default: expanded when sub-tasks exist, irrelevant when none.
            row._expanded = hasSubTasks and not _collapsedTasks[task.id]

            local togBtn = CreateFrame("Button", nil, row)
            togBtn:SetSize(14, 14)
            togBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            local togN = togBtn:CreateTexture(nil, "ARTWORK"); togN:SetAllPoints()

            local function UpdateTogBtn()
                if hasSubTasks then
                    togN:SetTexture(ASSETS .. "Buttons\\" ..
                        (row._expanded and "bt-down-normal" or "bt-right-normal"))
                    togBtn:SetAlpha(1.0)
                else
                    -- No sub-tasks: always > at low alpha (add affordance)
                    togN:SetTexture(ASSETS .. "Buttons\\bt-right-normal")
                    togBtn:SetAlpha(0.3)
                end
            end
            UpdateTogBtn()

            togBtn:SetScript("OnClick", function()
                if hasSubTasks then
                    -- Toggle collapse/expand, persist state
                    row._expanded = not row._expanded
                    if row._expanded then
                        _collapsedTasks[task.id] = nil
                    else
                        _collapsedTasks[task.id] = true
                    end
                    RenderTaskPanel()
                    ApplyTaskLayout(RBFrame())
                else
                    -- No sub-tasks: add one and focus its inline editbox
                    local subID = T.AddTask(NoteID(), "", task.id)
                    if subID then
                        _collapsedTasks[task.id] = nil  -- ensure parent is expanded
                        RenderTaskPanel()
                        ApplyTaskLayout(RBFrame())
                        for _, tr in ipairs(_taskRows) do
                            if tr._taskID == subID and tr._editBox then
                                local lbl2 = ({ tr:GetRegions() })[1]
                                if lbl2 and lbl2.Hide then lbl2:Hide() end
                                tr._editBox:SetText("")
                                tr._editBox:Show()
                                tr._editBox:SetFocus()
                                break
                            end
                        end
                    end
                end
            end)
            togBtn:SetScript("OnMouseUp", function(_, btn)
                if btn == "RightButton" then
                    BNB.ShowTaskContextMenu(row, NoteID(), task.id)
                end
            end)

            row._togBtn = togBtn

            -- Right-side extras: chain leftward from togBtn.
            -- Order right-to-left: togBtn ← subAddBtn? (R/S icons now outside this block)
            local iconGap  = 2
            rightAnchor = togBtn  -- each new element anchors RIGHT to this LEFT

            -- + sub-task button (only when sub-tasks already exist), so more can be
            -- added without right-clicking. Was built twice, same size and place (ALL-65.10e).
            if hasSubTasks then
                local subAddBtn = CreateFrame("Button", nil, row)
                subAddBtn:SetSize(14, 14)
                subAddBtn:SetPoint("RIGHT", rightAnchor, "LEFT", -iconGap, 0)
                local saN = subAddBtn:CreateTexture(nil, "ARTWORK"); saN:SetAllPoints()
                saN:SetTexture(ASSETS .. "Buttons\\bt-plus-normal")
                local saH = subAddBtn:CreateTexture(nil, "ARTWORK"); saH:SetAllPoints()
                saH:SetTexture(ASSETS .. "Buttons\\bt-plus-hover"); saH:Hide()
                subAddBtn:SetScript("OnEnter", function(self)
                    saH:Show(); saN:Hide()
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:AddLine(L["REFBOX_TASK_ADD_SUB_TIP"], 1, 1, 1)
                    GameTooltip:Show()
                end)
                subAddBtn:SetScript("OnLeave", function()
                    saH:Hide(); saN:Show(); GameTooltip:Hide()
                end)
                subAddBtn:SetScript("OnClick", function()
                    local subID = T.AddTask(NoteID(), "", task.id)
                    if subID then
                        _collapsedTasks[task.id] = nil
                        RenderTaskPanel()
                        ApplyTaskLayout(RBFrame())
                        BNB.FocusTaskEditBox(subID)
                    end
                end)
                subAddBtn:SetScript("OnMouseUp", function(_, btn)
                    if btn == "RightButton" then
                        BNB.ShowTaskContextMenu(row, NoteID(), task.id)
                    end
                end)
                _taskRows[#_taskRows + 1] = subAddBtn
                rightAnchor = subAddBtn
            end
        end  -- end if not isSubTask (toggle/subAdd block)

        -- Situation and reset icons appear on both top-level and sub-tasks.
        -- For top-level, rightAnchor is already set (togBtn or subAddBtn).
        -- For sub-tasks, create a synthetic anchor at the row's right edge.
        local iconSize = 12
        local iconGap  = 2
        if isSubTask then
            local anchor = CreateFrame("Frame", nil, row)
            anchor:SetSize(1, 1)
            anchor:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            rightAnchor = anchor
        end

        -- Situation icon (shown when task has a situation binding)
        if task.situation and task.situation ~= "" then
            local sitIco = CreateFrame("Button", nil, row)
            sitIco:SetSize(iconSize, iconSize)
            sitIco:SetPoint("RIGHT", rightAnchor, "LEFT", -iconGap, 0)
            local sitTx = sitIco:CreateTexture(nil, "ARTWORK"); sitTx:SetAllPoints()
            sitTx:SetTexture(ASSETS .. "UI\\ui-situation")
            sitIco:SetAlpha(0.75)
            sitIco:SetScript("OnEnter", function(self)
                self:SetAlpha(1.0)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(string.format(L["REFBOX_TASK_SITUATION_FMT"], task.situation), 1, 1, 1)
                GameTooltip:AddLine(L["REFBOX_TASK_CLICK_EDIT"], 0.8, 0.8, 0.8)
                GameTooltip:Show()
            end)
            sitIco:SetScript("OnLeave", function(self) self:SetAlpha(0.75); GameTooltip:Hide() end)
            sitIco:SetScript("OnClick", function()
                if BNB.TaskEditWindow and BNB.TaskEditWindow.Open then
                    BNB.TaskEditWindow.Open(NoteID(), task.id, row)
                end
            end)
            _taskRows[#_taskRows + 1] = sitIco
            rightAnchor = sitIco
        end

        -- Reset icon (shown when task has a reset type set)
        if task.resetType and task.resetType ~= "" and task.resetType ~= "none" then
            local resetTip = task.resetType == "daily" and L["REFBOX_TASK_RESET_DAILY_TIP"] or L["REFBOX_TASK_RESET_WEEKLY_TIP"]
            local rstIco = CreateFrame("Button", nil, row)
            rstIco:SetSize(iconSize, iconSize)
            rstIco:SetPoint("RIGHT", rightAnchor, "LEFT", -iconGap, 0)
            local rstTx = rstIco:CreateTexture(nil, "ARTWORK"); rstTx:SetAllPoints()
            rstTx:SetTexture(ASSETS .. "UI\\ui-repeat")
            rstIco:SetAlpha(0.75)
            rstIco:SetScript("OnEnter", function(self)
                self:SetAlpha(1.0)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(resetTip, 1, 1, 1)
                GameTooltip:AddLine(L["REFBOX_TASK_CLICK_EDIT"], 0.8, 0.8, 0.8)
                GameTooltip:Show()
            end)
            rstIco:SetScript("OnLeave", function(self) self:SetAlpha(0.75); GameTooltip:Hide() end)
            rstIco:SetScript("OnClick", function()
                if BNB.TaskEditWindow and BNB.TaskEditWindow.Open then
                    BNB.TaskEditWindow.Open(NoteID(), task.id, row)
                end
            end)
            _taskRows[#_taskRows + 1] = rstIco
        end
        row:SetScript("OnMouseUp", function(_, btn)
            if btn == "RightButton" then
                BNB.ShowTaskContextMenu(row, NoteID(), task.id)
            end
        end)

        y = y - rowH - TASK_ROW_GAP

        -- Sub-tasks (one level only, only if expanded)
        if not isSubTask and row._expanded then
            for _, sub in ipairs(subTasks) do
                RenderTaskRow(sub, true)
            end
        end
    end

    for _, task in ipairs(topLevel) do
        RenderTaskRow(task, false)
    end

    -- Set scroll child height
    local tsf = RBFrame()._taskScrollFrame
    tsc:SetHeight(math.max(math.abs(y) + 4, tsf and tsf:GetHeight() or 60))

    -- Disable Clear/Delete when no tasks are completed; dim label to match.
    -- Normal mode leaves the colour to the button template (yellow, grey when
    -- disabled) like every other button; only skin labels are coloured by hand.
    local hasCompleted = done > 0
    local isSkin = BigNoteBoxDB and BigNoteBoxDB.skinMode
    local function SetFooterBtn(btn, enabled)
        if not btn then return end
        btn:SetEnabled(enabled)
        local lbl = btn._lbl
        if lbl and isSkin then
            lbl:SetTextColor(enabled and 1 or 0.4, enabled and 1 or 0.4, enabled and 1 or 0.4)
        end
    end
    SetFooterBtn(RBFrame()._taskClrBtn, hasCompleted)
    SetFooterBtn(RBFrame()._taskDelBtn, hasCompleted)

    if keepEdit then StartTaskEdit(keepEdit.id, keepEdit.text) end
end

-- A render triggered from inside a render (a focus change deleting a task,
-- a TasksChanged listener) runs again after the current one instead of
-- nesting, so the last pass always draws the current data (ALL-76).
RenderTaskPanel = function()
    if _taskRendering then _taskRenderAgain = true; return end
    _taskRendering = true
    local passes = 0
    repeat
        _taskRenderAgain = false
        passes = passes + 1
        local ok, err = pcall(DoRenderTaskPanel)
        if not ok then geterrorhandler()(err) end
    until not _taskRenderAgain or passes >= 3
    _taskRendering = false
end

-- Public helper: focus the inline editbox of a specific task row.
-- Used by NoteList "Create task" context menu item after opening RefBox.
function BNB.FocusTaskEditBox(taskID)
    -- Every "add task" path (editor bottom bar, note list menu, sticky note)
    -- ends here. Notes with a model open on the Model tab, so the new task was
    -- added out of sight; switch to Tasks first (builds the rows it focuses).
    if RBFrame() and RBFrame():IsShown() and RBMode() ~= "attachments" and IsInspectNote(NoteID()) then
        OnModeClick("attachments")
    end
    if StartTaskEdit(taskID, "") then return end
    -- No row to type into (Reference Box closed or disabled): the caller added
    -- this empty task only to edit it, so don't leave it behind (ALL-76).
    local T = BNB.Task
    local task = T and NoteID() and T.FindTask(NoteID(), taskID)
    if task and task.text == "" then T.DeleteTask(NoteID(), taskID) end
end

-- ── Task context menu (WowStyle1DropdownTemplate — matches attachment rows) ──
local _taskCtxDropdown
function BNB.ShowTaskContextMenu(anchor, noteID, taskID)
    if not noteID or not taskID then return end
    local T = BNB.Task
    if not T then return end
    local task = T.FindTask(noteID, taskID)
    if not task then return end

    if not _taskCtxDropdown then
        _taskCtxDropdown = CreateFrame("DropdownButton", "BNBTaskCtxDropdown",
            UIParent, "WowStyle1DropdownTemplate")
        _taskCtxDropdown:SetSize(1, 1); _taskCtxDropdown:SetAlpha(0)
    end
    BNB.PlaceContextMenu(_taskCtxDropdown, anchor)

    local isTopLevel = not task.parentID
    local L = BNB.L or {}

    _taskCtxDropdown:SetupMenu(function(_, root)
        -- Edit task...
        root:CreateButton(L["TASK_CTX_EDIT"] or "Edit task...", function()
            if BNB.TaskEditWindow and BNB.TaskEditWindow.Open then
                BNB.TaskEditWindow.Open(noteID, taskID, anchor)
            end
        end)

        -- Add sub-task (top-level only, one nesting level)
        if isTopLevel then
            root:CreateButton(L["TASK_CTX_ADD_SUB"] or "Add sub-task", function()
                local subID = T.AddTask(noteID, "", taskID)
                if subID and RenderTaskPanel then
                    RenderTaskPanel()
                    ApplyTaskLayout(RBFrame())
                    -- Focus the new empty sub-task's inline editbox
                    for _, tr in ipairs(_taskRows) do
                        if tr._taskID == subID and tr._editBox then
                            local lbl2 = ({ tr:GetRegions() })[1]
                            if lbl2 and lbl2.Hide then lbl2:Hide() end
                            tr._editBox:SetText("")
                            tr._editBox:Show()
                            tr._editBox:SetFocus()
                            break
                        end
                    end
                end
            end)
        end

        -- Duplicate
        root:CreateButton(L["TASK_CTX_DUPLICATE"] or "Duplicate", function()
            local newID = T.AddTask(noteID, task.text, task.parentID)
            if newID then
                local changes = {}
                if task.resetType then changes.resetType = task.resetType end
                if task.resetEvery then changes.resetEvery = task.resetEvery end
                if task.situation then changes.situation = task.situation end
                if next(changes) then T.UpdateTask(noteID, newID, changes) end
                if RenderTaskPanel then
                    RenderTaskPanel()
                    ApplyTaskLayout(RBFrame())
                end
            end
        end)

        root:CreateDivider()

        -- Set reset (radio submenu)
        local resetSub = root:CreateButton(L["TASK_CTX_RESET"] or "Set reset")
        local RESETS = {
            { label = L["TASK_CTX_RESET_NONE"]   or "None",   value = nil    },
            { label = L["TASK_CTX_RESET_DAILY"]  or "Daily",  value = "daily"  },
            { label = L["TASK_CTX_RESET_WEEKLY"] or "Weekly", value = "weekly" },
        }
        for _, entry in ipairs(RESETS) do
            resetSub:CreateRadio(entry.label,
                function() return task.resetType == entry.value end,
                function()
                    if entry.value then
                        T.UpdateTask(noteID, taskID, { resetType = entry.value, _clear = {"lastReset"} })
                    else
                        T.UpdateTask(noteID, taskID, { _clear = {"resetType", "resetEvery", "lastReset"} })
                    end
                end)
        end

        -- Set situation (radio submenu with live-detected values)
        local sitSub = root:CreateButton(L["TASK_CTX_SITUATION"] or "Set situation")
        sitSub:CreateRadio(L["TASK_CTX_SIT_NONE"] or "None (global)",
            function() return not task.situation end,
            function()
                T.UpdateTask(noteID, taskID, { _clear = {"situation"} })
            end)

        local curZone = GetZoneText and GetZoneText() or ""
        if curZone ~= "" then
            sitSub:CreateRadio(string.format(L["REFBOX_TASK_SIT_ZONE_FMT"], curZone),
                function() return task.situation == ("zone:" .. curZone) end,
                function()
                    T.UpdateTask(noteID, taskID, { situation = "zone:" .. curZone })
                end)
        end

        local curSub = GetSubZoneText and GetSubZoneText() or ""
        if curSub ~= "" then
            sitSub:CreateRadio(string.format(L["REFBOX_TASK_SIT_SUBZONE_FMT"], curSub),
                function() return task.situation == ("subzone:" .. curSub) end,
                function()
                    T.UpdateTask(noteID, taskID, { situation = "subzone:" .. curSub })
                end)
        end

        local curInst = GetInstanceInfo and select(1, GetInstanceInfo()) or ""
        local isInstance = GetInstanceInfo and select(2, GetInstanceInfo())
        if curInst ~= "" and isInstance and isInstance ~= "none" then
            sitSub:CreateRadio(string.format(L["REFBOX_TASK_SIT_INSTANCE_FMT"], curInst),
                function() return task.situation == ("instance:" .. curInst) end,
                function()
                    T.UpdateTask(noteID, taskID, { situation = "instance:" .. curInst })
                end)
        end

        local targetName = (BNB.UnitNameRealm("target"))
        if targetName and UnitIsPlayer("target") then
            sitSub:CreateRadio(string.format(L["REFBOX_TASK_SIT_PLAYER_FMT"], targetName),
                function() return task.situation == ("player:" .. targetName) end,
                function()
                    T.UpdateTask(noteID, taskID, { situation = "player:" .. targetName })
                end)
        end

        root:CreateDivider()

        -- Delete
        local delLabel = "|cffFF6666" .. (L["TASK_CTX_DELETE"] or "Delete") .. "|r"
        root:CreateButton(delLabel, function()
            T.DeleteTask(noteID, taskID)
            if RenderTaskPanel then
                RenderTaskPanel()
                ApplyTaskLayout(RBFrame())
            end
        end)
    end)
    _taskCtxDropdown:OpenMenu()
end

-- RenderList's second delayed pass (ReferenceBox.lua) hides and re-shows the
-- panel so the chrome behind it paints; an inline task edit survives it.
local function RecompositeTaskPanel()
    local rbFrame = RBFrame()
    local tp = rbFrame._taskPanel
    if tp and tp:IsShown() then
        local keep = _taskEdit and _taskEdit.eb:HasFocus()
            and { id = _taskEdit.id, text = _taskEdit.eb:GetText() }
        _taskTeardown = true
        if keep then _taskEdit.eb:ClearFocus() end
        tp:Hide()
        ApplyTaskLayout(rbFrame)
        _taskTeardown = false
        if keep and tp:IsShown() then StartTaskEdit(keep.id, keep.text) end
    end
end

K.RenderTaskPanel, K.ApplyTaskLayout = RenderTaskPanel, ApplyTaskLayout
K.BuildTaskPanel, K.RegisterTaskCallback = BuildTaskPanel, RegisterTaskCallback
K.RecompositeTaskPanel = RecompositeTaskPanel

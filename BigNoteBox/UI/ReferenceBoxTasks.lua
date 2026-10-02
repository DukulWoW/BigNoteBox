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
-- HasModel: the note has a model view (its own, or an entry shown, ALL-206)
local HasModel, OnModeClick = K.HasModel, K.OnModeClick
local TasksOnly = K.TasksOnly
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
    local s = BigNoteBoxDB and BigNoteBoxDB.taskSpacing or BNB.DEFAULTS.taskSpacing
    if s == "compact"  then return 18, 16, 1 end
    if s == "spacious" then return 30, 28, 4 end
    return 24, 22, 2   -- normal (original values)
end

-- ── Task panel state ──────────────────────────────────────────────────────────
local _taskRows      = {}   -- rows shown by the last render (the pool is tsc._taskPool)
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

    local hasTasks   = BNB.Task and BNB.Task.Shows(NoteID())
    local hasModel   = HasModel(NoteID())
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

    -- ── STATE: tasks-only window (Reference Box off, ALL-102) ─────────────────
    -- No add strip, count, attachment list or splitter: the task panel fills
    -- the window under the title, or the wide Add Tasks button sits there.
    local strip, count = f._manualStrip, f._countLabel
    local tasksOnly = TasksOnly()
    if strip then strip:SetShown(not tasksOnly) end
    if count then if tasksOnly then count:Hide() else count:Show() end end
    if sf then sf:SetShown(not tasksOnly) end
    if tasksOnly then
        if sp then sp:Hide() end
        local top = -(titleH + 4)
        if hasTasks and taskPnl then
            if _taskRowsNoteID ~= NoteID() or _taskRowsGen ~= _taskDataGen then
                RenderTaskPanel()
            end
            taskPnl:Show()
            taskPnl:SetFrameLevel(f:GetFrameLevel() + 50)
            taskPnl:ClearAllPoints()
            taskPnl:SetPoint("TOPLEFT",     f, "TOPLEFT",     0, top)
            taskPnl:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, botPad)
        else
            if taskPnl then taskPnl:Hide() end
            if addWide then
                addWide:ClearAllPoints()
                addWide:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD,  top - 4)
                addWide:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, top - 4)
                addWide:SetHeight(26)
                addWide:Show()
            end
        end
        return
    end

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
        -- Scroll frame leaves room for the Add Tasks button at the bottom,
        -- unless the Tasks module is off (no button, ALL-102)
        local tasksOn = BNB.TasksEnabled()
        if sf then
            sf:ClearAllPoints()
            sf:SetPoint("TOPLEFT",     f, "TOPLEFT",    0, contentTop)
            sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -SCROLL_PAD,
                botPad + (tasksOn and ADD_TASKS_H or 0))
        end
        -- Wide "Add Tasks" button pinned just above the bottom edge
        if addWide and tasksOn then
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
            local hasModel  = HasModel(NoteID())
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
    BNB.SetHoverCursor(sp, "size")   -- ALL-95
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
            row._lbl:Hide()
            row._editBox:SetText(text or "")
            row._editBox:Show()
            row._editBox:SetFocus()
            return true
        end
    end
    return false
end

-- Task rows and the header buttons are built once and reused (PERF-02): WoW
-- never frees a frame, and building new ones on every TasksChanged leaked
-- about seven frames per task per render. The scripts read what a row shows
-- now from row._task / row._taskID / row._isSub, set by FillTaskRow.

-- [GR] / [GS] header icon. State (active, tooltip) is set by SetHdrIcon.
local function MakeHdrIcon(taskPnl, anchor, xOffset, texPath)
    local ico = CreateFrame("Button", nil, taskPnl)
    ico:SetSize(14, 14)
    ico:SetPoint("RIGHT", anchor, "LEFT", xOffset, 0)
    local tx = ico:CreateTexture(nil, "ARTWORK"); tx:SetAllPoints()
    tx:SetTexture(texPath)
    ico._tx = tx
    ico:SetScript("OnEnter", function(self)
        self:SetAlpha(1.0)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(self._tip or "", 1, 1, 1)
        GameTooltip:AddLine(L["REFBOX_TASK_DEFAULTS_TIP"], 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    ico:SetScript("OnLeave", function(self)
        self:SetAlpha(self._active and 0.85 or 0.35); GameTooltip:Hide()
    end)
    ico:SetScript("OnClick", function(self)
        if BNB.TaskEditWindow and BNB.TaskEditWindow.OpenGlobal then
            BNB.TaskEditWindow.OpenGlobal(NoteID(), self)
        end
    end)
    return ico
end

local function SetHdrIcon(ico, level, isActive, tipActive, tipInactive)
    ico:SetFrameLevel(level)
    ico._active = isActive
    ico._tip    = isActive and tipActive or tipInactive
    ico:SetAlpha(isActive and 0.85 or 0.35)
    pcall(ico._tx.SetDesaturated, ico._tx, not isActive)
end

-- Add task (+) and [GR][GS] icons, parented to the panel so they don't scroll.
local function TaskHeaderButtons(taskPnl)
    if taskPnl._hdrBtns then return taskPnl._hdrBtns end
    local addBtn = CreateFrame("Button", nil, taskPnl)
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
    -- Layout right-to-left: [+] <- [GS] <- [GR]; each icon is 14px + 2px gap.
    taskPnl._hdrBtns = {
        add = addBtn,
        sit = MakeHdrIcon(taskPnl, addBtn, -2,  ASSETS .. "UI\\ui-situation"),
        rst = MakeHdrIcon(taskPnl, addBtn, -18, ASSETS .. "UI\\ui-repeat"),
    }
    return taskPnl._hdrBtns
end

local function ShowRowMenu(row)
    BNB.ShowTaskContextMenu(row, NoteID(), row._taskID)
end

-- Situation / reset icon on a row; the tooltip line comes from tipFn(task).
local function MakeRowIcon(row, texPath, tipFn)
    local ico = CreateFrame("Button", nil, row)
    ico:SetSize(12, 12)
    local tx = ico:CreateTexture(nil, "ARTWORK"); tx:SetAllPoints()
    tx:SetTexture(texPath)
    ico:SetScript("OnEnter", function(self)
        self:SetAlpha(1.0)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(tipFn(row._task), 1, 1, 1)
        GameTooltip:AddLine(L["REFBOX_TASK_CLICK_EDIT"], 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    ico:SetScript("OnLeave", function(self) self:SetAlpha(0.75); GameTooltip:Hide() end)
    ico:SetScript("OnClick", function()
        if BNB.TaskEditWindow and BNB.TaskEditWindow.Open then
            BNB.TaskEditWindow.Open(NoteID(), row._taskID, row)
        end
    end)
    return ico
end

-- One task row with every child it can need; FillTaskRow shows the ones a task uses.
local function CreateTaskRow(tsc)
    local row = CreateFrame("Button", nil, tsc)
    row._hoverBtns = {}

    -- Checkbox (scaled UICheckButtonTemplate)
    local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    cb:SetScale(TASK_CB_SCALE)
    cb:SetPoint("LEFT", row, "LEFT", 0, 0)
    cb:SetScript("OnClick", function(self, btn)
        if btn ~= "RightButton" and NoteID() then BNB.Task.ToggleTask(NoteID(), row._taskID) end
    end)
    -- Route right-clicks on the checkbox to the context menu
    cb:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    cb:HookScript("OnClick", function(_, btn)
        if btn == "RightButton" then
            cb:SetChecked(row._task.completed)  -- undo the toggle
            ShowRowMenu(row)
        end
    end)
    row._cb = cb

    -- Task text / inline editbox
    local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("LEFT",  cb,  "RIGHT", 2,  0)
    lbl:SetPoint("RIGHT", row, "RIGHT", -38, 0)   -- clear of X and toggle (ALL-109)
    lbl:SetJustifyH("LEFT")
    lbl:SetWordWrap(false)
    row._lbl = lbl

    -- Inline edit box (hidden until clicked)
    local eb = CreateFrame("EditBox", nil, row, "BackdropTemplate")
    BNB.EnsureBackdrop(eb)
    BNB.SetBackdrop(eb, 0.06, 0.06, 0.08, 0.95, 0.20, 0.20, 0.25, 1)
    eb:SetPoint("LEFT",  cb,  "RIGHT", 2,  0)
    eb:SetPoint("RIGHT", row, "RIGHT", -38, 0)
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
            GameTooltip:AddLine(row._task.text, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    lbl:SetScript("OnLeave", function() GameTooltip:Hide() end)
    lbl:SetScript("OnMouseDown", function(_, btn)
        if btn == "RightButton" then
            ShowRowMenu(row)
            return
        end
        lbl:Hide()
        eb:SetText(row._task.text)
        eb:Show()
        eb:SetFocus()
    end)
    eb:SetScript("OnEditFocusGained", function(self)
        _taskEdit = { id = row._taskID, eb = self }
    end)
    eb:SetScript("OnEnterPressed", function(self)
        _taskEdit = nil  -- edit ends here; the re-render below must not reopen it
        local T, task = BNB.Task, row._task
        local newText = self:GetText()
        if IsShiftKeyDown() then
            -- Shift+Enter: save current task and create a new sibling below it
            if newText ~= "" then
                T.UpdateTask(NoteID(), task.id, { text = newText })
                task.text = newText
            end
            self:ClearFocus()
            local sibID = T.AddTask(NoteID(), "", row._isSub and task.parentID or nil)
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
            T.DeleteTask(NoteID(), task.id)
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
        if row._task.text == "" then
            -- Escape on a never-saved empty task removes it
            BNB.Task.DeleteTask(NoteID(), row._taskID)
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
            local task = row._task
            local newText = self:GetText()
            if newText == "" then
                BNB.Task.DeleteTask(NoteID(), task.id)
            else
                BNB.Task.UpdateTask(NoteID(), task.id, { text = newText })
                task.text = newText
                lbl:SetText(newText)
                self:Hide(); lbl:Show()
            end
        end
    end)
    eb:SetScript("OnMouseUp", function(_, btn)
        if btn == "RightButton" then ShowRowMenu(row) end
    end)

    -- Delete X left of the toggle slot, on every row, shown on hover. Deletes the
    -- task (and its sub-tasks) without a confirm, like the context menu.
    local delBtn = CreateFrame("Button", nil, row)
    delBtn:SetSize(14, 14)
    delBtn:SetPoint("RIGHT", row, "RIGHT", -20, 0)   -- one column on every row, left of the toggle slot
    local delN = delBtn:CreateTexture(nil, "ARTWORK"); delN:SetAllPoints()
    delN:SetTexture(ASSETS .. "Buttons\\bt-close-normal")
    local delH = delBtn:CreateTexture(nil, "ARTWORK"); delH:SetAllPoints()
    delH:SetTexture(ASSETS .. "Buttons\\bt-close-hover"); delH:Hide()
    delBtn:SetScript("OnEnter", function(self)
        delH:Show(); delN:Hide()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["REFBOX_TASK_ROW_DELETE_TIP"], 1, 1, 1)
        GameTooltip:Show()
    end)
    delBtn:SetScript("OnLeave", function()
        delH:Hide(); delN:Show(); GameTooltip:Hide()
    end)
    delBtn:SetScript("OnClick", function()
        GameTooltip:Hide()
        BNB.Task.DeleteTask(NoteID(), row._taskID)
        RenderTaskPanel()
        ApplyTaskLayout(RBFrame())
    end)
    delBtn:Hide()
    row._delBtn = delBtn

    -- Sub-task toggle (top-level tasks with sub-tasks only).
    -- Expanded : v  → click collapses.   Collapsed : >  → click expands.
    -- Without sub-tasks the toggle stays hidden but keeps its slot, so the
    -- hover + sits where the + of a task with sub-tasks sits (ALL-109).
    local togBtn = CreateFrame("Button", nil, row)
    togBtn:SetSize(14, 14)
    togBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)   -- furthest right (Dukul 2026-09-27)
    local togN = togBtn:CreateTexture(nil, "ARTWORK"); togN:SetAllPoints()
    togBtn:SetScript("OnClick", function()
        -- Toggle collapse/expand, persist state
        row._expanded = not row._expanded
        if row._expanded then
            _collapsedTasks[row._taskID] = nil
        else
            _collapsedTasks[row._taskID] = true
        end
        RenderTaskPanel()
        ApplyTaskLayout(RBFrame())
    end)
    togBtn:SetScript("OnMouseUp", function(_, btn)
        if btn == "RightButton" then ShowRowMenu(row) end
    end)
    row._togBtn, row._togTex = togBtn, togN

    -- + sub-task button: top-level rows only, hover only, with or without
    -- sub-tasks (ALL-109, Dukul 2026-09-27).
    local subAddBtn = CreateFrame("Button", nil, row)
    subAddBtn:SetSize(14, 14)
    subAddBtn:SetPoint("RIGHT", delBtn, "LEFT", -2, 0)
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
        local parentID = row._taskID
        local subID = BNB.Task.AddTask(NoteID(), "", parentID)
        if subID then
            _collapsedTasks[parentID] = nil
            RenderTaskPanel()
            ApplyTaskLayout(RBFrame())
            BNB.FocusTaskEditBox(subID)
        end
    end)
    subAddBtn:SetScript("OnMouseUp", function(_, btn)
        if btn == "RightButton" then ShowRowMenu(row) end
    end)
    subAddBtn:Hide()
    row._subAddBtn = subAddBtn

    -- Situation and reset icons, on both top-level and sub-tasks.
    row._sitIco = MakeRowIcon(row, ASSETS .. "UI\\ui-situation", function(task)
        return string.format(L["REFBOX_TASK_SITUATION_FMT"], task.situation or "")
    end)
    row._rstIco = MakeRowIcon(row, ASSETS .. "UI\\ui-repeat", function(task)
        return task.resetType == "daily" and L["REFBOX_TASK_RESET_DAILY_TIP"] or L["REFBOX_TASK_RESET_WEEKLY_TIP"]
    end)

    -- Show the hover buttons while the pointer is anywhere on the row. The
    -- children take the mouse from the row, so every mouse-enabled child
    -- starts the watch too; it hides them once the pointer is off the row.
    local function HoverWatch(self)
        if self:IsMouseOver() then return end
        for _, b in ipairs(self._hoverBtns) do b:Hide() end
        self:SetScript("OnUpdate", nil)
    end
    local function StartHover()
        for _, b in ipairs(row._hoverBtns) do b:Show() end
        row:SetScript("OnUpdate", HoverWatch)
    end
    row:HookScript("OnEnter", StartHover)
    for _, child in ipairs({ row:GetChildren() }) do
        local ok, motion = pcall(child.IsMouseMotionEnabled or child.IsMouseEnabled, child)
        if ok and motion then child:HookScript("OnEnter", StartHover) end
    end
    pcall(lbl.HookScript, lbl, "OnEnter", StartHover)   -- the label takes the mouse too

    row:SetScript("OnMouseUp", function(_, btn)
        if btn == "RightButton" then ShowRowMenu(row) end
    end)
    return row
end

-- Point a pooled row at a task. Returns the row height and, for a top-level
-- task, its sub-tasks.
local function FillTaskRow(row, task, isSubTask, y)
    local T     = BNB.Task
    local tsc   = row:GetParent()
    local TASK_ROW_H, TASK_SUBROW_H = GetTaskSpacing()
    local rowH  = isSubTask and TASK_SUBROW_H or TASK_ROW_H
    local xOff  = isSubTask and (T.SUBTASK_INDENT or 14) or 0
    local clr   = T.GetTaskColor(task)

    row._task, row._taskID, row._isSub = task, task.id, isSubTask
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT",  tsc, "TOPLEFT",  PAD + xOff, y)
    row:SetPoint("TOPRIGHT", tsc, "TOPRIGHT", -PAD, y)
    row:SetHeight(rowH)
    row:SetScript("OnUpdate", nil)
    row._cb:SetChecked(task.completed)

    local subTasks = not isSubTask and T.GetSubTasks(NoteID(), task.id) or nil

    -- For top-level tasks with sub-tasks, prefix with (done/total)
    local lbl = row._lbl
    lbl:SetHeight(rowH)
    lbl:SetTextColor(clr.r, clr.g, clr.b)
    local lblText = task.text ~= "" and task.text or "(empty)"
    if subTasks and #subTasks > 0 then
        local subDone = 0
        for _, s in ipairs(subTasks) do if s.completed then subDone = subDone + 1 end end
        local cntClr = (subDone == #subTasks) and "|cff66dd66" or "|cffaaaaaa"
        lblText = cntClr .. "(" .. subDone .. "/" .. #subTasks .. ")|r " .. lblText
        -- When collapsed, append sub-task count so it's visible without expanding
        if _collapsedTasks[task.id] then
            lblText = lblText .. " |cff888888(" .. #subTasks .. ")|r"
        end
    end
    lbl:SetText(lblText)
    lbl:Show()
    row._editBox:SetHeight(rowH - 2)
    row._editBox:Hide()

    -- Hover-only buttons (ALL-109): the X everywhere, the + on top-level rows.
    local hover = row._hoverBtns
    wipe(hover)
    hover[1] = row._delBtn
    row._delBtn:Hide()
    row._subAddBtn:Hide()
    -- rightAnchor: the R/S icons chain leftward from it, the + sub-task
    -- button on top-level rows, the delete X on sub-task rows.
    local rightAnchor = row._delBtn
    if isSubTask then
        row._expanded = nil
        row._togBtn:Hide()
    else
        -- Collapse state persists across re-renders via _collapsedTasks.
        -- Default: expanded when sub-tasks exist, irrelevant when none.
        local hasSubTasks = #subTasks > 0
        row._expanded = hasSubTasks and not _collapsedTasks[task.id]
        row._togTex:SetTexture(ASSETS .. "Buttons\\" ..
            (row._expanded and "bt-down-normal" or "bt-right-normal"))
        row._togBtn:SetShown(hasSubTasks)
        hover[2] = row._subAddBtn
        rightAnchor = row._subAddBtn
    end

    local sitIco, rstIco = row._sitIco, row._rstIco
    if task.situation and task.situation ~= "" then
        sitIco:ClearAllPoints()
        sitIco:SetPoint("RIGHT", rightAnchor, "LEFT", -2, 0)
        sitIco:SetAlpha(0.75)
        sitIco:Show()
        rightAnchor = sitIco
    else
        sitIco:Hide()
    end
    if task.resetType and task.resetType ~= "" and task.resetType ~= "none" then
        rstIco:ClearAllPoints()
        rstIco:SetPoint("RIGHT", rightAnchor, "LEFT", -2, 0)
        rstIco:SetAlpha(0.75)
        rstIco:Show()
    else
        rstIco:Hide()
    end
    return rowH, subTasks
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

    -- Release the pooled rows of this scroll child (a rebuilt Reference Box
    -- window has a new scroll child, and with it a new pool).
    local pool = tsc._taskPool
    if not pool then pool = {}; tsc._taskPool = pool end
    for _, row in ipairs(pool) do row:Hide() end
    wipe(_taskRows)
    _taskTeardown = wasTeardown
    _taskEdit = nil
    _taskRowsNoteID, _taskRowsGen = nil, _taskDataGen

    local hasTasks = BNB.Task and BNB.Task.Shows(NoteID())
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
    local completedPos = (db and db.taskCompletedPosition) or BNB.DEFAULTS.taskCompletedPosition
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

    -- Add task (+) and [GR][GS] icons — parented to pnl so they don't scroll.
    local pnlLevel = taskPnl:GetFrameLevel() + 56
    local hdr = TaskHeaderButtons(taskPnl)
    hdr.add:SetFrameLevel(pnlLevel)
    local hasSit = globalSit and globalSit ~= ""
    local hasRst = globalRst and globalRst ~= ""
    SetHdrIcon(hdr.sit, pnlLevel, hasSit,
        string.format(L["REFBOX_TASK_GLOBAL_SIT_FMT"], globalSit or ""),
        L["REFBOX_TASK_GLOBAL_SIT_NONE"])
    SetHdrIcon(hdr.rst, pnlLevel, hasRst,
        string.format(L["REFBOX_TASK_GLOBAL_RST_FMT"], globalRst or ""),
        L["REFBOX_TASK_GLOBAL_RST_NONE"])

    -- ── Task rows ────────────────────────────────────────────────────────────
    local y = -4   -- small top pad; header is now fixed on pnl, not tsc
    local _, _, TASK_ROW_GAP = GetTaskSpacing()

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

    local used = 0
    local function RenderTaskRow(task, isSubTask)
        used = used + 1
        local row = pool[used]
        if not row then row = CreateTaskRow(tsc); pool[used] = row end
        local rowH, subTasks = FillTaskRow(row, task, isSubTask, y)
        row:Show()
        _taskRows[#_taskRows + 1] = row
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
    if RBFrame() and RBFrame():IsShown() and RBMode() ~= "attachments" and HasModel(NoteID()) then
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
                    StartTaskEdit(subID, "")
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

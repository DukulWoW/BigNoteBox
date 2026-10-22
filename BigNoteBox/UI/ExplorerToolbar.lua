-- BigNoteBox UI/ExplorerToolbar.lua -- The explorer view's tool buttons (ALL-414 S2)
--
-- In the main window's toolbar strip, right of the view switch (or the back
-- arrow in its place), while the explorer grid shows (Dukul, 2026-10-20: the
-- two-row tool row over the grid wasted space and looked messy):
--   New (menu), Quick note | Copy, Move (menu), Delete, Rename, Pin,
--   Favorite | Share (menu), Export (menu) | Sort (menu), the order, View
--   (menu), Select all | More (what does not fit) | Search
-- The search icon opens the note list's own search row (BNB.DockListSearch:
-- one search and one set of filters for both views) over the buttons, the
-- favourite / task / reset buttons at its right end; it stays lit while a
-- search or filter is on. Closing the field (its icon, or Esc in the box or
-- the window) clears the search and filters (Dukul, 2026-10-20). The note actions work on the picked tiles and grey
-- out without the picks they need. Each button is icon only or icon + label
-- (spec.label): Dukul tries the mix in game ("if it looks weird, we can go
-- back to just icons or just buttons"). Icons: Assets/Explorer/ex-<name>.tga,
-- white 64 x 64 art tinted like the list's UI icons; a copy of
-- ex-placeholder.tga stands in until Dukul draws one.
--
-- Built by ExplorerView.lua's EX.BuildHeader through BNB._ExplorerKit:
--   K.BuildStrip(f, lead)   K.LayoutToolRow()   K.UpdateToolRow()
--   K.OnPicks()   K.SearchButton()   K.CloseSearch()
--------------------------------------------------------------------------------

local BNB = BigNoteBox
local L   = BNB.L
local K   = BNB._ExplorerKit
local EX  = BNB.Explorer

local ART      = "Interface\\AddOns\\BigNoteBox\\Assets\\Explorer\\"
local ARROW    = ART .. "ex-chevron-down"
local BTN_H    = 24
local ICON     = 18
local BTN_PAD  = 5
local BTN_GAP  = 2
local ARROW_SZ = 10
local SEP_W    = 9
local LEAD_W   = 28     -- the switch / back arrow before the buttons
local TB_GAP   = 6      -- room kept before the right-hand icons' menu button
local SEARCH_SZ = 20
local SEARCH_MIN = 200  -- the open search field is never narrower

local _bar, _search, _searchLit, _host, _more
local _items = {}        -- in order: { btn = b } or { sep = tex }
local _overflow = {}     -- specs that did not fit (the More menu)
local _searchOpen = false

-- ── The picks ───────────────────────────────────────────────────────────────
-- Notes only (Copy, Move, Pin, Favorite); folders join Delete and Rename;
-- Share / Export take the notes in picked folders too (Dukul, 2026-10-21)
local function Ids() return K.Picked() end
local function Count() return #K.Picked() end
local function FolderCount() return #K.PickedFolders() end
local function AnyPick() return Count() + FolderCount() > 0 end
local function OnlyOne()
    local ids = K.Picked()
    return #ids == 1 and FolderCount() == 0 and ids[1] or nil
end
local function OnlyFolder()
    local f = K.PickedFolders()
    return #f == 1 and Count() == 0 and f[1] or nil
end
local function DeepOne()
    local ids = K.PickedNotesDeep()
    return #ids == 1 and ids[1] or nil
end

-- Delete: notes alone keep their own confirm; with folders one confirm for
-- all (folders deleted, their notes back to the list; notes as the trash says)
local function DeletePicked()
    local notes, fids = K.Picked(), K.PickedFolders()
    if #fids == 0 then BNB.ConfirmDeleteNotes(notes, false); return end
    local FD = BNB.Folders
    if not FD then return end
    local text
    if #notes == 0 and #fids == 1 then
        text = string.format(L["FOLDER_DELETE_CONFIRM"], FD.Text(fids[1]), FD.CountAll(fids[1]))
    elseif #notes == 0 then
        text = string.format(L["EXPLORER_DEL_FOLDERS_FMT"], #fids)
    else
        local trash = BNB.TrashEnabled and BNB.TrashEnabled()
        text = string.format(L[trash and "EXPLORER_DEL_MIXED_TRASH_FMT" or "EXPLORER_DEL_MIXED_FMT"], #fids, #notes)
    end
    StaticPopup_Show("BNB_MULTI_CONFIRM", text, nil, function()
        for _, fid in ipairs(fids) do FD.Delete(fid) end
        if #notes > 0 and BNB.DeleteNotes then BNB.DeleteNotes(notes, false) end
    end)
end
local function Locked(id)
    local NK = BNB._NoteListKit
    local n = BNB.GetNote(id)
    return n and NK and NK.NoteIsLocked and NK.NoteIsLocked(n) or false
end
-- Every picked note has field set (Pin / Unpin, Favorite / Unfavorite)
local function AllHave(field)
    local ids = K.Picked()
    if #ids == 0 then return false end
    for _, id in ipairs(ids) do
        local n = BNB.GetNote(id)
        if not (n and n[field]) then return false end
    end
    return true
end
local function SetAll(field, on)
    for _, id in ipairs(K.Picked()) do
        if BNB.GetNote(id) then
            if on then BNB.UpdateNote(id, { [field] = true })
            else BNB.UpdateNote(id, { _clear = { field } }) end
        end
    end
end

-- ── Rename ──────────────────────────────────────────────────────────────────
local function PopupEditBox(self) return (self.GetEditBox and self:GetEditBox()) or self.editBox or self.EditBox end

local function ApplyRename(id, text)
    local note = BNB.GetNote(id)
    if not note then return end
    text = (text or ""):match("^%s*(.-)%s*$")
    if text == (note.title or "") then return end
    -- The open note: its unsaved text first, then the editor shows the new title
    local open = BNB._currentNoteID == id
    if open then BNB.SaveCurrentNote() end
    BNB.UpdateNote(id, { title = text })
    if open and BNB.LoadNoteInEditor then BNB.LoadNoteInEditor(id) end
end

StaticPopupDialogs["BNB_EXPLORER_RENAME"] = {
    preferredIndex = 3,
    text = "%s", hasEditBox = true, maxLetters = 200,   -- the editor's title box
    button1 = OKAY, button2 = CANCEL,
    OnShow = function(self, id)
        local eb = PopupEditBox(self)
        local n = id and BNB.GetNote(id)
        if eb then eb:SetText(n and n.title or ""); eb:HighlightText(); eb:SetFocus() end
    end,
    OnAccept = function(self, id)
        local eb = PopupEditBox(self)
        ApplyRename(id, eb and eb:GetText())
    end,
    -- Read the text before hiding: hiding clears the edit box (as BNB_FOLDER_NAME)
    EditBoxOnEnterPressed = function(eb)
        local p = eb:GetParent()
        local id, text = p.data, eb:GetText()
        p:Hide()
        ApplyRename(id, text)
    end,
    EditBoxOnEscapePressed = function(eb) eb:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

local function Rename()
    local fid = OnlyFolder()
    if fid then BNB.PromptFolderName({ mode = "rename", id = fid }); return end
    local id = OnlyOne()
    local n = id and BNB.GetNote(id)
    if not n then return end
    local title = (n.title ~= "" and n.title or L["UNTITLED"]):gsub("|", "||")
    StaticPopup_Show("BNB_EXPLORER_RENAME", string.format(L["EXPLORER_RENAME_PROMPT"], title), nil, id)
end

-- ── Buttons ─────────────────────────────────────────────────────────────────
-- spec: icon (name or function), title (locale key or function), sub
-- (locale key or function), label (show the title beside the icon), enabled
-- (function), needs (locale key or function: why it is grey), fn or menu(root)
local SPECS = {
    { icon = "ex-new", title = "EXPLORER_TB_NEW", sub = "EXPLORER_TB_NEW_TIP", label = true,
      menu = function(root)
        root:CreateButton(L[K.UserFolder() and "FOLDER_CM_NEW_NOTE" or "EXPLORER_TB_NEW_NOTE"],
            K.NewNoteHere, { iconTex = ART .. "ex-new-note", iconGold = true })
        if BNB.FoldersEnabled() then
            root:CreateButton(L["FOLDER_CM_NEW_FOLDER"], K.NewFolder, { iconTex = ART .. "ex-new-folder", iconGold = true })
            -- With notes picked: a new folder holding them (Dukul, 2026-10-22)
            local n = #K.Picked()
            if n > 0 then
                root:CreateDivider()
                root:CreateButton(string.format(L["EXPLORER_NEW_FOLDER_PICKS_FMT"], n), K.NewFolderWithPicks,
                    { iconTex = ART .. "ex-new-folder", iconGold = true,
                      tip = string.format(L["EXPLORER_NEW_FOLDER_PICKS_FMT"], n),
                      tipSub = string.format(L["EXPLORER_NEW_FOLDER_PICKS_TIP"], n) })
            end
        end
      end },
    { icon = "ex-quick-note", title = "NL_QUICK_NOTE_BTN", sub = "NL_QUICK_NOTE_TIP_SUB",
      fn = function()
        if InCombatLockdown() then BNB:Print(L["COMBAT_BLOCKED"]); return end
        BNB.SaveCurrentNote()
        local id = BNB.CreateQuickNote()
        if id then BNB.ShowQuickNote(id) end
      end },
    "sep",
    { icon = "ex-copy", title = "EXPLORER_TB_COPY", sub = "EXPLORER_TB_COPY_TIP",
      enabled = function() return Count() > 0 end, needs = "EXPLORER_TB_NEED_PICK",
      fn = function() if BNB.OpenCopyMovePopupMulti then BNB.OpenCopyMovePopupMulti(Ids()) end end },
    { icon = "ex-move", title = "EXPLORER_TB_MOVE", sub = "EXPLORER_TB_MOVE_TIP",
      enabled = function() return Count() > 0 end, needs = "EXPLORER_TB_NEED_PICK",
      menu = function(root)
        local ids = Ids()
        if BNB.FoldersEnabled() and BNB.AddMoveToFolderMenu then
            BNB.AddMoveToFolderMenu(root, ids, nil, true)
            root:CreateDivider()
        end
        root:CreateButton(L["NL_CTX_COPY_MOVE"], function() BNB.OpenCopyMovePopupMulti(ids) end,
            { icon = "copy-move" })
      end },
    { icon = "ex-delete", title = "EXPLORER_TB_DELETE", sub = "EXPLORER_TB_DELETE_TIP",
      enabled = AnyPick, needs = "EXPLORER_TB_NEED_PICK",
      fn = DeletePicked },
    { icon = "ex-rename", title = "EXPLORER_TB_RENAME", sub = "EXPLORER_TB_RENAME_TIP",
      enabled = function()
        if OnlyFolder() then return true end
        local id = OnlyOne(); return id ~= nil and not Locked(id)
      end,
      needs = function()
        local id = OnlyOne()
        if id and Locked(id) then return L["EXPLORER_TB_LOCKED"] end
        return L["EXPLORER_TB_NEED_ONE_ITEM"]
      end,
      fn = Rename },
    { icon = "ex-pin", title = function() return L[AllHave("pinned") and "EXPLORER_TB_UNPIN" or "EXPLORER_TB_PIN"] end,
      sub = "EXPLORER_TB_PIN_TIP",
      enabled = function() return Count() > 0 end, needs = "EXPLORER_TB_NEED_PICK",
      fn = function() SetAll("pinned", not AllHave("pinned")) end },
    { icon = "ex-favorite", title = function() return L[AllHave("favorited") and "EXPLORER_TB_UNFAV" or "EXPLORER_TB_FAV"] end,
      sub = "EXPLORER_TB_FAV_TIP",
      enabled = function() return Count() > 0 end, needs = "EXPLORER_TB_NEED_PICK",
      fn = function() SetAll("favorited", not AllHave("favorited")) end },
    "sep",
    { icon = "ex-share", title = "EXPLORER_TB_SHARE", sub = "EXPLORER_TB_SHARE_TIP",
      enabled = function() return DeepOne() ~= nil end, needs = "EXPLORER_TB_NEED_ONE",
      menu = function(root)
        local id = DeepOne()
        if not id then return end
        root:CreateButton(L["NL_CTX_SHARE"], function()
            if BNB.OpenShareWindow then BNB.OpenShareWindow(id) end
        end, { icon = "share" })
        root:CreateButton(L["SEND_TITLE"], function()
            if BNB.OpenSendToChat then BNB.OpenSendToChat(id) end
        end, { icon = "chat" })
      end },
    { icon = "ex-export", title = "EXPLORER_TB_EXPORT", sub = "EXPLORER_TB_EXPORT_TIP",
      enabled = function() return #K.PickedNotesDeep() > 0 end, needs = "EXPLORER_TB_NEED_PICK",
      menu = function(root)
        local ids = K.PickedNotesDeep()
        local one = #ids == 1 and ids[1] or nil
        root:CreateButton(L["NL_CM_EXPORT_JSON"], function()
            if one then BNB.ExportNoteJSON(one) else BNB.ExportMultiJSON(ids) end
        end, { icon = "export-json" })
        root:CreateButton(L["NL_CM_EXPORT_MD"], function()
            if one then BNB.ExportNoteMD(one) else BNB.ExportMultiMD(ids) end
        end, { icon = "export-markdown" })
        if one then
            -- One note: the three HTML styles, as its right-click menu
            local h = root:CreateButton(L["NL_CM_EXPORT_HTML"], nil, { icon = "export-html" })
            h:CreateButton(L["CFG_EXPORT_HTML_NOTEONLY"], function() BNB.ExportNoteHTML(one, "noteonly") end)
            h:CreateButton(L["CFG_EXPORT_HTML_PLAIN"],    function() BNB.ExportNoteHTML(one, "plain") end)
            h:CreateButton(L["CFG_EXPORT_HTML_STYLIZED"], function() BNB.ExportNoteHTML(one, "stylized") end)
        else
            root:CreateButton(L["NL_CM_EXPORT_HTML"], function() BNB.ExportMultiHTML(ids) end,
                { icon = "export-html" })
        end
      end },
    "sep",
    { icon = function() return K.SortIcon() end, title = "EXPLORER_TB_SORT", sub = "EXPLORER_TB_SORT_TIP", label = true,
      menu = function(root) K.FillSortMenu(root) end },
    { icon = function() return BigNoteBoxDB.sortAsc and "ex-sort-ascending" or "ex-sort-descending" end,
      title = "EXPLORER_TB_ORDER",
      sub = function()
        return string.format(L["EXPLORER_TB_ORDER_TIP_FMT"],
            L[BigNoteBoxDB.sortAsc and "DIR_MODE_ASC" or "DIR_MODE_DESC"])
      end,
      enabled = function() return (BigNoteBoxDB.sortBy or BNB.DEFAULTS.sortBy) ~= "custom" end,
      needs = "EXPLORER_TB_ORDER_CUSTOM",
      fn = function() BNB.SetNoteSort(nil, not BigNoteBoxDB.sortAsc) end },
    { icon = function() return K.ViewIcon() end, title = "EXPLORER_TB_VIEW", sub = "EXPLORER_TB_VIEW_TIP", label = true,
      menu = function(root) K.FillViewMenu(root) end },
    { icon = "ex-select-all", title = function() return K.SelectAllText() end, sub = "EXPLORER_TB_SELECT_ALL_TIP",
      enabled = function() return K.CanPick() end,
      fn = function() K.SelectAll() end },
}

local function Text(v)
    if type(v) == "function" then return v() end
    if v == nil then return nil end
    return L[v]
end

local function Enabled(spec) return not spec.enabled or spec.enabled() end

local function Run(spec, owner)
    if not Enabled(spec) then return end
    GameTooltip:Hide()
    if spec.menu then BNB.ContextMenu.Open(owner, spec.menu) else spec.fn() end
end

local function ShowTip(self, spec)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(Text(spec.title) or "", 1, 1, 1)
    local sub = Text(spec.sub)
    if sub then GameTooltip:AddLine(sub, 0.85, 0.85, 0.85, true) end
    if not Enabled(spec) and spec.needs then
        GameTooltip:AddLine(Text(spec.needs), 1, 0.45, 0.45, true)
    end
    GameTooltip:Show()
end

-- Width from what the button shows; measured at each layout (a bundled font
-- can measure 0 until it has loaded, ALL-16)
local function SizeButton(b)
    local w = BTN_PAD + ICON
    if b._fs then
        local sw = b._fs.GetUnboundedStringWidth and b._fs:GetUnboundedStringWidth() or b._fs:GetStringWidth()
        w = w + 4 + math.ceil(sw or 0)
    end
    if b._ar then
        b._ar:ClearAllPoints()
        b._ar:SetPoint("LEFT", b, "LEFT", w + 2, 0)
        w = w + 2 + ARROW_SZ
    end
    b:SetWidth(w + BTN_PAD)
end

local function PaintButton(b)
    local spec = b._spec
    local on = Enabled(spec)
    b:SetEnabled(on)
    local icon = type(spec.icon) == "function" and spec.icon() or spec.icon
    b._ic:SetTexture(ART .. icon)
    b._ic:SetDesaturated(not on)
    b._ic:SetAlpha(on and 1 or 0.35)
    if b._fs then
        b._fs:SetText(Text(spec.title) or "")
        b._fs:SetAlpha(on and 1 or 0.45)
    end
    if b._ar then b._ar:SetAlpha(on and 1 or 0.35) end
end

local function MakeButton(parent, spec)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(BTN_H)
    b._spec = spec
    local hl = b:CreateTexture(nil, "BACKGROUND")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    hl:Hide()
    local ic = b:CreateTexture(nil, "ARTWORK")
    ic:SetSize(ICON, ICON)
    ic:SetPoint("LEFT", b, "LEFT", BTN_PAD, 0)
    BNB.TintUIIcon(ic)
    b._ic = ic
    if spec.label then
        local fs = b:CreateFontString(nil, "OVERLAY", "BNBFontHighlightSmall")
        fs:SetPoint("LEFT", ic, "RIGHT", 4, 0)
        fs:SetWordWrap(false)
        fs:SetTextColor(BNB.TextWhite(1))
        b._fs = fs
    end
    if spec.menu and not spec.noArrow then   -- a small arrow: the button opens a menu
        local ar = b:CreateTexture(nil, "ARTWORK")
        ar:SetSize(ARROW_SZ, ARROW_SZ)
        ar:SetTexture(ARROW)
        BNB.TintUIIcon(ar)
        b._ar = ar
    end
    b:SetScript("OnEnter", function(self) hl:Show(); ShowTip(self, self._spec) end)
    b:SetScript("OnLeave", function(self)
        hl:Hide()
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    b:SetScript("OnClick", function(self) Run(self._spec, self) end)
    b._cmDropDown = true   -- a menu opens under the button, not at the pointer
    PaintButton(b)
    SizeButton(b)
    return b
end

local MORE_SPEC = { icon = "ex-more", title = "EXPLORER_TB_MORE", sub = "EXPLORER_TB_MORE_TIP", noArrow = true,
    menu = function(root)
        for _, spec in ipairs(_overflow) do
            local on = Enabled(spec)
            if spec.menu then
                local sub = root:CreateButton(Text(spec.title), nil, { disabled = not on })
                if on then spec.menu(sub) end
            else
                root:CreateButton(Text(spec.title), function() Run(spec) end, { disabled = not on })
            end
        end
    end }

-- ── Search ──────────────────────────────────────────────────────────────────
local function Filtering() return BNB.IsListFiltering and BNB.IsListFiltering() or false end

local function PaintSearch()
    if not _search then return end
    _searchLit:SetShown(_searchOpen or Filtering())
end

-- ── Layout ──────────────────────────────────────────────────────────────────
-- The buttons left to right; a separator shows only before a button that
-- fits. Returns the x where the row ends
local function Pass(limit)
    wipe(_overflow)
    local x, full, pending, any = 0, false, nil, false
    for _, it in ipairs(_items) do
        if it.sep then
            it.sep:Hide()
            if not full and any then pending = it.sep end
        else
            local b = it.btn
            SizeButton(b)
            local w = b:GetWidth()
            local extra = pending and SEP_W or 0
            if not full and x + extra + w <= limit then
                if pending then
                    pending:ClearAllPoints()
                    pending:SetPoint("LEFT", _bar, "LEFT", x + math.floor(SEP_W / 2), 0)
                    pending:Show()
                    x = x + SEP_W
                    pending = nil
                end
                b:ClearAllPoints()
                b:SetPoint("LEFT", _bar, "LEFT", x, 0)
                b:Show()
                x = x + w + BTN_GAP
                any = true
            else
                full = true
                pending = nil
                b:Hide()
                _overflow[#_overflow + 1] = b._spec
            end
        end
    end
    return x
end

function K.LayoutToolRow()
    if not _bar then return end
    local show = EX.Mode() == "grid"
    _bar:SetShown(show)
    _search:SetShown(show)
    if not show then return end
    -- The row stops short of the right-hand icons' menu button; the other
    -- right-hand icons give way to it (BNB.ApplyToolbarIcons)
    local bl, menu = _bar:GetLeft(), BNB._toolbarMenuBtn
    local ml = menu and menu:GetLeft()
    if not (bl and ml) then return end
    local limit = math.max(0, ml - bl - TB_GAP - SEARCH_SZ - 6)
    SizeButton(_more)
    local x = Pass(limit)
    if #_overflow > 0 then
        x = Pass(limit - _more:GetWidth() - BTN_GAP)
        _more:ClearAllPoints()
        _more:SetPoint("LEFT", _bar, "LEFT", x, 0)
        _more:Show()
        x = x + _more:GetWidth() + BTN_GAP
    else
        _more:Hide()
    end
    _bar:SetWidth(math.max(1, limit))
    -- The list's search row, borrowed (hidden with the field while closed)
    if BNB.DockListSearch then BNB.DockListSearch(_host, K.CloseSearch) end
    if _searchOpen then
        -- The field over the buttons, as wide as they are (at least SEARCH_MIN)
        x = math.min(math.max(x, SEARCH_MIN), limit)
        for _, it in ipairs(_items) do (it.btn or it.sep):Hide() end
        _more:Hide()
        _host:SetWidth(math.max(1, x - 4))
        _host:Show()
    else
        _host:Hide()
    end
    _search:ClearAllPoints()
    _search:SetPoint("LEFT", _bar, "LEFT", x + 2, 0)
    PaintSearch()
end

local function SetSearchOpen(open)
    _searchOpen = open and true or false
    -- Closing clears the search and every filter, as the reset button
    if not _searchOpen and BNB.ResetListFilters then BNB.ResetListFilters() end
    K.LayoutToolRow()
    if BNB.ApplyToolbarIcons then BNB.ApplyToolbarIcons() end
    if _searchOpen and BNB.FocusListSearch then BNB.FocusListSearch() end
end

-- Esc: closes the open search field (true), else nothing to close (false)
function K.CloseSearch()
    if not _searchOpen then return false end
    SetSearchOpen(false)
    return true
end

function K.UpdateToolRow()
    if not _bar then return end
    for _, it in ipairs(_items) do
        if it.btn then PaintButton(it.btn) end
    end
    PaintButton(_more)
    PaintSearch()
    -- A tooltip open over a button follows (Pin -> Unpin)
    local owner = GameTooltip:IsShown() and GameTooltip:GetOwner()
    if owner and owner._spec and owner:IsMouseOver() then ShowTip(owner, owner._spec) end
end

K.OnPicks = K.UpdateToolRow

function K.SearchButton() return _search end

-- ── Build ───────────────────────────────────────────────────────────────────
-- f = the main window; lead = the frame the switch / back arrow sit on
function K.BuildStrip(f, lead)
    _bar = CreateFrame("Frame", nil, f)
    _bar:SetHeight(BTN_H)
    _bar:SetPoint("LEFT", lead, "LEFT", LEAD_W, 0)
    _bar:SetWidth(1)
    _bar:Hide()

    for _, spec in ipairs(SPECS) do
        if spec == "sep" then
            local t = _bar:CreateTexture(nil, "ARTWORK")
            t:SetSize(1, BTN_H - 8)
            local r, g, b = BNB.HeaderColor()
            t:SetColorTexture(r, g, b, 0.35)
            t:Hide()
            _items[#_items + 1] = { sep = t }
        else
            _items[#_items + 1] = { btn = MakeButton(_bar, spec) }
        end
    end
    _more = MakeButton(_bar, MORE_SPEC)
    _more:Hide()

    -- The search field: the list's search row lives in it while borrowed
    _host = CreateFrame("Frame", nil, _bar)
    _host:SetHeight(BTN_H)
    _host:SetPoint("LEFT", _bar, "LEFT", 0, 0)
    _host:Hide()

    -- The search icon: on the window itself (not the row), so the right-hand
    -- icons can measure it (BNB.ApplyToolbarIcons reads IsShown)
    local s = CreateFrame("Button", nil, f)
    s:SetSize(SEARCH_SZ, SEARCH_SZ)
    local lit = s:CreateTexture(nil, "BACKGROUND")
    lit:SetPoint("TOPLEFT", -3, 3)
    lit:SetPoint("BOTTOMRIGHT", 3, -3)
    lit:SetTexture(BNB.UI_HOVER_TEX)
    BNB.TintUIIcon(lit)
    lit:Hide()
    _searchLit = lit
    local tx = s:CreateTexture(nil, "ARTWORK")
    tx:SetAllPoints()
    tx:SetTexture(ART .. "ex-search")
    BNB.TintUIIcon(tx)
    BNB.AddUIIconHover(s, tx)
    s:SetScript("OnClick", function() SetSearchOpen(not _searchOpen) end)
    s:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L[_searchOpen and "EXPLORER_SEARCH_CLOSE" or "EXPLORER_SEARCH"], 1, 1, 1)
        GameTooltip:AddLine(L["EXPLORER_SEARCH_TIP"], 0.85, 0.85, 0.85, true)
        if Filtering() then GameTooltip:AddLine(L["EXPLORER_SEARCH_ON"], 0.4, 0.85, 0.4, true) end
        GameTooltip:Show()
    end)
    s:SetScript("OnLeave", function(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
    s:Hide()
    _search = s
end

-- BigNoteBox UI/FolderMenus.lua -- Menus and popups for note folders (ALL-510)
--
-- The data lives in Core/Folders.lua (BNB.Folders); this file is the player's
-- way in:
--   BNB.ShowFolderMenu(owner, id)       a folder header's right-click: New
--                                       note here, Rename, Colour, New folder,
--                                       Delete folder (confirm with the count)
--   BNB.ShowNotesHeaderMenu(owner)      the "Notes (N)" header's right-click
--   BNB.AddMoveToFolderMenu(root, ids, after)
--                                       "Move to folder" on a BNB.ContextMenu
--                                       builder: the note menu and Select mode
--   BNB.PromptFolderName(data)          name popup; data = { mode = "new" |
--                                       "rename", id, after(folderID) }
-- Moving notes into a folder opens it, so you see where they went.
--------------------------------------------------------------------------------

local BNB = BigNoteBox
local L   = BNB.L

local function F() return BNB.Folders end

local SW_W, SW_H = 46, 11   -- the colour swatch in a menu row, as TagColors

local function PopupEditBox(self) return (self.GetEditBox and self:GetEditBox()) or self.editBox or self.EditBox end

local function Err(msg) BNB:Print("|cffff5555" .. msg .. "|r") end

-- Menu rows about folders use Dukul's cm-folder symbol (2026-10-19), one for
-- every row: the list shows open / closed, a menu row only says "folder"

-- Notes into a folder (nil = out of folders); the folder opens
local function MoveInto(ids, id)
    F().Move(ids, id)
    if id then F().SetOpen(id, true) end
end

-- ── Name popup ──────────────────────────────────────────────────────────────
local function SubmitName(text, data)
    if not data then return end
    local FD = F()
    if data.mode == "rename" then
        local ok, err = FD.Rename(data.id, text)
        if not ok and err then Err(L[err]) end
        return
    end
    local name = (text or ""):match("^%s*(.-)%s*$")
    if name == "" then Err(L["FOLDER_ERR_EMPTY"]); return end
    local had = FD.FindByName(name)
    local id = FD.Create(name)
    if not id then return end
    if had then BNB:Print(string.format(L["FOLDER_EXISTS_USED"], FD.Text(id))) end
    if data.after then data.after(id) end
end

StaticPopupDialogs["BNB_FOLDER_NAME"] = {
    preferredIndex = 3,
    text = "%s", hasEditBox = true, maxLetters = 40,
    button1 = OKAY, button2 = CANCEL,
    OnShow = function(self, data)
        local eb = PopupEditBox(self)
        if eb then eb:SetText(data and data.text or ""); eb:HighlightText(); eb:SetFocus() end
    end,
    OnAccept = function(self, data)
        local eb = PopupEditBox(self)
        SubmitName(eb and eb:GetText(), data)
    end,
    -- Read the name before hiding: hiding the popup clears its edit box, so
    -- Enter always sent an empty name ("A folder needs a name", Dukul,
    -- 2026-10-19); OK reads it in OnAccept, before the hide
    EditBoxOnEnterPressed = function(eb)
        local p = eb:GetParent()
        local data, text = p.data, eb:GetText()
        p:Hide()
        SubmitName(text, data)
    end,
    EditBoxOnEscapePressed = function(eb) eb:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

function BNB.PromptFolderName(data)
    local prompt = L["FOLDER_NAME_NEW"]
    if data.mode == "rename" then
        local rec = F().Get(data.id)
        if not rec then return end
        prompt = string.format(L["FOLDER_NAME_RENAME"], rec.name)
        data.text = rec.name
    end
    StaticPopup_Show("BNB_FOLDER_NAME", prompt, nil, data)
end

-- ── Colour sub-menu: the tag colour palette, no game colours ───────────────
local function AddColorMenu(root, id)
    local TC  = BNB.TagColors
    local rec = F().Get(id)
    local cur = rec and rec.color
    local r, g, b = F().Color(id)
    local sub = root:CreateButton(L["TAGCOL_MENU"], nil, {
        iconTex = TC.DROP, iconColor = r and { r, g, b } or { 0.35, 0.35, 0.35 },
        tip = L["TAGCOL_MENU"], tipSub = L["FOLDER_COLOR_TIP"],
    })
    local function Label(text, on)
        if on then return string.format(L["TAGCOL_CURRENT_FMT"], text) end
        return text
    end
    sub:CreateButton(Label(L["TAGCOL_NONE"], cur == nil), function() F().SetColor(id, nil) end,
        { iconTex = TC.SWATCH, iconColor = { 0.30, 0.30, 0.30 }, iconW = SW_W, iconH = SW_H })
    sub:CreateDivider()
    for _, c in ipairs(TC.LIST) do
        local key = c.key
        sub:CreateButton(Label(L[c.label], cur == key), function() F().SetColor(id, key) end,
            { iconTex = TC.SWATCH, iconColor = { c.r, c.g, c.b }, iconW = SW_W, iconH = SW_H })
    end
end

-- ── Folder header menu ──────────────────────────────────────────────────────
local function NewNoteIn(id)
    local NND = BNB.NewNoteDialog
    if NND and NND.Open then NND.Open({ folder = id }) end
end

local function NewFolder()
    BNB.PromptFolderName({ mode = "new" })
end

function BNB.ShowFolderMenu(owner, id)
    if not BNB.FoldersEnabled() then return end   -- module off (ALL-514): catch-all
    local FD = F()
    local rec = FD.Get(id)
    if not rec then return end
    BNB.ContextMenu.Open(owner, function(root)
        root:CreateTitle(FD.Text(id))
        root:CreateDivider()
        root:CreateButton(L["FOLDER_CM_NEW_NOTE"], function() NewNoteIn(id) end, { icon = "create" })
        root:CreateButton(L["FOLDER_CM_RENAME"], function()
            BNB.PromptFolderName({ mode = "rename", id = id })
        end, { icon = "rename" })
        AddColorMenu(root, id)
        root:CreateDivider()
        root:CreateButton(L["FOLDER_CM_NEW_FOLDER"], NewFolder, { icon = "folder" })
        root:CreateDivider()
        root:CreateButton(L["FOLDER_CM_DELETE"], function()
            local n = FD.CountAll(id)
            StaticPopup_Show("BNB_MULTI_CONFIRM",
                string.format(L["FOLDER_DELETE_CONFIRM"], FD.Text(id), n), nil,
                function() FD.Delete(id) end)
        end, { icon = "trash", danger = true })
    end)
end

function BNB.ShowNotesHeaderMenu(owner)
    if not BNB.FoldersEnabled() then return end   -- its only row is New folder (ALL-514)
    BNB.ContextMenu.Open(owner, function(root)
        root:CreateButton(L["FOLDER_CM_NEW_FOLDER"], NewFolder, { icon = "folder" })
    end)
end

-- ── Move to folder ──────────────────────────────────────────────────────────
-- ids = the notes; after() runs once they moved (Select mode ends itself)
function BNB.AddMoveToFolderMenu(root, ids, after)
    local FD = F()
    if not FD or not BNB.FoldersEnabled() or not ids or #ids == 0 then return end   -- ALL-514
    -- The folder every note is in, false when they differ
    local common, anyIn = nil, false
    for i, noteID in ipairs(ids) do
        local fid = FD.Of(BNB.GetNote(noteID))
        if fid then anyIn = true end
        if i == 1 then common = fid elseif common ~= fid then common = false end
    end
    local function Done(id)
        return function()
            MoveInto(ids, id)
            if after then after() end
        end
    end
    local sub = root:CreateButton(L["FOLDER_CM_MOVE"], nil, { icon = "folder" })
    local list = FD.List()
    for _, f in ipairs(list) do
        local label = FD.Text(f.id)   -- the name in the folder's colour
        if common == f.id then label = string.format(L["TAGCOL_CURRENT_FMT"], label) end
        sub:CreateButton(label, Done(f.id),
            { icon = "folder", disabled = common == f.id })
    end
    if #list > 0 then sub:CreateDivider() end
    sub:CreateButton(L["FOLDER_CM_NEW_FOLDER"], function()
        BNB.PromptFolderName({ mode = "new", after = function(id)
            MoveInto(ids, id)
            if after then after() end
        end })
    end, { icon = "create" })
    sub:CreateButton(L["FOLDER_CM_NO_FOLDER"], Done(nil), { icon = "folder-no", disabled = not anyIn })   -- Dukul's cm-folder-no
end

-- ── System folders (ALL-511) ────────────────────────────────────────────────
-- A system note's right-click (list row, editor, anywhere ShowNoteContextMenu
-- is asked for one): Open, Copy to my notes, Hide this release. A system
-- folder header's: Show hidden releases, Hide this folder (its setting).
local function SYS() return BNB.SystemNotes end

-- A normal Global note with the system note's text, opened in the editor
function BNB.CopySystemNote(id)
    local newID = BNB.CopyNote(id)
    if not newID then return end
    if BNB.OpenNoteInMain then BNB.OpenNoteInMain(newID) end
    return newID
end

function BNB.ShowSystemNoteMenu(owner, id)
    local S = SYS()
    local note = S and S.Get(id)
    if not note then return end
    local p = S.Provider(note.system)
    BNB.ContextMenu.Open(owner, function(root)
        root:CreateTitle(note.title)
        root:CreateDivider()
        if BNB._currentNoteID ~= id then
            root:CreateButton(L["NL_CM_OPEN_EDITOR"], function()
                if BNB.OpenNoteInMain then BNB.OpenNoteInMain(id) end
            end, { icon = "editor" })
        end
        root:CreateButton(L["SYS_CM_COPY"], function() BNB.CopySystemNote(id) end,
            { icon = "duplicate", tip = L["SYS_CM_COPY"], tipSub = L["SYS_CM_COPY_TIP"] })
        if p and p.canHide then
            root:CreateDivider()
            root:CreateButton(L["SYS_CM_HIDE_RELEASE"], function() S.Hide(id) end,
                { tip = L["SYS_CM_HIDE_RELEASE"], tipSub = L["SYS_CM_HIDE_RELEASE_TIP"] })
        end
    end)
end

function BNB.ShowSystemFolderMenu(owner, key)
    local S = SYS()
    local p = S and S.Provider(key)
    if not p then return end
    BNB.ContextMenu.Open(owner, function(root)
        root:CreateTitle(L[p.name], { icon = F().ART_OPEN, crop = false,
            color = p.r and { r = p.r, g = p.g, b = p.b } or nil })
        root:CreateDivider()
        if p.canHide then
            local n = S.HiddenCount(key)
            root:CreateButton(string.format(L["SYS_CM_SHOW_HIDDEN_FMT"], n), function() S.ShowHidden(key) end,
                { disabled = n == 0 })
        end
        if p.setting then
            root:CreateButton(L["SYS_CM_HIDE_FOLDER"], function()
                if BigNoteBoxDB then BigNoteBoxDB[p.setting] = false end
                BNB:Print(string.format(L["SYS_HIDE_FOLDER_PRINT_FMT"], L[p.name]))
                BNB.SendMessage("SystemNotesChanged", key)
            end, { tip = L["SYS_CM_HIDE_FOLDER"], tipSub = L["SYS_CM_HIDE_FOLDER_TIP"] })
        end
    end)
end

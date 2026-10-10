-- BigNoteBox Features/Tldr.lua - the tl;dr module (ALL-372)
--
-- A note's tl;dr is one short line (note.tldr, Core/NoteFields.lua, at most
-- BNB.TLDR_MAX characters, cleaned by BNB.CleanTldr). It shows under the note
-- title, in the game tooltip of the player / NPC the note is about and on the
-- note's situation toast; each place has its own checkbox on the Modules >
-- tl;dr page (UI/Config/Tldr.lua), which also edits the snippet list the
-- editor's tl;dr box offers.
--
-- BEHAVIOUR (Dukul, 2026-10-10):
--   * A module like the others (ALL-343): BigNoteBoxDB.tldrEnabled, read only
--     through BNB.TldrEnabled(). Off = no tl;dr anywhere and no tl;dr box in
--     the editor; the saved text stays on the note.
--   * The note list hover details (noteHoverDetails) are a switch of their
--     own on the same page and keep working with the module off (then
--     alarms / situations / waypoints only).
--   * Snippets: BigNoteBoxDB.tldrSnippets, nil = the default list in the
--     player's language. Written only once the player changes the list.
--
-- PUBLIC API:
--   BNB.TldrEnabled()
--   BNB.ApplyTldrModule(on)      -- sends TldrSettings
--   BNB.TldrSnippets()           -- the snippet list (a fresh copy)
--   BNB.SetTldrSnippets(list)    -- nil = back to the defaults; sends TldrSettings
--   BNB.TldrSnippetsCustom()     -- true when the player changed the list
--   BNB.TLDR_SNIPPETS_MAX

local BNB = BigNoteBox
local L   = BNB.L

BNB.TLDR_SNIPPETS_MAX = 30

-- The default snippets, in order (Dukul's pick: KOS first)
local DEFAULT_SNIPPETS = {
    "TLDR_SNIP_KOS", "TLDR_SNIP_FRIENDLY", "TLDR_SNIP_AVOID", "TLDR_SNIP_VENDOR",
    "TLDR_SNIP_QUESTGIVER", "TLDR_SNIP_RARE", "TLDR_SNIP_GOODGROUP",
    "TLDR_SNIP_RECRUIT", "TLDR_SNIP_OWES",
}

function BNB.TldrEnabled()
    return not BigNoteBoxDB or BigNoteBoxDB.tldrEnabled ~= false
end

-- The module switch and the per-place boxes both end here, so every surface
-- redraws from one message
function BNB.ApplyTldrModule(on)
    BNB.SendMessage("TldrSettings", on)
end

function BNB.TldrSnippetsCustom()
    return BigNoteBoxDB ~= nil and type(BigNoteBoxDB.tldrSnippets) == "table"
end

function BNB.TldrSnippets()
    local out = {}
    if BNB.TldrSnippetsCustom() then
        for _, s in ipairs(BigNoteBoxDB.tldrSnippets) do
            if type(s) == "string" and s ~= "" then out[#out + 1] = s end
        end
    else
        for _, k in ipairs(DEFAULT_SNIPPETS) do out[#out + 1] = L[k] end
    end
    return out
end

-- Every entry cleaned like a tl;dr, empties and repeats dropped, capped at
-- TLDR_SNIPPETS_MAX
function BNB.SetTldrSnippets(list)
    if not BigNoteBoxDB then return end
    if list == nil then
        BigNoteBoxDB.tldrSnippets = nil
    else
        local out, seen = {}, {}
        for _, s in ipairs(list) do
            s = BNB.CleanTldr(s)
            if s and not seen[s] and #out < BNB.TLDR_SNIPPETS_MAX then
                seen[s] = true
                out[#out + 1] = s
            end
        end
        BigNoteBoxDB.tldrSnippets = out
    end
    BNB.SendMessage("TldrSettings", BNB.TldrEnabled())
end

-- BigNoteBox Core/DevTools.lua
-- The developer labs (Icon Lab, Background Lab, the search layout tool and
-- their shared LabKit / LabSheet) live in the dev addon BigNoteBox_Dev, never
-- in the release (ARCH-04). That addon loads before this one (OptionalDeps),
-- so its lab files cannot reach BigNoteBox while they load: each one queues
-- its body in BigNoteBoxDevLabs, and this file, last in the TOC, runs the
-- queue once everything the labs use exists. Without the dev addon there is
-- no queue and nothing runs.

local BNB = BigNoteBox
local L = BNB.L

if type(BigNoteBoxDevLabs) == "table" then
    for _, fn in ipairs(BigNoteBoxDevLabs) do xpcall(fn, geterrorhandler()) end
    BigNoteBoxDevLabs = nil
end

-- A dev command or button whose tool is not loaded: say where it lives.
function BNB.DevToolMissing()
    BNB:Print(L["DEV_WIN_NEEDS_DEV_ADDON"])
end

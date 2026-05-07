-- BigNoteBox Features/RandomQuotes.lua
-- Stores the quote pool and picks one per session at PLAYER_LOGIN.
-- Public:
--   BNB.RandomQuotes        -- the raw table (array of strings)
--   BNB._sessionQuote       -- the quote chosen for this session (set at login)

local BNB = BigNoteBox

BNB.RandomQuotes = {
    "\"Lok'tar ogar!\" -Thrall",
    "\"For the Horde!\" -Horde soldiers",
    "\"For the Alliance!\" -Alliance soldiers",
    "\"You are not prepared!\" -Illidan Stormrage",
    "\"I am my scars.\" -Illidan Stormrage",
    "\"Frostmourne hungers.\" -Frostmourne",
    "\"None may challenge the living.\" -Arthas Menethil (Lich King)",
    "\"I serve only the Frozen Throne.\" -Arthas Menethil (Lich King)",
    "\"Arise, my champion!\" -The Lich King",
    "\"Death comes for your soul!\" -The Lich King",
    "\"The Light condemns all who stray.\" -High Inquisitor Whitemane",
    "\"Burn in righteous fire!\" -Scarlet Crusade",
    "\"Nature will rise against you!\" -Malfurion Stormrage",
    "\"The forest fights back.\" -Malfurion Stormrage",
    "\"The cycle must be preserved.\" -Cenarius",
    "\"The Light will heal you.\" -Anduin Wrynn",
    "\"I will not fail my people.\" -Anduin Wrynn",
    "\"Peace is an illusion.\" -Garrosh Hellscream",
    "\"Victory or death!\" -Orcish battle cry",
    "\"Lok'tar!\" -Orc soldiers",
    "\"I will break you.\" -Kil'jaeden",
    "\"The Legion will consume all!\" -Kil'jaeden",
    "\"This world will burn!\" -Archimonde",
    "\"You are nothing before the Legion.\" -Burning Legion forces",
    "\"All will serve the master.\" -Old Gods whispers",
    "\"We are eternal.\" -Old Gods",
    "\"You know nothing of power.\" -Archimonde",
    "\"I am the beginning of the end.\" -Deathwing",
    "\"The world... will shatter!\" -Deathwing",
    "\"I have waited long for this moment.\" -Ragnaros",
    "\"Too soon... you have awakened me too soon!\" -Ragnaros",
    "\"Burn! Burn for eternity!\" -Ragnaros",
    "\"Feel the fire of Sulfuron!\" -Ragnaros",
    "\"The Shadowlands will consume all souls.\" -The Jailer (Zovaal)",
    "\"Your fate is already sealed.\" -The Jailer (Zovaal)",
    "\"No escape from the cycle of death.\" -The Jailer (Zovaal)",
    "\"I watched you with pride, Arthas.\" -Uther the Lightbringer",
    "\"The Light has abandoned you.\" -Uther the Lightbringer",
    "\"You are unworthy.\" -Tyrande Whisperwind",
    "\"The Night Elves will endure.\" -Tyrande Whisperwind",
    "\"I will not be denied.\" -Sylvanas Windrunner",
    "\"What are we if not slaves to this torment?\" -Sylvanas Windrunner",
    "\"Death comes for us all.\" -Sylvanas Windrunner",
    "\"Honor guides us.\" -Varok Saurfang",
    "\"The Horde is nothing without honor!\" -Varok Saurfang",
    "\"My son... the Horde will remember.\" -Varok Saurfang",
    "\"We stand together.\" -Anduin Wrynn",
    "\"There must always be a Lich King.\" -Bolvar Fordragon",
    "\"I will remain... the jailer of the damned.\" -Bolvar Fordragon",
    "\"The Titans... lied.\" -Illidan Stormrage",
    "\"I have sacrificed everything... what have you given?\" -Illidan Stormrage",
    "\"The Dream is corrupted.\" -Ysera",
    "\"All must be preserved.\" -Ysera",
    "\"The earth will endure.\" -Thrall",
    "\"The elements answer me.\" -Thrall",
}

-- Pick one quote at login and hold it for the session.
BNB.RegisterEvent("PLAYER_LOGIN", function()
    local pool = BNB.RandomQuotes
    if pool and #pool > 0 then
        BNB._sessionQuote = pool[math.random(1, #pool)]
    end
end)

-- ZaeUI_Defensives: Known defensive spell data for group cooldown tracking
-- Spell IDs may need updating for Midnight (12.0.0+)

local _, ns = ...

--- Known defensive spells trackable for group members.
--- Format: [spellID] = { name = "Spell Name", cooldown = seconds, duration = seconds, category = "external"|"personal"|"raidwide", class = "CLASSNAME" }
local spellData = {
    -- External defensives (cast on others)
    [33206]  = { name = "Pain Suppression",     cooldown = 120, duration = 8,  category = "external",  class = "PRIEST" },
    [102342] = { name = "Ironbark",              cooldown = 90,  duration = 12, category = "external",  class = "DRUID" },
    [6940]   = { name = "Blessing of Sacrifice", cooldown = 120, duration = 12, category = "external",  class = "PALADIN" },
    [116849] = { name = "Life Cocoon",           cooldown = 120, duration = 12, category = "external",  class = "MONK" },
    [1022]   = { name = "Blessing of Protection", cooldown = 300, duration = 10, category = "external", class = "PALADIN" },
    [47788]  = { name = "Guardian Spirit",       cooldown = 180, duration = 10, category = "external",  class = "PRIEST" },
    [388615] = { name = "Rescue",                cooldown = 60,  duration = 4,  category = "external",  class = "EVOKER" },

    -- Personal defensives (self-only)
    [115203] = { name = "Fortifying Brew",       cooldown = 180, duration = 15, category = "personal",  class = "MONK" },
    [108271] = { name = "Astral Shift",          cooldown = 120, duration = 12, category = "personal",  class = "SHAMAN" },
    [198589] = { name = "Blur",                  cooldown = 60,  duration = 10, category = "personal",  class = "DEMONHUNTER" },
    [196555] = { name = "Netherwalk",            cooldown = 180, duration = 6,  category = "personal",  class = "DEMONHUNTER" },
    [61336]  = { name = "Survival Instincts",    cooldown = 180, duration = 6,  category = "personal",  class = "DRUID" },
    [22812]  = { name = "Barkskin",              cooldown = 60,  duration = 8,  category = "personal",  class = "DRUID" },
    [48792]  = { name = "Icebound Fortitude",    cooldown = 180, duration = 8,  category = "personal",  class = "DEATHKNIGHT" },
    [45438]  = { name = "Ice Block",             cooldown = 240, duration = 10, category = "personal",  class = "MAGE" },
    [642]    = { name = "Divine Shield",         cooldown = 300, duration = 8,  category = "personal",  class = "PALADIN" },
    [31224]  = { name = "Cloak of Shadows",      cooldown = 120, duration = 5,  category = "personal",  class = "ROGUE" },
    [5277]   = { name = "Evasion",               cooldown = 120, duration = 10, category = "personal",  class = "ROGUE" },
    [871]    = { name = "Shield Wall",           cooldown = 240, duration = 8,  category = "personal",  class = "WARRIOR" },
    [118038] = { name = "Die by the Sword",      cooldown = 120, duration = 8,  category = "personal",  class = "WARRIOR" },
    [47585]  = { name = "Dispersion",            cooldown = 120, duration = 6,  category = "personal",  class = "PRIEST" },
    [104773] = { name = "Unending Resolve",      cooldown = 180, duration = 8,  category = "personal",  class = "WARLOCK" },
    [186265] = { name = "Aspect of the Turtle",  cooldown = 180, duration = 8,  category = "personal",  class = "HUNTER" },
    [363916] = { name = "Obsidian Scales",       cooldown = 90,  duration = 12, category = "personal",  class = "EVOKER" },

    -- Raidwide defensives (benefit the whole group)
    [97462]  = { name = "Rallying Cry",          cooldown = 180, duration = 10, category = "raidwide",  class = "WARRIOR" },
    [31821]  = { name = "Aura Mastery",          cooldown = 180, duration = 8,  category = "raidwide",  class = "PALADIN" },
    [98008]  = { name = "Spirit Link Totem",     cooldown = 180, duration = 6,  category = "raidwide",  class = "SHAMAN" },
    [196718] = { name = "Darkness",              cooldown = 300, duration = 8,  category = "raidwide",  class = "DEMONHUNTER" },
    [51052]  = { name = "Anti-Magic Zone",       cooldown = 120, duration = 8,  category = "raidwide",  class = "DEATHKNIGHT" },
    [62618]  = { name = "Power Word: Barrier",   cooldown = 180, duration = 10, category = "raidwide",  class = "PRIEST" },
}

ns.spellData = spellData

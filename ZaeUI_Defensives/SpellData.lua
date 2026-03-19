-- ZaeUI_Defensives: Known defensive spell data for group cooldown tracking
-- Base cooldowns verified against warcraft.wiki.gg for Midnight (12.0.0+)

local _, ns = ...

--- Known defensive spells trackable for group members.
--- Format: [spellID] = { name, cooldown (base), duration, category, class, cooldownBySpec?, cdModifiers? }
--- cooldownBySpec: { [specID] = seconds } overrides the base cooldown for specific specializations.
--- cdModifiers: list of modifiers, each one of:
---   { talent = spellID, reduction = seconds, reductionBySpec? }
---     Single-rank talent: if the player has the talent, subtract reduction from base CD.
---     reductionBySpec: { [specID] = seconds } overrides reduction for specific specs.
---   { ranks = { { talent = spellID, reduction = seconds }, ... } }
---     Multi-rank talent: checks each rank from highest to lowest; applies the first match.
local spellData = {
    -- External defensives (cast on others)
    [33206]  = { name = "Pain Suppression",     cooldown = 180, duration = 8,  category = "external",  class = "PRIEST" },
    [102342] = { name = "Ironbark",              cooldown = 90,  duration = 12, category = "external",  class = "DRUID",
                 cdModifiers = { { talent = 382552, reduction = 20 } } },             -- Improved Ironbark: -20s
    [6940]   = { name = "Blessing of Sacrifice", cooldown = 120, duration = 12, category = "external",  class = "PALADIN",
                 cdModifiers = { { talent = 384820, reduction = 15,                   -- Sacrifice of the Just: -15s (Holy)
                                   reductionBySpec = { [66] = 60 } } } },             -- Protection: -60s
    [116849] = { name = "Life Cocoon",           cooldown = 120, duration = 12, category = "external",  class = "MONK" },
    [1022]   = { name = "Blessing of Protection", cooldown = 300, duration = 10, category = "external", class = "PALADIN" },
    [47788]  = { name = "Guardian Spirit",       cooldown = 180, duration = 10, category = "external",  class = "PRIEST" },
    [388615] = { name = "Rescue",                cooldown = 60,  duration = 4,  category = "external",  class = "EVOKER" },

    -- Personal defensives (self-only)
    [115203] = { name = "Fortifying Brew",       cooldown = 360, duration = 15, category = "personal",  class = "MONK",
                 cooldownBySpec = { [269] = 120, [270] = 120 },                       -- WW/MW: 120s, BrM: 360s
                 cdModifiers = { { talent = 388813, reduction = 120,                  -- Expeditious Fortification: -120s (BrM)
                                   reductionBySpec = { [269] = 30, [270] = 30 } } } },  -- WW/MW: -30s
    [108271] = { name = "Astral Shift",          cooldown = 120, duration = 12, category = "personal",  class = "SHAMAN" },
    [198589] = { name = "Blur",                  cooldown = 60,  duration = 10, category = "personal",  class = "DEMONHUNTER" },
    [61336]  = { name = "Survival Instincts",    cooldown = 180, duration = 6,  category = "personal",  class = "DRUID" },
    [22812]  = { name = "Barkskin",              cooldown = 45,  duration = 8,  category = "personal",  class = "DRUID" },
    [48792]  = { name = "Icebound Fortitude",    cooldown = 120, duration = 8,  category = "personal",  class = "DEATHKNIGHT" },
    [45438]  = { name = "Ice Block",             cooldown = 240, duration = 10, category = "personal",  class = "MAGE",
                 cdModifiers = { { talent = 382424, reduction = 60 } } },             -- Winter's Protection (2 ranks): -60s
    [642]    = { name = "Divine Shield",         cooldown = 300, duration = 8,  category = "personal",  class = "PALADIN",
                 cdModifiers = { { talent = 114154, reduction = 90 } } },             -- Unbreakable Spirit: -30% (90s)
    [31224]  = { name = "Cloak of Shadows",      cooldown = 120, duration = 5,  category = "personal",  class = "ROGUE" },
    [5277]   = { name = "Evasion",               cooldown = 120, duration = 10, category = "personal",  class = "ROGUE" },
    [871]    = { name = "Shield Wall",           cooldown = 180, duration = 8,  category = "personal",  class = "WARRIOR",
                 cdModifiers = { { talent = 397103, reduction = 60 } } },             -- Defender's Aegis: -60s
    [118038] = { name = "Die by the Sword",      cooldown = 120, duration = 8,  category = "personal",  class = "WARRIOR" },
    [47585]  = { name = "Dispersion",            cooldown = 120, duration = 6,  category = "personal",  class = "PRIEST" },
    [104773] = { name = "Unending Resolve",      cooldown = 180, duration = 8,  category = "personal",  class = "WARLOCK" },
    [186265] = { name = "Aspect of the Turtle",  cooldown = 180, duration = 8,  category = "personal",  class = "HUNTER" },
    [363916] = { name = "Obsidian Scales",       cooldown = 90,  duration = 12, category = "personal",  class = "EVOKER" },

    -- Racial defensives (personal)
    [20594]  = { name = "Stoneform",             cooldown = 120, duration = 8,  category = "personal",  class = "ALL" },   -- Dwarf
    [265221] = { name = "Fireblood",             cooldown = 120, duration = 8,  category = "personal",  class = "ALL" },   -- Dark Iron Dwarf

    -- Raidwide defensives (benefit the whole group)
    [97462]  = { name = "Rallying Cry",          cooldown = 180, duration = 10, category = "raidwide",  class = "WARRIOR" },
    [31821]  = { name = "Aura Mastery",          cooldown = 180, duration = 8,  category = "raidwide",  class = "PALADIN",
                 cdModifiers = { { talent = 392911, reduction = 30 } } },             -- Unwavering Spirit: -30s
    [98008]  = { name = "Spirit Link Totem",     cooldown = 180, duration = 6,  category = "raidwide",  class = "SHAMAN" },
    [196718] = { name = "Darkness",              cooldown = 300, duration = 8,  category = "raidwide",  class = "DEMONHUNTER" },
    [51052]  = { name = "Anti-Magic Zone",       cooldown = 240, duration = 8,  category = "raidwide",  class = "DEATHKNIGHT",
                 cdModifiers = { { talent = 374383, reduction = 60 } } },             -- Assimilation: -60s
    [62618]  = { name = "Power Word: Barrier",   cooldown = 180, duration = 10, category = "raidwide",  class = "PRIEST" },
}

ns.spellData = spellData

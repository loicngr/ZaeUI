-- ZaeUI_Interrupts: Known interrupt, stun and knockback spell data
-- Spell IDs may need updating for Midnight (12.0.0+)

local _, ns = ...

--- Known spells that can interrupt a mob's cast.
--- Format: [spellID] = { name = "Spell Name", cooldown = seconds, category = "interrupt"|"stun"|"other" }
local spellData = {
    -- Interrupts
    [1766]   = { name = "Kick",              cooldown = 15, category = "interrupt" },  -- Rogue
    [6552]   = { name = "Pummel",            cooldown = 15, category = "interrupt" },  -- Warrior
    [47528]  = { name = "Mind Freeze",       cooldown = 15, category = "interrupt" },  -- Death Knight
    [96231]  = { name = "Rebuke",            cooldown = 15, category = "interrupt" },  -- Paladin
    [116705] = { name = "Spear Hand Strike", cooldown = 15, category = "interrupt" },  -- Monk
    [106839] = { name = "Skull Bash",        cooldown = 15, category = "interrupt" },  -- Druid
    [183752] = { name = "Disrupt",           cooldown = 15, category = "interrupt" },  -- Demon Hunter
    [187707] = { name = "Muzzle",            cooldown = 15, category = "interrupt" },  -- Hunter (Survival)
    [57994]  = { name = "Wind Shear",        cooldown = 12, category = "interrupt" },  -- Shaman
    [2139]   = { name = "Counterspell",      cooldown = 24, category = "interrupt" },  -- Mage
    [147362] = { name = "Counter Shot",      cooldown = 24, category = "interrupt" },  -- Hunter (BM/MM)
    [19647]  = { name = "Spell Lock",        cooldown = 24, category = "interrupt", pet = true },  -- Warlock (Felhunter)
    [351338] = { name = "Quell",             cooldown = 40, category = "interrupt" },  -- Evoker
    [15487]  = { name = "Silence",           cooldown = 45, category = "interrupt" },  -- Priest (Shadow)

    -- Stuns
    [853]    = { name = "Hammer of Justice", cooldown = 60, category = "stun" },       -- Paladin
    [5211]   = { name = "Mighty Bash",       cooldown = 60, category = "stun" },       -- Druid
    [119381] = { name = "Leg Sweep",         cooldown = 60, category = "stun" },       -- Monk
    [46968]  = { name = "Shockwave",         cooldown = 40, category = "stun" },       -- Warrior
    [107570] = { name = "Storm Bolt",        cooldown = 30, category = "stun" },       -- Warrior
    [179057] = { name = "Chaos Nova",        cooldown = 60, category = "stun" },       -- Demon Hunter
    [211881] = { name = "Fel Eruption",      cooldown = 30, category = "stun" },       -- Demon Hunter
    [91800]  = { name = "Gnaw",              cooldown = 60, category = "stun", pet = true },       -- Death Knight (Ghoul)
    [221562] = { name = "Asphyxiate",        cooldown = 45, category = "stun" },       -- Death Knight
    [30283]  = { name = "Shadowfury",        cooldown = 60, category = "stun" },       -- Warlock
    [89766]  = { name = "Axe Toss",          cooldown = 30, category = "stun", pet = true },       -- Warlock (Felguard)
    [199804] = { name = "Between the Eyes",  cooldown = 45, category = "stun" },       -- Rogue (Outlaw)
    [408]    = { name = "Kidney Shot",       cooldown = 20, category = "stun" },       -- Rogue
    [1833]   = { name = "Cheap Shot",        cooldown = 1,  category = "stun" },       -- Rogue (no real CD, 1s for tracking)
    [24394]  = { name = "Intimidation",      cooldown = 60, category = "stun" },       -- Hunter
    [200166] = { name = "Repentance",        cooldown = 15, category = "other" },      -- Paladin (incapacitate)
    [105421] = { name = "Blinding Light",    cooldown = 90, category = "stun" },       -- Paladin
    [389831] = { name = "Landslide",         cooldown = 90, category = "stun" },       -- Evoker
    [100]    = { name = "Charge",            cooldown = 20, category = "stun" },       -- Warrior
    [88625]  = { name = "Holy Word: Chastise", cooldown = 60, category = "stun" },    -- Priest (Holy)
    [109248] = { name = "Binding Shot",      cooldown = 45, category = "stun" },       -- Hunter

    -- Other (knockbacks, disorients, incapacitates)
    [132469] = { name = "Typhoon",           cooldown = 30, category = "other" },      -- Druid
    [99]     = { name = "Incapacitating Roar", cooldown = 30, category = "other" },    -- Druid
    [22570]  = { name = "Maim",              cooldown = 20, category = "other" },      -- Druid (Feral)
    [157981] = { name = "Blast Wave",        cooldown = 25, category = "other" },      -- Mage
    [51490]  = { name = "Thunderstorm",      cooldown = 30, category = "other" },      -- Shaman
    [31661]  = { name = "Dragon's Breath",   cooldown = 18, category = "other" },      -- Mage
    [8122]   = { name = "Psychic Scream",    cooldown = 60, category = "other" },      -- Priest
    [6789]   = { name = "Mortal Coil",       cooldown = 45, category = "other" },      -- Warlock
    [115078] = { name = "Paralysis",         cooldown = 45, category = "other" },      -- Monk
    [2094]   = { name = "Blind",             cooldown = 120, category = "other" },     -- Rogue
    [192058] = { name = "Capacitor Totem",   cooldown = 60, category = "other" },      -- Shaman
    [1776]   = { name = "Gouge",             cooldown = 15, category = "other" },      -- Rogue
    [217832] = { name = "Imprison",          cooldown = 45, category = "other" },      -- Demon Hunter
    [202137] = { name = "Sigil of Silence",  cooldown = 60, category = "other" },      -- Demon Hunter
    [207684] = { name = "Sigil of Misery",   cooldown = 90, category = "other" },      -- Demon Hunter
    [116844] = { name = "Ring of Peace",     cooldown = 45, category = "other" },      -- Monk
    [113724] = { name = "Ring of Frost",     cooldown = 45, category = "other" },      -- Mage
    [5246]   = { name = "Intimidating Shout", cooldown = 90, category = "other" },     -- Warrior
    [207167] = { name = "Blinding Sleet",    cooldown = 60, category = "other" },      -- Death Knight
    [187650] = { name = "Freezing Trap",     cooldown = 30, category = "other" },      -- Hunter
}

ns.spellData = spellData

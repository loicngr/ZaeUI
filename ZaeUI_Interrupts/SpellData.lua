-- ZaeUI_Interrupts: Known interrupt, stun and knockback spell data
-- Base cooldowns verified against warcraft.wiki.gg for Midnight (12.0.0+)

local _, ns = ...

--- Known spells that can interrupt a mob's cast.
--- Format: [spellID] = { name, cooldown (base), category, pet?, cooldownBySpec?, cdModifiers? }
--- cooldownBySpec: { [specID] = seconds } overrides the base cooldown for specific specializations.
--- cdModifiers: list of modifiers, each one of:
---   { talent = spellID, reduction = seconds, reductionBySpec? }
---     Single-rank talent: if the player has the talent, subtract reduction from base CD.
---     reductionBySpec: { [specID] = seconds } overrides reduction for specific specs.
---   { ranks = { { talent = spellID, reduction = seconds }, ... } }
---     Multi-rank talent: checks each rank from highest to lowest; applies the first match.
local spellData = {
    -- Interrupts
    [1766]   = { name = "Kick",              cooldown = 15, category = "interrupt" },  -- Rogue
    [6552]   = { name = "Pummel",            cooldown = 15, category = "interrupt",    -- Warrior
                 cdModifiers = { { talent = 391271, reduction = 2 } } },             -- Honed Reflexes: -10% (~2s)
    [47528]  = { name = "Mind Freeze",       cooldown = 15, category = "interrupt" },  -- Death Knight
    [96231]  = { name = "Rebuke",            cooldown = 15, category = "interrupt" },  -- Paladin
    [116705] = { name = "Spear Hand Strike", cooldown = 15, category = "interrupt" },  -- Monk
    [106839] = { name = "Skull Bash",        cooldown = 15, category = "interrupt" },  -- Druid
    [183752] = { name = "Disrupt",           cooldown = 15, category = "interrupt" },  -- Demon Hunter
    [187707] = { name = "Muzzle",            cooldown = 15, category = "interrupt" },  -- Hunter (Survival)
    [57994]  = { name = "Wind Shear",        cooldown = 12, category = "interrupt",    -- Shaman
                 cooldownBySpec = { [264] = 30 } },                                   -- Restoration: 30s
    [2139]   = { name = "Counterspell",      cooldown = 25, category = "interrupt",    -- Mage
                 cdModifiers = { { talent = 382297, reduction = 5 } } },              -- Quick Witted: -5s
    [147362] = { name = "Counter Shot",      cooldown = 24, category = "interrupt" },  -- Hunter (BM/MM)
    [19647]  = { name = "Spell Lock",        cooldown = 24, category = "interrupt", pet = true },  -- Warlock (Felhunter)
    [351338] = { name = "Quell",             cooldown = 20, category = "interrupt" },  -- Evoker
    [15487]  = { name = "Silence",           cooldown = 30, category = "interrupt" },  -- Priest (Shadow)
    [386071] = { name = "Disrupting Shout", cooldown = 90, category = "interrupt" },  -- Warrior (Protection, AoE)

    -- Stuns
    [853]    = { name = "Hammer of Justice", cooldown = 45, category = "stun",          -- Paladin
                 cdModifiers = { { talent = 234299, reduction = 15 } } },             -- Fist of Justice: -15s
    [5211]   = { name = "Mighty Bash",       cooldown = 60, category = "stun" },       -- Druid
    [119381] = { name = "Leg Sweep",         cooldown = 60, category = "stun",          -- Monk
                 cdModifiers = { { talent = 344359, reduction = 10 } } },             -- Ancient Arts: -10s
    [46968]  = { name = "Shockwave",         cooldown = 40, category = "stun" },       -- Warrior
    [107570] = { name = "Storm Bolt",        cooldown = 30, category = "stun",          -- Warrior
                 cdModifiers = { { talent = 391271, reduction = 3 } } },             -- Honed Reflexes: -10% (3s)
    [179057] = { name = "Chaos Nova",        cooldown = 45, category = "stun" },       -- Demon Hunter
    [91800]  = { name = "Gnaw",              cooldown = 60, category = "stun", pet = true },       -- Death Knight (Ghoul)
    [221562] = { name = "Asphyxiate",        cooldown = 45, category = "stun" },       -- Death Knight
    [30283]  = { name = "Shadowfury",        cooldown = 60, category = "stun",          -- Warlock
                 cdModifiers = { { talent = 1270255, reduction = 15 } } },            -- Oppressive Darkness: -15s
    [89766]  = { name = "Axe Toss",          cooldown = 30, category = "stun", pet = true },       -- Warlock (Felguard)
    [199804] = { name = "Between the Eyes",  cooldown = 45, category = "stun" },       -- Rogue (Outlaw)
    [408]    = { name = "Kidney Shot",       cooldown = 30, category = "stun" },       -- Rogue
    [1833]   = { name = "Cheap Shot",        cooldown = 12, category = "stun" },       -- Rogue
    [24394]  = { name = "Intimidation",      cooldown = 60, category = "stun" },       -- Hunter
    [200166] = { name = "Repentance",        cooldown = 60, category = "other" },      -- Paladin (incapacitate)
    [105421] = { name = "Blinding Light",    cooldown = 90, category = "stun",          -- Paladin
                 cdModifiers = { { talent = 469325, reduction = 15 } } },             -- Light's Countenance: -15s
    [389831] = { name = "Landslide",         cooldown = 90, category = "stun" },       -- Evoker
    [100]    = { name = "Charge",            cooldown = 20, category = "other",         -- Warrior (root)
                 cdModifiers = { { talent = 444777, reduction = 5 } } },             -- Vicious Agility: -5s (Slayer hero)
    [88625]  = { name = "Holy Word: Chastise", cooldown = 60, category = "stun" },    -- Priest (Holy)
    [109248] = { name = "Binding Shot",      cooldown = 45, category = "stun" },       -- Hunter

    -- Other (knockbacks, disorients, incapacitates)
    [132469] = { name = "Typhoon",           cooldown = 30, category = "other",         -- Druid
                 cdModifiers = { { talent = 400140, reduction = 5 } } },             -- Incessant Tempest: -5s
    [99]     = { name = "Incapacitating Roar", cooldown = 30, category = "other" },    -- Druid
    [22570]  = { name = "Maim",              cooldown = 30, category = "other" },      -- Druid (Feral)
    [51490]  = { name = "Thunderstorm",      cooldown = 30, category = "other" },      -- Shaman
    [31661]  = { name = "Dragon's Breath",   cooldown = 45, category = "other" },      -- Mage
    [8122]   = { name = "Psychic Scream",    cooldown = 40, category = "other",         -- Priest
                 cdModifiers = { { talent = 196704, reduction = 10 } } },             -- Psychic Voice: -10s
    [6789]   = { name = "Mortal Coil",       cooldown = 45, category = "other" },      -- Warlock
    [115078] = { name = "Paralysis",         cooldown = 45, category = "other",         -- Monk
                 cdModifiers = { { talent = 344359, reduction = 15 } } },            -- Ancient Arts: -15s
    [2094]   = { name = "Blind",             cooldown = 120, category = "other",        -- Rogue
                 cdModifiers = { { talent = 256165, reduction = 30 } } },            -- Blinding Powder: -25% (30s, Outlaw)
    [192058] = { name = "Capacitor Totem",   cooldown = 60, category = "other",         -- Shaman
                 cdModifiers = { { talent = 265046, reduction = 15 } } },             -- Static Charge: -15s
    [1776]   = { name = "Gouge",             cooldown = 25, category = "other" },      -- Rogue
    [217832] = { name = "Imprison",          cooldown = 45, category = "other" },      -- Demon Hunter
    [202137] = { name = "Sigil of Silence",  cooldown = 90, category = "other" },      -- Demon Hunter
    [207684] = { name = "Sigil of Misery",   cooldown = 120, category = "other" },     -- Demon Hunter
    [116844] = { name = "Ring of Peace",     cooldown = 45, category = "other",         -- Monk
                 cdModifiers = { { talent = 450448, reduction = 5 } } },             -- Peace and Prosperity: -5s
    [113724] = { name = "Ring of Frost",     cooldown = 45, category = "other" },      -- Mage
    [5484]   = { name = "Howl of Terror",     cooldown = 40, category = "other" },      -- Warlock (AoE fear)
    [5246]   = { name = "Intimidating Shout", cooldown = 90, category = "other" },     -- Warrior
    [207167] = { name = "Blinding Sleet",    cooldown = 60, category = "other" },      -- Death Knight
    [187650] = { name = "Freezing Trap",     cooldown = 30, category = "other" },      -- Hunter

    -- Racial stuns/CC
    [20549]  = { name = "War Stomp",         cooldown = 90, category = "stun" },       -- Tauren (AoE stun 2s)
    [255654] = { name = "Bull Rush",         cooldown = 120, category = "stun" },      -- Highmountain Tauren (stun 1.5s)
    [107079] = { name = "Quaking Palm",      cooldown = 120, category = "other" },     -- Pandaren (incapacitate 4s)
    [287712] = { name = "Haymaker",          cooldown = 150, category = "stun" },      -- Kul Tiran (stun + knockback)
    [357214] = { name = "Wing Buffet",       cooldown = 180, category = "other" },     -- Dracthyr (knockback)
    [368970] = { name = "Tail Swipe",        cooldown = 180, category = "other" },     -- Dracthyr (knockback)
}

ns.spellData = spellData

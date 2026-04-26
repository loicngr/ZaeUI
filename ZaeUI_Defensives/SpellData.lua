-- ZaeUI_Defensives: SpellData — defensive spell catalog
-- Base cooldowns verified against warcraft.wiki.gg for Midnight (12.0.0+)
-- Pure data module: no WoW API calls, no runtime allocations beyond the table literal.

local _, ns = ...

---@class SpellDataEntry
---@field name string
---@field class string                  # "PALADIN", "PRIEST", etc.
---@field category string               # "External" | "Personal"
---@field cooldown number               # seconds, base
---@field duration number               # seconds, base buff duration (0 = instant)
---@field cooldownBySpec table?         # { [specID] = cd }
---@field specs number[]?               # restrict spell to listed specIDs (nil = all specs of class)
---@field cdModifiers table?            # see shape below
---@field charges number?               # default 1
---@field chargeModifiers table?        # { { talent = spellID, bonus = number } }
---@field castSpellId number|number[]?  # button spell ID(s) when different from the aura spell ID
---@field requiresTalent number?        # only seed if this talent is known or assumed
---@field excludeIfTalent number?       # exclude from seeding if this talent is known or assumed
---@field requiresEvidence string|table|false|nil  # nil=unconstrained, false=none, string=key, table=all keys
---@field canCancelEarly boolean?       # true: accept measuredDuration <= expected + tolerance
---@field minDuration boolean?          # true: accept measuredDuration >= expected - tolerance (extensions)
---@field auraFilter string|table?      # "BigDefensive" | "Important" | "External" — Blizzard filter the buff appears under (nil = match any)
---@field excludeFromPrediction boolean? # true: never commit via the unique-classify aura-add fast path; require duration match at removal

-- cdModifiers shape:
--   { talent = spellID, reduction = seconds }                              -- single-rank
--   { ranks = { { talent = spellID, reduction = seconds }, ... } }         -- multi-rank, highest first
-- cooldownBySpec: { [specID] = seconds } overrides base cooldown for specific specs.
-- charges: base number of max charges (nil = 1 charge = normal cooldown behavior).
-- chargeModifiers: list of { talent = spellID, bonus = number } — talents that grant extra charges.
--
-- requiresEvidence keys: "UnitFlags", "Shield", "Debuff", "FeignDeath", "Cast"
--   nil   = unconstrained (any evidence or none)
--   false = explicitly no evidence required
--   "X"   = evidence.X must be true
--   {"X","Y"} = evidence.X AND evidence.Y must both be true

local SpellData = {
    -- ----------------------------------------------------------------
    -- External defensives (cast on others)
    -- ----------------------------------------------------------------
    [33206]  = { name = "Pain Suppression",      cooldown = 180, duration = 8,  category = "External", class = "PRIEST",
                 specs = { 256 },
                 charges = 1,
                 chargeModifiers = { { talent = 373035, bonus = 1 } } },
    [102342] = { name = "Ironbark",               cooldown = 90,  duration = 12, category = "External", class = "DRUID",
                 specs = { 105 },
                 cdModifiers = { { talent = 382552, reduction = 20 } } },
    [6940]   = { name = "Blessing of Sacrifice",  cooldown = 120, duration = 12, category = "External", class = "PALADIN",
                 requiresEvidence = "Shield",
                 cdModifiers = { { talent = 384820, reduction = 15 } } },
    [116849] = { name = "Life Cocoon",            cooldown = 120, duration = 12, category = "External", class = "MONK",
                 specs = { 270 },
                 requiresEvidence = "Shield",
                 cdModifiers = { { talent = 202424, reduction = 30 } } },
    [1022]   = { name = "Blessing of Protection", cooldown = 300, duration = 10, category = "External", class = "PALADIN",
                 requiresEvidence = { "Debuff", "UnitFlags" },
                 excludeIfTalent = 204018,
                 cdModifiers = { { talent = 384909, reduction = 60 } } },
    [47788]  = { name = "Guardian Spirit",        cooldown = 180, duration = 10, category = "External", class = "PRIEST",
                 specs = { 257 } },
    [204018] = { name = "Blessing of Spellwarding", cooldown = 300, duration = 10, category = "External", class = "PALADIN",
                 requiresEvidence = "Shield",
                 requiresTalent = 204018,
                 cdModifiers = { { talent = 384909, reduction = 60 } } },
    [53480]  = { name = "Roar of Sacrifice",      cooldown = 120, duration = 12, category = "External", class = "HUNTER" },
    [357170] = { name = "Time Dilation",           cooldown = 60,  duration = 8,  category = "External", class = "EVOKER",
                 specs = { 1468 },
                 charges = 1,
                 chargeModifiers = { { talent = 376204, bonus = 1 } } },

    -- ----------------------------------------------------------------
    -- Personal defensives (self-only)
    -- ----------------------------------------------------------------
    [115203] = { name = "Fortifying Brew",        cooldown = 360, duration = 15, category = "Personal", class = "MONK",
                 cooldownBySpec = { [269] = 120, [270] = 120 },
                 requiresEvidence = false,
                 cdModifiers = { { talent = 388813, reduction = 30 } } },
    [108271] = { name = "Astral Shift",           cooldown = 120, duration = 12, category = "Personal", class = "SHAMAN",
                 requiresEvidence = false,
                 cdModifiers = { { talent = 381647, reduction = 30 } } },
    [198589] = { name = "Blur",                   cooldown = 60,  duration = 10, category = "Personal", class = "DEMONHUNTER",
                 specs = { 577, 1480 },
                 requiresEvidence = false,
                 auraFilter = "BigDefensive",
                 charges = 1,
                 chargeModifiers = { { talent = 1266307, bonus = 1 } } },
    [204021] = { name = "Fiery Brand",            cooldown = 60,  duration = 12, category = "Personal", class = "DEMONHUNTER",
                 specs = { 581 },
                 requiresEvidence = false,
                 auraFilter = "BigDefensive",
                 minDuration = true },
    [187827] = { name = "Metamorphosis",          cooldown = 120, duration = 15, category = "Personal", class = "DEMONHUNTER",
                 specs = { 581 },
                 requiresEvidence = false,
                 auraFilter = "Important",
                 minDuration = true },
    [22812]  = { name = "Barkskin",               cooldown = 45,  duration = 8,  category = "Personal", class = "DRUID",
                 requiresEvidence = false },
    [48792]  = { name = "Icebound Fortitude",     cooldown = 120, duration = 8,  category = "Personal", class = "DEATHKNIGHT",
                 requiresEvidence = false,
                 cdModifiers = { { talent = 434136, reduction = 3 } } },
    [55233]  = { name = "Vampiric Blood",         cooldown = 90,  duration = 10, category = "Personal", class = "DEATHKNIGHT",
                 specs = { 250 },
                 requiresEvidence = false,
                 minDuration = true },
    [45438]  = { name = "Ice Block",              cooldown = 240, duration = 10, category = "Personal", class = "MAGE",
                 requiresEvidence = false,
                 canCancelEarly = true,
                 excludeIfTalent = 414659,
                 charges = 1,
                 chargeModifiers = { { talent = 1244110, bonus = 1 } },
                 cdModifiers = { { ranks = { { talent = 382424, reduction = 60 },
                                             { talent = 382424, reduction = 30 } } },
                                 { talent = 1265517, reduction = 30 } } },
    [414659] = { name = "Ice Cold",               cooldown = 240, duration = 6,  category = "Personal", class = "MAGE",
                 requiresEvidence = false,
                 canCancelEarly = true,
                 castSpellId = 414658,
                 requiresTalent = 414659,
                 charges = 1,
                 chargeModifiers = { { talent = 1244110, bonus = 1 } },
                 cdModifiers = { { talent = 1265517, reduction = 30 } } },
    [342246] = { name = "Alter Time",             cooldown = 50,  duration = 10, category = "Personal", class = "MAGE",
                 requiresEvidence = "Cast",
                 canCancelEarly = true },
    [642]    = { name = "Divine Shield",          cooldown = 300, duration = 8,  category = "Personal", class = "PALADIN",
                 requiresEvidence = "UnitFlags",
                 canCancelEarly = true,
                 cdModifiers = { { talent = 114154, reduction = 90 } } },
    [498]    = { name = "Divine Protection",      cooldown = 60,  duration = 8,  category = "Personal", class = "PALADIN",
                 specs = { 65 },
                 requiresEvidence = false,
                 cdModifiers = { { talent = 114154, reduction = 18 } } },
    [31850]  = { name = "Ardent Defender",        cooldown = 90,  duration = 8,  category = "Personal", class = "PALADIN",
                 specs = { 66 },
                 requiresEvidence = false,
                 cdModifiers = { { talent = 114154, reduction = 27 } } },
    [86659]  = { name = "Guardian of Ancient Kings", cooldown = 180, duration = 8, category = "Personal", class = "PALADIN",
                 specs = { 66 },
                 requiresEvidence = false,
                 charges = 1,
                 chargeModifiers = { { talent = 1246481, bonus = 1 } } },
    [31224]  = { name = "Cloak of Shadows",       cooldown = 120, duration = 5,  category = "Personal", class = "ROGUE",
                 requiresEvidence = false },
    [5277]   = { name = "Evasion",                cooldown = 120, duration = 10, category = "Personal", class = "ROGUE",
                 requiresEvidence = false },
    [121471] = { name = "Shadow Blades",          cooldown = 90,  duration = 16, category = "Personal", class = "ROGUE",
                 specs = { 261 },
                 requiresEvidence = false,
                 auraFilter = "Important",
                 minDuration = true,
                 excludeFromPrediction = true },
    [871]    = { name = "Shield Wall",            cooldown = 180, duration = 8,  category = "Personal", class = "WARRIOR",
                 specs = { 73 },
                 requiresEvidence = false,
                 charges = 1,
                 chargeModifiers = { { talent = 397103, bonus = 1 } },
                 cdModifiers = { { talent = 397103, reduction = 60 },
                                 { talent = 391271, reduction = 18 } } },
    [118038] = { name = "Die by the Sword",       cooldown = 120, duration = 8,  category = "Personal", class = "WARRIOR",
                 specs = { 71 },
                 requiresEvidence = false,
                 cdModifiers = { { talent = 391271, reduction = 12 } } },
    [184364] = { name = "Enraged Regeneration",   cooldown = 108, duration = 8,  category = "Personal", class = "WARRIOR",
                 specs = { 72 },
                 requiresEvidence = false },
    [47585]  = { name = "Dispersion",             cooldown = 120, duration = 6,  category = "Personal", class = "PRIEST",
                 specs = { 258 },
                 requiresEvidence = false,
                 canCancelEarly = true,
                 cdModifiers = { { talent = 288733, reduction = 30 } } },
    [104773] = { name = "Unending Resolve",       cooldown = 180, duration = 8,  category = "Personal", class = "WARLOCK",
                 requiresEvidence = false,
                 cdModifiers = { { talent = 386659, reduction = 45 } } },
    [186265] = { name = "Aspect of the Turtle",   cooldown = 180, duration = 8,  category = "Personal", class = "HUNTER",
                 requiresEvidence = "UnitFlags",
                 canCancelEarly = true,
                 cdModifiers = { { talent = 1258485, reduction = 30 },
                                 { ranks = { { talent = 266921, reduction = 30 },
                                             { talent = 266921, reduction = 15 } } } } },
    [264735] = { name = "Survival of the Fittest", cooldown = 90,  duration = 6,  category = "Personal", class = "HUNTER",
                 requiresEvidence = false,
                 minDuration = true,
                 charges = 1,
                 chargeModifiers = { { talent = 459450, bonus = 1 } } },
    [109304] = { name = "Exhilaration",            cooldown = 120, duration = 0,  category = "Personal", class = "HUNTER" },
    [363916] = { name = "Obsidian Scales",        cooldown = 90,  duration = 12, category = "Personal", class = "EVOKER",
                 requiresEvidence = false,
                 charges = 1,
                 chargeModifiers = { { talent = 375406, bonus = 1 } } },
    [48707]  = { name = "Anti-Magic Shell",       cooldown = 60,  duration = 5,  category = "Personal", class = "DEATHKNIGHT",
                 requiresEvidence = false },
}

ns.SpellData = SpellData

local DefaultTalents = {
    [64] = { [414659] = true, [1244110] = true },
}

ns.DefaultTalents = DefaultTalents

ZaeUI_DefensivesSpellData = SpellData

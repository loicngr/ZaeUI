local fw = require("framework")
local stubs = require("wow_stubs")

-- TalentResolver uses a small injectable fake of SpellData + talents source.
local function loadResolver(spellData, talentSource)
    local ns = { Core = {}, Utils = {} }
    local futil = assert(loadfile("ZaeUI_Defensives/Utils/Util.lua"))
    futil("ZaeUI_Defensives", ns)
    ns.SpellData = spellData
    -- Injection point for the talent source
    ns.Core.__testTalentSource = talentSource
    local f = assert(loadfile("ZaeUI_Defensives/Core/TalentResolver.lua"))
    f("ZaeUI_Defensives", ns)
    return ns.Core.TalentResolver, ns
end

fw.describe("TalentResolver — base cooldown no talents", function()
    stubs.reset()
    stubs.roster["player"] = { guid = "G", class = "PALADIN" }
    local spellData = {
        [642] = { name = "Divine Shield", class = "PALADIN",
                  category = "Personal", auraOn = "caster",
                  cooldown = 300, duration = 8 },
    }
    local TR = loadResolver(spellData, function() return {} end)
    local cd, ch, eff = TR:Resolve("player", 642)
    fw.it("returns base cooldown", function() fw.assertEq(cd, 300) end)
    fw.it("returns 1 charge", function() fw.assertEq(ch, 1) end)
    fw.it("returns same effectiveID", function() fw.assertEq(eff, 642) end)
end)

fw.describe("TalentResolver — single cdModifier", function()
    stubs.reset()
    stubs.roster["player"] = { guid = "G", class = "PALADIN" }
    local spellData = {
        [642] = { name = "Divine Shield", class = "PALADIN",
                  category = "Personal", auraOn = "caster",
                  cooldown = 300, duration = 8,
                  cdModifiers = { { talent = 114154, reduction = 90 } } },
    }
    local TR = loadResolver(spellData, function() return { [114154] = true } end)
    local cd = TR:Resolve("player", 642)
    fw.it("applies reduction", function() fw.assertEq(cd, 210) end)
end)

fw.describe("TalentResolver — multi-rank cdModifier", function()
    stubs.reset()
    stubs.roster["player"] = { guid = "G", class = "MAGE" }
    local spellData = {
        [45438] = { name = "Ice Block", class = "MAGE",
                    category = "Personal", auraOn = "caster",
                    cooldown = 240, duration = 10,
                    cdModifiers = {
                        { ranks = { { talent = 382424, reduction = 60 },
                                    { talent = 382424, reduction = 30 } } } } },
    }
    local TR = loadResolver(spellData, function() return { [382424] = true } end)
    local cd = TR:Resolve("player", 45438)
    fw.it("picks highest rank reduction", function() fw.assertEq(cd, 180) end)
end)

fw.describe("TalentResolver — chargeModifier (realistic catalog shape)", function()
    stubs.reset()
    stubs.roster["player"] = { guid = "G", class = "MAGE" }
    -- Ice Block + Glacial Bulwark (+1 charge)
    local spellData = {
        [45438] = { name = "Ice Block", class = "MAGE",
                    category = "Personal", auraOn = "caster",
                    cooldown = 240, duration = 10, charges = 1,
                    chargeModifiers = { { talent = 1244110, bonus = 1 } } },
    }
    local TR = loadResolver(spellData, function() return { [1244110] = true } end)
    local _, ch = TR:Resolve("player", 45438)
    fw.it("adds charges from talent (Glacial Bulwark: 1 → 2)", function()
        fw.assertEq(ch, 2)
    end)
end)

fw.describe("TalentResolver — cooldownBySpec", function()
    stubs.reset()
    stubs.roster["player"] = { guid = "G", class = "MONK" }
    stubs.playerSpecID = 269 -- WW
    local spellData = {
        [115203] = { name = "Fortifying Brew", class = "MONK",
                     category = "Personal", auraOn = "caster",
                     cooldown = 360, duration = 15,
                     cooldownBySpec = { [269] = 120, [270] = 120 } },
    }
    local TR = loadResolver(spellData, function() return {} end)
    local cd = TR:Resolve("player", 115203)
    fw.it("overrides base for WW spec", function() fw.assertEq(cd, 120) end)
end)

fw.describe("TalentResolver — overrides via FindSpellOverrideByID", function()
    stubs.reset()
    stubs.roster["player"] = { guid = "G", class = "MAGE" }
    stubs.spellOverrides[45438] = 414658  -- Ice Block → Ice Cold
    local spellData = {
        [45438] = { name = "Ice Block", class = "MAGE",
                    category = "Personal", auraOn = "caster",
                    cooldown = 240, duration = 10,
                    overrides = { 414658 } },
        [414658] = { name = "Ice Cold", class = "MAGE",
                     category = "Personal", auraOn = "caster",
                     cooldown = 240, duration = 6 },
    }
    local TR = loadResolver(spellData, function() return {} end)
    local _, _, eff = TR:Resolve("player", 45438)
    fw.it("swaps to override spellID", function() fw.assertEq(eff, 414658) end)
end)

fw.describe("TalentResolver — duration base value (no modifier)", function()
    stubs.reset()
    stubs.roster["player"] = { guid = "G", class = "DRUID" }
    local spellData = {
        [102342] = { name = "Ironbark", class = "DRUID",
                     category = "External", cooldown = 90, duration = 12 },
    }
    local TR = loadResolver(spellData, function() return {} end)
    local _, _, _, duration = TR:Resolve("player", 102342)
    fw.it("returns base duration as 4th value", function()
        fw.assertEq(duration, 12)
    end)
end)

fw.describe("TalentResolver — single-rank durationModifier", function()
    stubs.reset()
    stubs.roster["player"] = { guid = "G", class = "DRUID" }
    local spellData = {
        [102342] = { name = "Ironbark", class = "DRUID",
                     category = "External", cooldown = 90, duration = 12,
                     durationModifiers = { { talent = 392116, bonus = 4 } } },
    }
    local TR = loadResolver(spellData, function() return { [392116] = true } end)
    local _, _, _, duration = TR:Resolve("player", 102342)
    fw.it("adds bonus to base duration", function()
        fw.assertEq(duration, 16)
    end)
end)

fw.describe("TalentResolver — multi-rank durationModifier", function()
    stubs.reset()
    stubs.roster["player"] = { guid = "G", class = "EVOKER" }
    local spellData = {
        [357170] = { name = "Time Dilation", class = "EVOKER",
                     category = "External", cooldown = 60, duration = 8,
                     durationModifiers = { { ranks = {
                         { talent = 376240, bonus = 2.4 },
                         { talent = 376240, bonus = 1.2 },
                     } } } },
    }
    local TR = loadResolver(spellData, function() return { [376240] = true } end)
    local _, _, _, duration = TR:Resolve("player", 357170)
    fw.it("picks strongest active rank", function()
        fw.assertClose(duration, 10.4, 0.001)
    end)
end)

fw.describe("TalentResolver — Divine Protection Ret variant (403876)", function()
    stubs.reset()
    stubs.roster["player"] = { guid = "G", class = "PALADIN" }
    -- Catalog reflects the real Ret entry shape.
    local spellData = {
        [403876] = { name = "Divine Protection", class = "PALADIN",
                     category = "Personal", cooldown = 90, duration = 8,
                     specs = { 70 },
                     requiresEvidence = "Shield",
                     cdModifiers = { { talent = 114154, reduction = 27 } } },
    }
    local TR = loadResolver(spellData,
        function() return { [114154] = true } end)
    local cd, ch, eff, duration = TR:Resolve("player", 403876)
    fw.it("applies Unbreakable Spirit (90 - 27 = 63s)", function()
        fw.assertEq(cd, 63)
    end)
    fw.it("returns 1 charge", function() fw.assertEq(ch, 1) end)
    fw.it("preserves effective spell ID", function()
        fw.assertEq(eff, 403876)
    end)
    fw.it("returns 8s duration", function() fw.assertEq(duration, 8) end)
end)

fw.describe("TalentResolver — racial defensive Stoneform (20594)", function()
    stubs.reset()
    stubs.roster["player"] = { guid = "G", class = "WARRIOR", race = "Dwarf" }
    local spellData = {
        [20594] = { name = "Stoneform", race = "Dwarf",
                    category = "Personal", cooldown = 120, duration = 8,
                    requiresEvidence = false },
    }
    local TR = loadResolver(spellData, function() return {} end)
    local cd, ch, eff, duration = TR:Resolve("player", 20594)
    fw.it("returns base cooldown 120s", function() fw.assertEq(cd, 120) end)
    fw.it("returns 1 charge", function() fw.assertEq(ch, 1) end)
    fw.it("preserves effective spell ID", function() fw.assertEq(eff, 20594) end)
    fw.it("returns 8s duration", function() fw.assertEq(duration, 8) end)
end)

fw.describe("TalentResolver — Fireblood (265221) Dark Iron Dwarf racial", function()
    stubs.reset()
    stubs.roster["player"] = { guid = "G", class = "WARRIOR", race = "DarkIronDwarf" }
    local spellData = {
        [265221] = { name = "Fireblood", race = "DarkIronDwarf",
                     category = "Personal", cooldown = 120, duration = 8,
                     requiresEvidence = false },
    }
    local TR = loadResolver(spellData, function() return {} end)
    local cd, ch, eff, duration = TR:Resolve("player", 265221)
    fw.it("returns base cooldown 120s", function() fw.assertEq(cd, 120) end)
    fw.it("returns 1 charge", function() fw.assertEq(ch, 1) end)
    fw.it("preserves effective spell ID", function() fw.assertEq(eff, 265221) end)
    fw.it("returns 8s duration", function() fw.assertEq(duration, 8) end)
end)

fw.describe("TalentResolver — Aura Mastery (31821) Holy Paladin raidwide", function()
    stubs.reset()
    stubs.roster["player"] = { guid = "G", class = "PALADIN" }
    stubs.playerSpecID = 65
    local spellData = {
        [31821] = { name = "Aura Mastery", class = "PALADIN", specs = { 65 },
                    category = "Raidwide", cooldown = 180, duration = 8,
                    requiresEvidence = false },
    }
    local TR = loadResolver(spellData, function() return {} end)
    local cd, ch, eff, duration = TR:Resolve("player", 31821)
    fw.it("returns base cooldown 180s", function() fw.assertEq(cd, 180) end)
    fw.it("returns 1 charge", function() fw.assertEq(ch, 1) end)
    fw.it("preserves effective spell ID", function() fw.assertEq(eff, 31821) end)
    fw.it("returns 8s duration", function() fw.assertEq(duration, 8) end)
end)

fw.describe("TalentResolver — Rallying Cry (97463) Warrior raidwide", function()
    stubs.reset()
    stubs.roster["player"] = { guid = "G", class = "WARRIOR" }
    local spellData = {
        [97463] = { name = "Rallying Cry", class = "WARRIOR",
                    category = "Raidwide", cooldown = 180, duration = 10,
                    castSpellId = 97462, requiresEvidence = false },
    }
    local TR = loadResolver(spellData, function() return {} end)
    local cd, ch, eff, duration = TR:Resolve("player", 97463)
    fw.it("returns base cooldown 180s", function() fw.assertEq(cd, 180) end)
    fw.it("returns 1 charge", function() fw.assertEq(ch, 1) end)
    fw.it("preserves effective aura spell ID", function() fw.assertEq(eff, 97463) end)
    fw.it("returns 10s duration", function() fw.assertEq(duration, 10) end)
end)

fw.describe("TalentResolver — Blur (212800) Havoc DH with Demonic Resilience charge", function()
    stubs.reset()
    stubs.roster["player"] = { guid = "G", class = "DEMONHUNTER" }
    stubs.playerSpecID = 577
    local spellData = {
        [212800] = { name = "Blur", class = "DEMONHUNTER", specs = { 577, 1480 },
                     category = "Personal", cooldown = 60, duration = 10,
                     castSpellId = 198589, charges = 1,
                     chargeModifiers = { { talent = 1266307, bonus = 1 } },
                     requiresEvidence = false },
    }
    local TR = loadResolver(spellData,
        function() return { [1266307] = true } end)
    local cd, ch, eff, duration = TR:Resolve("player", 212800)
    fw.it("returns base cooldown 60s", function() fw.assertEq(cd, 60) end)
    fw.it("returns 2 charges with Demonic Resilience", function() fw.assertEq(ch, 2) end)
    fw.it("preserves effective aura spell ID", function() fw.assertEq(eff, 212800) end)
    fw.it("returns 10s duration", function() fw.assertEq(duration, 10) end)
end)

fw.describe("TalentResolver — Alter Time (342246) Mage", function()
    stubs.reset()
    stubs.roster["player"] = { guid = "G", class = "MAGE" }
    local spellData = {
        [342246] = { name = "Alter Time", class = "MAGE",
                     category = "Personal", cooldown = 50, duration = 10,
                     castSpellId = 342245, requiresEvidence = "Cast",
                     canCancelEarly = true },
    }
    local TR = loadResolver(spellData, function() return {} end)
    local cd, ch, eff, duration = TR:Resolve("player", 342246)
    fw.it("returns base cooldown 50s", function() fw.assertEq(cd, 50) end)
    fw.it("returns 1 charge", function() fw.assertEq(ch, 1) end)
    fw.it("preserves effective aura spell ID", function() fw.assertEq(eff, 342246) end)
    fw.it("returns 10s duration", function() fw.assertEq(duration, 10) end)
end)

fw.describe("TalentResolver — Vanish (11327) Rogue", function()
    stubs.reset()
    stubs.roster["player"] = { guid = "G", class = "ROGUE" }
    local spellData = {
        [11327] = { name = "Vanish", class = "ROGUE",
                    category = "Personal", cooldown = 120, duration = 3,
                    castSpellId = 1856, charges = 1,
                    chargeModifiers = { { talent = 382513, bonus = 1 } },
                    requiresEvidence = false },
    }

    local TR = loadResolver(spellData, function() return {} end)
    local cd, ch, eff, duration = TR:Resolve("player", 11327)
    fw.it("base: cooldown 120s", function() fw.assertEq(cd, 120) end)
    fw.it("base: 1 charge without talent", function() fw.assertEq(ch, 1) end)
    fw.it("base: preserves aura spell ID", function() fw.assertEq(eff, 11327) end)
    fw.it("base: 3s duration", function() fw.assertEq(duration, 3) end)

    local TR2 = loadResolver(spellData, function() return { [382513] = true } end)
    local _, ch2 = TR2:Resolve("player", 11327)
    fw.it("with talent 382513: 2 charges", function() fw.assertEq(ch2, 2) end)
end)

fw.describe("TalentResolver — Barkskin (22812) Druid talent stacking", function()
    stubs.reset()
    stubs.roster["player"] = { guid = "G", class = "DRUID" }
    local spellData = {
        [22812] = { name = "Barkskin", class = "DRUID",
                    category = "Personal", cooldown = 60, duration = 8,
                    requiresEvidence = false,
                    cdModifiers = { { talent = 203965, reduction = 7 },
                                    { talent = 137010, reduction = 8 } } },
    }

    local TR0 = loadResolver(spellData, function() return {} end)
    local cd0 = TR0:Resolve("player", 22812)
    fw.it("base cooldown 60s", function() fw.assertEq(cd0, 60) end)

    local TR1 = loadResolver(spellData, function() return { [203965] = true } end)
    local cd1 = TR1:Resolve("player", 22812)
    fw.it("with 203965 alone: 53s", function() fw.assertEq(cd1, 53) end)

    local TR2 = loadResolver(spellData, function() return { [137010] = true } end)
    local cd2 = TR2:Resolve("player", 22812)
    fw.it("with 137010 alone: 52s", function() fw.assertEq(cd2, 52) end)

    local TR3 = loadResolver(spellData,
        function() return { [203965] = true, [137010] = true } end)
    local cd3 = TR3:Resolve("player", 22812)
    fw.it("with both talents: 45s", function() fw.assertEq(cd3, 45) end)
end)

fw.describe("TalentResolver — Aspect of the Turtle (186265) Hunter talent stacking", function()
    stubs.reset()
    stubs.roster["player"] = { guid = "G", class = "HUNTER" }
    local spellData = {
        [186265] = { name = "Aspect of the Turtle", class = "HUNTER",
                     category = "Personal", cooldown = 180, duration = 8,
                     requiresEvidence = "UnitFlags", canCancelEarly = true,
                     cdModifiers = { { talent = 1258485, reduction = 30 },
                                     { talent = 266921,  reduction = 12 } } },
    }

    local TR0 = loadResolver(spellData, function() return {} end)
    local cd0 = TR0:Resolve("player", 186265)
    fw.it("base cooldown 180s", function() fw.assertEq(cd0, 180) end)

    local TR1 = loadResolver(spellData, function() return { [1258485] = true } end)
    local cd1 = TR1:Resolve("player", 186265)
    fw.it("with 1258485 alone: 150s", function() fw.assertEq(cd1, 150) end)

    local TR2 = loadResolver(spellData, function() return { [266921] = true } end)
    local cd2 = TR2:Resolve("player", 186265)
    fw.it("with 266921 alone: 168s", function() fw.assertEq(cd2, 168) end)

    local TR3 = loadResolver(spellData,
        function() return { [1258485] = true, [266921] = true } end)
    local cd3 = TR3:Resolve("player", 186265)
    fw.it("with both talents: 138s", function() fw.assertEq(cd3, 138) end)
end)

fw.describe("TalentResolver — Darkness (209426) DH raidwide", function()
    stubs.reset()
    stubs.roster["player"] = { guid = "G", class = "DEMONHUNTER" }
    local spellData = {
        [209426] = { name = "Darkness", class = "DEMONHUNTER",
                     category = "Raidwide", cooldown = 300, duration = 8,
                     castSpellId = 196718, requiresEvidence = false },
    }
    local TR = loadResolver(spellData, function() return {} end)
    local cd, ch, eff, duration = TR:Resolve("player", 209426)
    fw.it("returns base cooldown 300s", function() fw.assertEq(cd, 300) end)
    fw.it("returns 1 charge", function() fw.assertEq(ch, 1) end)
    fw.it("preserves effective aura spell ID", function() fw.assertEq(eff, 209426) end)
    fw.it("returns 8s duration", function() fw.assertEq(duration, 8) end)
end)

fw.describe("TalentResolver — multiple durationModifiers stack", function()
    stubs.reset()
    stubs.roster["player"] = { guid = "G", class = "EVOKER" }
    local spellData = {
        [357170] = { name = "Time Dilation", class = "EVOKER",
                     category = "External", cooldown = 60, duration = 8,
                     durationModifiers = {
                         { talent = 1, bonus = 2 },
                         { talent = 2, bonus = 3 },
                     } },
    }
    local TR = loadResolver(spellData,
        function() return { [1] = true, [2] = true } end)
    local _, _, _, duration = TR:Resolve("player", 357170)
    fw.it("sums all active bonuses", function()
        fw.assertEq(duration, 13)
    end)
end)

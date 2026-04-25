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

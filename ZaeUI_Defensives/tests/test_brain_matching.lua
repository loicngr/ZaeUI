local fw = require("framework")
require("wow_stubs")

local function loadBrain()
    local ns = { Core = {}, Utils = {}, Modules = {} }
    local futil = assert(loadfile("ZaeUI_Defensives/Utils/Util.lua"))
    futil("ZaeUI_Defensives", ns)
    ns.SpellData = {
        [642] = { name = "Divine Shield", class = "PALADIN",
                  category = "Personal",
                  cooldown = 300, duration = 8 },
        [102342] = { name = "Ironbark", class = "DRUID",
                     category = "External",
                     cooldown = 90, duration = 12, specs = { 105 } },
    }
    local f = assert(loadfile("ZaeUI_Defensives/Core/Brain.lua"))
    f("ZaeUI_Defensives", ns)
    return ns.Core.Brain, ns
end

fw.describe("Brain.MatchAuraToSpell — class match", function()
    local B = loadBrain()
    fw.it("accepts class match", function()
        local ok = B.MatchAuraToSpell(642, "PALADIN", nil, "Human", "caster")
        fw.assertTrue(ok)
    end)
    fw.it("rejects class mismatch", function()
        local ok = B.MatchAuraToSpell(642, "MAGE", nil, "Human", "caster")
        fw.assertEq(ok, false)
    end)
end)

fw.describe("Brain.MatchAuraToSpell — spec restriction", function()
    local ns = { Core = {}, Utils = {} }
    local futil = assert(loadfile("ZaeUI_Defensives/Utils/Util.lua"))
    futil("ZaeUI_Defensives", ns)
    ns.SpellData = {
        [999001] = { name = "Test", class = "DRUID", category = "Personal",
                     cooldown = 60, duration = 8, specs = { 105 } },
    }
    local f = assert(loadfile("ZaeUI_Defensives/Core/Brain.lua"))
    f("ZaeUI_Defensives", ns)
    local B2 = ns.Core.Brain
    local B = loadBrain()

    fw.it("accepts matching spec", function()
        fw.assertTrue(B2.MatchAuraToSpell(999001, "DRUID", 105, "NightElf", "caster"))
    end)
    fw.it("rejects wrong spec when specs list non-nil", function()
        fw.assertEq(B2.MatchAuraToSpell(999001, "DRUID", 103, "NightElf", "caster"), false)
    end)
    fw.it("conservative skip when spec unknown and specs non-nil", function()
        fw.assertEq(B2.MatchAuraToSpell(999001, "DRUID", nil, "NightElf", "caster"), false)
    end)
    fw.it("accepts when specs is nil even if spec unknown", function()
        fw.assertTrue(B.MatchAuraToSpell(642, "PALADIN", nil, "Human", "caster"))
    end)
end)

fw.describe("Brain.MatchAuraToSpell — target skip class/spec filter", function()
    local B = loadBrain()
    fw.it("Ironbark (target) accepted on a Paladin tank", function()
        fw.assertTrue(B.MatchAuraToSpell(102342, "PALADIN", 70, "Human", "target"))
    end)
    fw.it("Ironbark (target) accepted on a Death Knight tank", function()
        fw.assertTrue(B.MatchAuraToSpell(102342, "DEATHKNIGHT", 250, "Orc", "target"))
    end)
    fw.it("target accepts even when target spec unknown", function()
        fw.assertTrue(B.MatchAuraToSpell(102342, "WARRIOR", nil, "Tauren", "target"))
    end)
end)

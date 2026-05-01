local fw = require("framework")
local stubs = require("wow_stubs")

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

-- Wires Util + CooldownStore + TalentResolver + Brain together, with an
-- injectable SpellData and a talent source installed before Brain:Init runs
-- so the Resolver upvalue inside Brain sees the test talents.
local function loadBrainWithTalents(spellData, talentSource)
    stubs.reset()
    stubs.setTime(1000)
    stubs.roster["player"]  = { guid = "P-Player", name = "Myself",
                                class = "PALADIN", race = "Human",
                                role = "HEALER" }
    stubs.roster["party1"]  = { guid = "P-Tank", name = "Tonk",
                                class = "PALADIN", race = "Human",
                                spec = 66, role = "TANK" }
    stubs.roster["party2"]  = { guid = "P-Druid", name = "Druido",
                                class = "DRUID", race = "NightElf",
                                spec = 105, role = "HEALER" }

    _G.UnitIsFriend = function() return true end
    _G.UnitCanAttack = function() return false end
    _G.format = string.format
    _G.GetNumGroupMembers = function() return 3 end
    _G.IsInRaid = function() return false end
    _G.ZaeUI_DefensivesDB = { debug = false }
    _G.CreateFrame = function()
        return { SetScript = function() end, RegisterEvent = function() end }
    end

    local ns = { Core = {}, Utils = {}, Modules = {} }
    local futil = assert(loadfile("ZaeUI_Defensives/Utils/Util.lua"))
    futil("ZaeUI_Defensives", ns)

    ns.SpellData = spellData

    local fstore = assert(loadfile("ZaeUI_Defensives/Core/CooldownStore.lua"))
    fstore("ZaeUI_Defensives", ns)

    -- Inject the talent source BEFORE TalentResolver loads so it captures it
    -- as its initial upvalue. Brain:Init will subsequently call
    -- TR:SetTalentSource with an Inspector-backed function; we re-pin the
    -- test source after Init to keep the controlled fixture authoritative.
    ns.Core.__testTalentSource = talentSource
    local ftr = assert(loadfile("ZaeUI_Defensives/Core/TalentResolver.lua"))
    ftr("ZaeUI_Defensives", ns)

    ns.Core.Inspector = {
        GetSpec = function(_, unit)
            return stubs.roster[unit] and stubs.roster[unit].spec or nil
        end,
        GetRoleHint = function(_, unit)
            return stubs.roster[unit] and stubs.roster[unit].role or "UNKNOWN"
        end,
        GetTalents = function(_, _name) return {} end,
        RegisterCallback = function(_, _fn) end,
    }
    ns.Core.AuraWatcher = {
        RegisterCallback = function() end,
        GetUnitForGUID = function() return nil end,
    }

    local fbrain = assert(loadfile("ZaeUI_Defensives/Core/Brain.lua"))
    fbrain("ZaeUI_Defensives", ns)
    ns.Core.Brain:Init()

    -- Brain:Init wires its own talent source through Inspector. Restore the
    -- fixture's source so the test's talent set actually drives Resolve.
    ns.Core.TalentResolver:SetTalentSource(talentSource)
    ns.Core.TalentResolver:InvalidateCache()

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

fw.describe("Brain.MatchAuraToSpell — racial match", function()
    local ns = { Core = {}, Utils = {} }
    local futil = assert(loadfile("ZaeUI_Defensives/Utils/Util.lua"))
    futil("ZaeUI_Defensives", ns)
    ns.SpellData = {
        [20594] = { name = "Stoneform", race = "Dwarf", category = "Personal",
                    cooldown = 120, duration = 8, requiresEvidence = false },
        [642]   = { name = "Divine Shield", class = "PALADIN",
                    category = "Personal", cooldown = 300, duration = 8 },
    }
    local f = assert(loadfile("ZaeUI_Defensives/Core/Brain.lua"))
    f("ZaeUI_Defensives", ns)
    local B = ns.Core.Brain

    fw.it("Stoneform matches when unitRace == Dwarf", function()
        fw.assertTrue(B.MatchAuraToSpell(20594, "WARRIOR", nil, "Dwarf", "caster"))
    end)
    fw.it("Stoneform rejects when unitRace == Human", function()
        fw.assertEq(B.MatchAuraToSpell(20594, "WARRIOR", nil, "Human", "caster"), false)
    end)
    fw.it("Stoneform rejects when unitRace is nil", function()
        fw.assertEq(B.MatchAuraToSpell(20594, "WARRIOR", nil, nil, "caster"), false)
    end)
    fw.it("class spell still matches by class even when race is provided", function()
        fw.assertTrue(B.MatchAuraToSpell(642, "PALADIN", nil, "Dwarf", "caster"))
    end)
end)

fw.describe("Brain.MatchAuraToSpell — racial match with race list", function()
    local ns = { Core = {}, Utils = {} }
    local futil = assert(loadfile("ZaeUI_Defensives/Utils/Util.lua"))
    futil("ZaeUI_Defensives", ns)
    ns.SpellData = {
        [20594] = { name = "Stoneform",
                    race = { "Dwarf", "Earthen" }, category = "Personal",
                    cooldown = 120, duration = 8, requiresEvidence = false },
    }
    local f = assert(loadfile("ZaeUI_Defensives/Core/Brain.lua"))
    f("ZaeUI_Defensives", ns)
    local B = ns.Core.Brain

    fw.it("matches the first race in the list", function()
        fw.assertTrue(B.MatchAuraToSpell(20594, "WARRIOR", nil, "Dwarf", "caster"))
    end)
    fw.it("matches a later race in the list", function()
        fw.assertTrue(B.MatchAuraToSpell(20594, "WARRIOR", nil, "Earthen", "caster"))
    end)
    fw.it("rejects a race not in the list", function()
        fw.assertEq(B.MatchAuraToSpell(20594, "WARRIOR", nil, "Human", "caster"), false)
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

fw.describe("Brain._durationMatches — explicit expected parameter", function()
    local B = loadBrain()

    fw.it("matches when measured equals the explicit expected value", function()
        -- info.duration is 12 (base) but the explicit expected is 16 (talented).
        local info = { duration = 12 }
        fw.assertTrue(B._durationMatches(16, 16, info))
    end)

    fw.it("does not match when measured equals info.duration but not expected", function()
        -- Reading the base info.duration would falsely accept a 12s aura;
        -- the explicit expected (16) must be what the comparison uses.
        local info = { duration = 12 }
        fw.assertEq(B._durationMatches(12, 16, info), false)
    end)
end)

fw.describe("Brain._durationMatches — minDuration upper bound", function()
    local B = loadBrain()

    fw.it("rejects measured beyond base + sum of positive durationModifiers", function()
        local info = { duration = 6, minDuration = true,
                       durationModifiers = { { talent = 1, bonus = 2 } } }
        fw.assertEq(B._durationMatches(11.0, 6, info), false)
    end)

    fw.it("accepts measured equal to base + bonus (talented variant)", function()
        local info = { duration = 6, minDuration = true,
                       durationModifiers = { { talent = 1, bonus = 2 } } }
        fw.assertTrue(B._durationMatches(8.0, 6, info))
    end)

    fw.it("accepts measured equal to base", function()
        local info = { duration = 6, minDuration = true,
                       durationModifiers = { { talent = 1, bonus = 2 } } }
        fw.assertTrue(B._durationMatches(6.0, 6, info))
    end)

    fw.it("with no durationModifiers, upper bound is base + tolerance", function()
        local info = { duration = 6, minDuration = true }
        fw.assertEq(B._durationMatches(8.0, 6, info), false)
        fw.assertTrue(B._durationMatches(6.4, 6, info))
    end)

    fw.it("rejects measured below the lower tolerance", function()
        local info = { duration = 6, minDuration = true,
                       durationModifiers = { { talent = 1, bonus = 2 } } }
        fw.assertEq(B._durationMatches(5.0, 6, info), false)
    end)

    fw.it("upper bound widens when expected is the talent-resolved value", function()
        local info = { duration = 6, minDuration = true,
                       durationModifiers = { { talent = 1, bonus = 2 } } }
        fw.assertTrue(B._durationMatches(8.3, 8, info))
    end)
end)

fw.describe("Brain._matchByDuration — uses talent-resolved duration per candidate", function()
    -- Ironbark base 12s, talent 392116 adds 4s → measured 16s should match.
    -- Without the per-candidate Resolve call, the function would only see the
    -- base 12s from SpellData and reject 16s as out of tolerance. Talent
    -- bonuses live on the caster (party2 Druid), not the target (party1 Pal).
    local spellData = {
        [102342] = { name = "Ironbark", class = "DRUID",
                     category = "External", cooldown = 90, duration = 12,
                     specs = { 105 },
                     durationModifiers = { { talent = 392116, bonus = 4 } } },
    }
    local talents = { [392116] = true }
    local Brain = loadBrainWithTalents(spellData, function() return talents end)

    fw.it("picks Ironbark on 16s measured when only the talented duration matches", function()
        local spellID, info, casterUnit = Brain._matchByDuration(
            16, "party1", "PALADIN", 70, "External", nil, nil, nil, nil, 1000)
        fw.assertEq(spellID, 102342)
        fw.assertTrue(info)
        fw.assertEq(casterUnit, "party2")
    end)
end)

fw.describe("Brain._matchByDuration — External resolves duration via caster talents", function()
    -- The buff lives on a target whose class differs from the caster's class.
    -- Today's bug: TR:Resolve(target, spellID) cannot see the caster's
    -- durationModifiers, so the 16s aura is rejected against expected 12s.
    -- New contract: matchByDuration must locate the caster among the roster
    -- (by class match), resolve duration via TR on the caster unit, and
    -- return a 4-tuple (spellID, info, casterUnit, casterGUID).
    local spellData = {
        [102342] = { name = "Ironbark", class = "DRUID",
                     category = "External", cooldown = 90, duration = 12,
                     specs = { 105 },
                     durationModifiers = { { talent = 392116, bonus = 4 } } },
    }
    local talentsByUnit = {
        party2 = { [392116] = true },
    }
    local emptyTalents = {}
    local function talentSource(unit)
        return talentsByUnit[unit] or emptyTalents
    end
    local Brain = loadBrainWithTalents(spellData, talentSource)

    fw.it("identifies the Druid caster on a Paladin target via roster + cast evidence", function()
        -- startedAt ~= now (1000); stamp Druid's lastCastTime within window.
        Brain._lastCastTime["party2"] = 1000

        -- Target is party1 (Paladin tank). The caller-supplied unitClass is
        -- the target's class; the function must walk the roster to locate
        -- a class=DRUID caster (info.class) and resolve duration on them.
        local spellID, info, casterUnit, casterGUID = Brain._matchByDuration(
            16, "party1", "PALADIN", 70, "External", nil, nil, nil, nil, 1000)

        fw.assertEq(spellID, 102342)
        fw.assertTrue(info)
        fw.assertEq(casterUnit, "party2")
        fw.assertEq(casterGUID, "P-Druid")
    end)
end)

fw.describe("Brain._matchByDuration — cast-evidence breaks tie between same-class casters", function()
    -- Two Druids in group, both with the talent that turns Ironbark into 16s.
    -- Without a tie-break, the function would either return ambiguous or pick
    -- by roster order. The cast-evidence pass must select the Druid whose
    -- lastCastTime falls inside the evidence window of startedAt.
    local spellData = {
        [102342] = { name = "Ironbark", class = "DRUID",
                     category = "External", cooldown = 90, duration = 12,
                     specs = { 105 },
                     durationModifiers = { { talent = 392116, bonus = 4 } } },
    }
    local talentsByUnit = {
        party2 = { [392116] = true },
        party3 = { [392116] = true },
    }
    local emptyTalents = {}
    local function talentSource(unit)
        return talentsByUnit[unit] or emptyTalents
    end

    fw.it("picks the candidate with cast evidence (party2)", function()
        local Brain, ns = loadBrainWithTalents(spellData, talentSource)
        stubs.roster["party3"] = { guid = "P-Druid2", name = "Druidum",
                                   class = "DRUID", race = "Tauren",
                                   spec = 105, role = "HEALER" }
        _G.GetNumGroupMembers = function() return 4 end

        Brain._lastCastTime["party2"] = 1000
        Brain._lastCastTime["party3"] = nil

        local spellID, info, casterUnit, casterGUID = Brain._matchByDuration(
            16, "party1", "PALADIN", 70, "External", nil, nil, nil, nil, 1000)

        fw.assertEq(spellID, 102342)
        fw.assertTrue(info)
        fw.assertEq(casterUnit, "party2")
        fw.assertEq(casterGUID, "P-Druid")
        -- Sanity: ns is wired so we know we're on the same instance as Brain.
        fw.assertTrue(ns and ns.Core and ns.Core.Brain == Brain)
    end)

    fw.it("picks the candidate with cast evidence (party3) when only it has it", function()
        local Brain = loadBrainWithTalents(spellData, talentSource)
        stubs.roster["party3"] = { guid = "P-Druid2", name = "Druidum",
                                   class = "DRUID", race = "Tauren",
                                   spec = 105, role = "HEALER" }
        _G.GetNumGroupMembers = function() return 4 end

        Brain._lastCastTime["party2"] = nil
        Brain._lastCastTime["party3"] = 1000

        local spellID, info, casterUnit, casterGUID = Brain._matchByDuration(
            16, "party1", "PALADIN", 70, "External", nil, nil, nil, nil, 1000)

        fw.assertEq(spellID, 102342)
        fw.assertTrue(info)
        fw.assertEq(casterUnit, "party3")
        fw.assertEq(casterGUID, "P-Druid2")
    end)
end)

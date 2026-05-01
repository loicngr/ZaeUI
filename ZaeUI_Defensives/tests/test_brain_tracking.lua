local fw = require("framework")
local stubs = require("wow_stubs")

-- Helper: loads Brain with Init-equivalent wiring by directly exercising
-- the internal functions exposed via callbacks. Since Brain's internal
-- functions (onLocalCast, onAuraAdded, etc.) are local, we test them
-- through the full Init path with a mock AuraWatcher.
--
-- Optional opts:
--   spellDataOverrides : map<spellID, info> merged into the default catalog
--                        (overrides existing entries by spellID)
--   talentsByName      : map<unitName, table>; backs Inspector:GetTalents
local function buildInitializedEnv(opts)
    opts = opts or {}
    stubs.reset()
    stubs.setTime(1000)

    stubs.roster["player"] = { guid = "P-Player", name = "Myself", class = "PALADIN", race = "Human", role = "HEALER" }
    stubs.roster["party1"] = { guid = "P-Monk",   name = "Monko",  class = "MONK",    race = "Pandaren", role = "TANK" }
    stubs.roster["party2"] = { guid = "P-Druid",  name = "Druido", class = "DRUID",   race = "NightElf", role = "HEALER", spec = 105 }

    _G.UnitIsFriend = function() return true end
    _G.UnitCanAttack = function() return false end
    _G.format = string.format
    _G.GetNumGroupMembers = function() return 3 end
    _G.IsInRaid = function() return false end
    _G.ZaeUI_DefensivesDB = { debug = false }
    _G.CreateFrame = function()
        return {
            SetScript = function() end,
            RegisterEvent = function() end,
        }
    end

    local ns = { Core = {}, Utils = {}, Modules = {} }

    local futil = assert(loadfile("ZaeUI_Defensives/Utils/Util.lua"))
    futil("ZaeUI_Defensives", ns)

    ns.SpellData = {
        [115203] = { name = "Fortifying Brew", cooldown = 360, duration = 15,
                     category = "Personal", class = "MONK", requiresEvidence = false },
        [642]    = { name = "Divine Shield", cooldown = 300, duration = 8,
                     category = "Personal", class = "PALADIN",
                     requiresEvidence = "UnitFlags", canCancelEarly = true },
        [102342] = { name = "Ironbark", cooldown = 90, duration = 12,
                     category = "External", class = "DRUID", specs = { 105 } },
        [22812]  = { name = "Barkskin", cooldown = 45, duration = 8,
                     category = "Personal", class = "DRUID", requiresEvidence = false },
        [48792]  = { name = "Icebound Fortitude", cooldown = 120, duration = 8,
                     category = "Personal", class = "DEATHKNIGHT", requiresEvidence = false },
        [186265] = { name = "Aspect of the Turtle", cooldown = 180, duration = 8,
                     category = "Personal", class = "HUNTER",
                     requiresEvidence = "UnitFlags", canCancelEarly = true },
        [264735] = { name = "Survival of the Fittest", cooldown = 90, duration = 6,
                     category = "Personal", class = "HUNTER",
                     requiresEvidence = false, minDuration = true,
                     durationModifiers = { { talent = 388039, bonus = 2 } } },
        [6940]   = { name = "Blessing of Sacrifice", cooldown = 120, duration = 12,
                     category = "External", class = "PALADIN",
                     requiresEvidence = "Shield" },
        [48707]  = { name = "Anti-Magic Shell", cooldown = 60, duration = 5,
                     category = "Personal", class = "DEATHKNIGHT",
                     requiresEvidence = "Shield" },
    }
    if opts.spellDataOverrides then
        for spellID, info in pairs(opts.spellDataOverrides) do
            ns.SpellData[spellID] = info
        end
    end

    local fstore = assert(loadfile("ZaeUI_Defensives/Core/CooldownStore.lua"))
    fstore("ZaeUI_Defensives", ns)

    local talentsByName = opts.talentsByName or {}
    local ftr = assert(loadfile("ZaeUI_Defensives/Core/TalentResolver.lua"))
    ftr("ZaeUI_Defensives", ns)

    -- Mock AuraWatcher that captures callbacks
    -- Mock Inspector that reads spec from roster
    local specCallbacks = {}
    ns.Core.Inspector = {
        GetSpec = function(_, unit)
            return stubs.roster[unit] and stubs.roster[unit].spec or nil
        end,
        GetRoleHint = function(_, unit)
            return stubs.roster[unit] and stubs.roster[unit].role or "UNKNOWN"
        end,
        GetTalents = function(_, name) return talentsByName[name] or {} end,
        RegisterCallback = function(_, fn)
            specCallbacks[#specCallbacks + 1] = fn
        end,
    }

    local awCallbacks = {}
    ns.Core.AuraWatcher = {
        RegisterCallback = function(_, event, fn)
            awCallbacks[event] = fn
        end,
        GetUnitForGUID = function(_, guid)
            for u, r in pairs(stubs.roster) do
                if r.guid == guid then return u end
            end
            return nil
        end,
    }

    local fbrain = assert(loadfile("ZaeUI_Defensives/Core/Brain.lua"))
    fbrain("ZaeUI_Defensives", ns)

    ns.Core.Brain:Init()
    ns.Core.TalentResolver:InvalidateCache()

    return {
        Brain = ns.Core.Brain,
        Store = ns.Core.CooldownStore,
        ns = ns,
        stubs = stubs,
        fire = awCallbacks,
        fireSpecChanged = function(unit, reason)
            for i = 1, #specCallbacks do
                specCallbacks[i](unit, reason)
            end
        end,
    }
end

-- =====================================================================
-- Tests
-- =====================================================================

fw.describe("Brain tracking — local cast starts CD immediately", function()
    local env = buildInitializedEnv()

    fw.it("onLocalCast for Divine Shield starts cooldown", function()
        env.stubs.setTime(1000)
        env.fire.OnLocalCast(642)

        local cd = env.Store:Get("P-Player", 642)
        fw.assertTrue(cd, "CD entry should exist")
        fw.assertEq(cd.duration, 300)
        fw.assertEq(cd.startedAt, 1000)
        fw.assertTrue(cd.buffActive)
    end)

    fw.it("onLocalCast ignores unknown spellID", function()
        env.fire.OnLocalCast(999999)
        local cd = env.Store:Get("P-Player", 999999)
        fw.assertNil(cd)
    end)

    fw.it("onLocalCast ignores nil spellID", function()
        env.fire.OnLocalCast(nil)
        -- no error, no entry
    end)
end)

fw.describe("Brain tracking — immediate detection via readable spellId", function()
    local env = buildInitializedEnv()

    fw.it("personal buff with readable spellId starts CD on aura addition", function()
        env.stubs.setTime(2000)
        env.fire.OnAuraChanged("party1", {
            addedAuras = {
                { spellId = 115203, auraInstanceID = 100, name = "Fortifying Brew" },
            },
        })

        local cd = env.Store:Get("P-Monk", 115203)
        fw.assertTrue(cd, "Fortifying Brew CD should exist on Monk")
        fw.assertEq(cd.duration, 360)
        fw.assertEq(cd.startedAt, 2000)
        fw.assertTrue(cd.buffActive)
    end)

    fw.it("external buff with readable sourceUnit credits the caster", function()
        env.stubs.setTime(3000)
        env.fire.OnAuraChanged("party1", {
            addedAuras = {
                { spellId = 102342, auraInstanceID = 200, name = "Ironbark",
                  sourceUnit = "party2" },
            },
        })

        local cd = env.Store:Get("P-Druid", 102342)
        fw.assertTrue(cd, "Ironbark CD should exist on the Druid caster")
        fw.assertEq(cd.duration, 90)
    end)

    fw.it("external buff without sourceUnit does not crash", function()
        env.stubs.setTime(3100)
        -- sourceUnit is nil (secret) — no CD committed but no error
        env.fire.OnAuraChanged("party1", {
            addedAuras = {
                { spellId = 102342, auraInstanceID = 201, name = "Ironbark" },
            },
        })
        -- Can't attribute without source — no new CD beyond the previous test
    end)
end)

fw.describe("Brain tracking — duration matching on aura removal", function()
    local env = buildInitializedEnv()

    fw.it("matches Fortifying Brew by 15s duration on Monk", function()
        env.stubs.setTime(5000)
        env.fire.OnAuraChanged("party1", {
            addedAuras = {
                { spellId = 115203, auraInstanceID = 300, name = "Fortifying Brew" },
            },
        })

        -- Aura removed after ~15s → triggers duration matching
        env.stubs.setTime(5015)
        env.fire.OnAuraChanged("party1", {
            removedAuraInstanceIDs = { 300 },
        })

        local cd = env.Store:Get("P-Monk", 115203)
        fw.assertTrue(cd, "Duration match should have created CD entry")
        fw.assertEq(cd.duration, 360)
        fw.assertEq(cd.startedAt, 5000)
    end)

    fw.it("does not match when duration is way off", function()
        -- Add a DK to roster
        stubs.roster["party3"] = { guid = "P-DK", name = "Deekay", class = "DEATHKNIGHT", race = "Undead" }

        env.stubs.setTime(6000)
        env.fire.OnAuraChanged("party3", {
            addedAuras = {
                { auraInstanceID = 400, name = "Some Unknown Buff" },
            },
        })
        -- Remove after 3s — no DK spell has 3s duration
        env.stubs.setTime(6003)
        env.fire.OnAuraChanged("party3", {
            removedAuraInstanceIDs = { 400 },
        })

        local cd = env.Store:Get("P-DK", 48792)
        fw.assertNil(cd, "No match for 3s duration on DK")
    end)

    fw.it("matches within tolerance (±0.5s)", function()
        stubs.roster["party4"] = { guid = "P-DK2", name = "Deekay2", class = "DEATHKNIGHT", race = "Undead" }

        env.stubs.setTime(7000)
        env.fire.OnAuraChanged("party4", {
            addedAuras = {
                { auraInstanceID = 500, name = "Icebound Fortitude" },
            },
        })
        -- Buff measured at 7.5s instead of 8s — within 0.5s tolerance
        env.stubs.setTime(7007.5)
        env.fire.OnAuraChanged("party4", {
            removedAuraInstanceIDs = { 500 },
        })

        local cd = env.Store:Get("P-DK2", 48792)
        fw.assertTrue(cd, "Should match IBF within tolerance")
        fw.assertEq(cd.duration, 120)
    end)

    fw.it("rejects when outside 0.5s tolerance", function()
        local env2 = buildInitializedEnv()
        stubs.roster["party3"] = { guid = "P-DK3", name = "Deekay3", class = "DEATHKNIGHT", race = "Undead" }

        env2.stubs.setTime(7000)
        env2.fire.OnAuraChanged("party3", {
            addedAuras = {
                { auraInstanceID = 501, name = "Some Buff" },
            },
        })
        -- 7s measured vs 8s expected = 1s delta > 0.5s tolerance
        env2.stubs.setTime(7007)
        env2.fire.OnAuraChanged("party3", {
            removedAuraInstanceIDs = { 501 },
        })

        local cd = env2.Store:Get("P-DK3", 48792)
        fw.assertNil(cd, "1s delta should exceed 0.5s tolerance")
    end)
end)

fw.describe("Brain tracking — name-based fallback when spellId secret", function()
    local env = buildInitializedEnv()

    fw.it("tracks aura by name when spellId is secret", function()
        env.stubs.setTime(8000)
        -- Make the spellId field secret
        local secretSpellId = {}
        env.stubs.secretValues[secretSpellId] = true
        env.fire.OnAuraChanged("party1", {
            addedAuras = {
                { spellId = secretSpellId, auraInstanceID = 600, name = "Fortifying Brew" },
            },
        })

        -- The aura should be tracked (found via name lookup)
        -- On removal, it will match
        env.stubs.setTime(8015)
        env.fire.OnAuraChanged("party1", {
            removedAuraInstanceIDs = { 600 },
        })

        local cd = env.Store:Get("P-Monk", 115203)
        fw.assertTrue(cd, "Name-based fallback should detect Fortifying Brew")
        fw.assertEq(cd.startedAt, 8000)
    end)
end)

fw.describe("Brain tracking — debounce prevents double-fire", function()
    local env = buildInitializedEnv()

    fw.it("second detection within 100ms is debounced", function()
        env.stubs.setTime(9000)
        env.fire.OnLocalCast(642)
        local cd1 = env.Store:Get("P-Player", 642)
        fw.assertTrue(cd1)

        -- Try again within debounce window — different source but same spell+guid
        env.stubs.setTime(9000.05)
        env.fire.OnAuraChanged("player", {
            addedAuras = {
                { spellId = 642, auraInstanceID = 700, name = "Divine Shield" },
            },
        })

        -- CD should still have the original startedAt, not overwritten
        local cd2 = env.Store:Get("P-Player", 642)
        fw.assertEq(cd2.startedAt, 9000)
    end)
end)

fw.describe("Brain tracking — external spells skipped on removal", function()
    local env = buildInitializedEnv()

    fw.it("external aura removal does not commit CD on the target", function()
        env.stubs.setTime(10000)
        -- Ironbark appears on the tank (party1) — spellId secret, only name
        env.fire.OnAuraChanged("party1", {
            addedAuras = {
                { auraInstanceID = 800, name = "Ironbark" },
            },
        })
        -- Removed after 12s
        env.stubs.setTime(10012)
        env.fire.OnAuraChanged("party1", {
            removedAuraInstanceIDs = { 800 },
        })

        -- Should NOT create a CD on the Monk (target), because Ironbark
        -- is an External and the attribution logic searches for the caster.
        -- In this test there IS a Druid (party2) so it may attribute to them.
        -- But the target (P-Monk) should never get an Ironbark entry.
        local cd = env.Store:Get("P-Monk", 102342)
        fw.assertNil(cd, "External CD should not be attributed to the target")
    end)
end)

fw.describe("Brain tracking — buff end on aura removal", function()
    local env = buildInitializedEnv()

    fw.it("EndBuff is called when tracked aura is removed", function()
        env.stubs.setTime(11000)
        -- Readable spellId → CD starts immediately
        env.fire.OnAuraChanged("party1", {
            addedAuras = {
                { spellId = 115203, auraInstanceID = 900, name = "Fortifying Brew" },
            },
        })

        local cd = env.Store:Get("P-Monk", 115203)
        fw.assertTrue(cd.buffActive, "Buff should be active")

        -- Buff removed
        env.stubs.setTime(11015)
        env.fire.OnAuraChanged("party1", {
            removedAuraInstanceIDs = { 900 },
        })

        local cd2 = env.Store:Get("P-Monk", 115203)
        fw.assertEq(cd2.buffActive, false, "Buff should be ended after removal")
    end)
end)

fw.describe("Brain tracking — seeded spells can be activated by detection", function()
    local env = buildInitializedEnv()

    fw.it("duration match overwrites seeded (startedAt=0) entry", function()
        -- Seed Fortifying Brew as "ready"
        env.Store:RegisterPlayer("P-Monk", { name = "Monko", class = "MONK" })
        env.Store:SeedKnownSpells("P-Monk", { [115203] = 1 })
        local seeded = env.Store:Get("P-Monk", 115203)
        fw.assertTrue(seeded, "Seeded entry should exist")
        fw.assertEq(seeded.startedAt, 0, "Seeded entry has startedAt=0")

        -- Aura appears with secret spellId but classified as BIG_DEFENSIVE
        env.stubs.setTime(20000)
        local secretId = {}
        local secretName = {}
        env.stubs.secretValues[secretId] = true
        env.stubs.secretValues[secretName] = true
        env.stubs.auraFilters["party1"] = {
            [2000] = { "HELPFUL|BIG_DEFENSIVE" },
        }

        env.fire.OnAuraChanged("party1", {
            addedAuras = {
                { spellId = secretId, auraInstanceID = 2000, name = secretName },
            },
        })

        -- Aura removed after 15s → duration match for Fortifying Brew
        env.stubs.setTime(20015)
        env.fire.OnAuraChanged("party1", {
            removedAuraInstanceIDs = { 2000 },
        })

        local cd = env.Store:Get("P-Monk", 115203)
        fw.assertTrue(cd, "CD entry should exist")
        fw.assertEq(cd.startedAt, 20000, "Seeded entry should be overwritten with real detection")
        fw.assertEq(cd.duration, 360, "Should have real cooldown duration")
    end)
end)

fw.describe("Brain tracking — full update scans all auras", function()
    local env = buildInitializedEnv()

    _G.AuraUtil = {
        ForEachAura = function(unit, _filter, _maxCount, callback)
            if unit == "party1" then
                callback({ spellId = 115203, auraInstanceID = 1000, name = "Fortifying Brew" })
            end
        end,
    }

    fw.it("isFullUpdate triggers ForEachAura scan", function()
        env.stubs.setTime(12000)
        env.fire.OnAuraChanged("party1", { isFullUpdate = true })

        -- The aura should have been tracked; verify by removing it
        env.stubs.setTime(12015)
        env.fire.OnAuraChanged("party1", {
            removedAuraInstanceIDs = { 1000 },
        })

        local cd = env.Store:Get("P-Monk", 115203)
        fw.assertTrue(cd, "Full update should track auras for later removal matching")
    end)

    _G.AuraUtil = nil
end)

fw.describe("Brain tracking — filter classification (secret-safe M+ path)", function()
    local env = buildInitializedEnv()

    fw.it("tracks aura via BIG_DEFENSIVE filter when spellId and name are secret", function()
        env.stubs.setTime(13000)
        local secretId = {}
        local secretName = {}
        env.stubs.secretValues[secretId] = true
        env.stubs.secretValues[secretName] = true

        env.stubs.auraFilters["party1"] = {
            [1100] = { "HELPFUL|BIG_DEFENSIVE" },
        }

        env.fire.OnAuraChanged("party1", {
            addedAuras = {
                { spellId = secretId, auraInstanceID = 1100, name = secretName },
            },
        })

        -- Remove after 15s → matches Fortifying Brew (duration=15, class=MONK)
        env.stubs.setTime(13015)
        env.fire.OnAuraChanged("party1", {
            removedAuraInstanceIDs = { 1100 },
        })

        local cd = env.Store:Get("P-Monk", 115203)
        fw.assertTrue(cd, "BIG_DEFENSIVE classification should enable duration matching")
        fw.assertEq(cd.duration, 360)
        fw.assertEq(cd.startedAt, 13000)
    end)

    fw.it("does not track aura when neither known nor classified", function()
        local env2 = buildInitializedEnv()
        env2.stubs.setTime(14000)
        local secretId2 = {}
        local secretName2 = {}
        env2.stubs.secretValues[secretId2] = true
        env2.stubs.secretValues[secretName2] = true

        env2.stubs.auraFilters["party1"] = {}

        env2.fire.OnAuraChanged("party1", {
            addedAuras = {
                { spellId = secretId2, auraInstanceID = 1200, name = secretName2 },
            },
        })

        env2.stubs.setTime(14015)
        env2.fire.OnAuraChanged("party1", {
            removedAuraInstanceIDs = { 1200 },
        })

        local cd = env2.Store:Get("P-Monk", 115203)
        fw.assertNil(cd, "Unclassified aura should not be tracked")
    end)

    fw.it("EXTERNAL_DEFENSIVE aura tracked but skipped on removal", function()
        env.stubs.setTime(15000)
        local secretId3 = {}
        local secretName3 = {}
        env.stubs.secretValues[secretId3] = true
        env.stubs.secretValues[secretName3] = true

        env.stubs.auraFilters["party1"] = {
            [1300] = { "HELPFUL|EXTERNAL_DEFENSIVE" },
        }

        env.fire.OnAuraChanged("party1", {
            addedAuras = {
                { spellId = secretId3, auraInstanceID = 1300, name = secretName3 },
            },
        })

        env.stubs.setTime(15012)
        env.fire.OnAuraChanged("party1", {
            removedAuraInstanceIDs = { 1300 },
        })

        -- External CDs can't be attributed to the target on removal
        local cd = env.Store:Get("P-Monk", 102342)
        fw.assertNil(cd, "External classified aura should not commit CD on target")
    end)

    fw.it("unique candidate match triggers immediate detection", function()
        -- Monk has only 1 Personal defensive with requiresEvidence=false in our test SpellData → unique match
        env.stubs.setTime(16000)
        local secretId4 = {}
        env.stubs.secretValues[secretId4] = true

        env.stubs.auraFilters["party1"] = {
            [1400] = { "HELPFUL|BIG_DEFENSIVE" },
        }

        env.fire.OnAuraChanged("party1", {
            addedAuras = {
                { spellId = secretId4, auraInstanceID = 1400, name = "Fortifying Brew" },
            },
        })

        -- CD should be committed immediately (unique candidate for MONK Personal)
        local cd = env.Store:Get("P-Monk", 115203)
        fw.assertTrue(cd, "Unique candidate should trigger immediate detection")
        fw.assertEq(cd.startedAt, 16000)
        fw.assertTrue(cd.buffActive)
    end)

    fw.it("IMPORTANT filter also classifies as Personal", function()
        env.stubs.setTime(16500)
        local secretId6 = {}
        local secretName6 = {}
        env.stubs.secretValues[secretId6] = true
        env.stubs.secretValues[secretName6] = true

        env.stubs.auraFilters["party1"] = {
            [1450] = { "HELPFUL|IMPORTANT" },
        }

        env.fire.OnAuraChanged("party1", {
            addedAuras = {
                { spellId = secretId6, auraInstanceID = 1450, name = secretName6 },
            },
        })

        env.stubs.setTime(16515)
        env.fire.OnAuraChanged("party1", {
            removedAuraInstanceIDs = { 1450 },
        })

        local cd = env.Store:Get("P-Monk", 115203)
        fw.assertTrue(cd, "IMPORTANT filter should classify as Personal and enable matching")
    end)

    fw.it("category narrows duration matching to correct type", function()
        env.stubs.setTime(17000)
        local secretId5 = {}
        local secretName5 = {}
        env.stubs.secretValues[secretId5] = true
        env.stubs.secretValues[secretName5] = true

        -- Barkskin on Druid: Personal, 8s duration
        env.stubs.auraFilters["party2"] = {
            [1500] = { "HELPFUL|BIG_DEFENSIVE" },
        }

        env.fire.OnAuraChanged("party2", {
            addedAuras = {
                { spellId = secretId5, auraInstanceID = 1500, name = secretName5 },
            },
        })

        env.stubs.setTime(17008)
        env.fire.OnAuraChanged("party2", {
            removedAuraInstanceIDs = { 1500 },
        })

        local cd = env.Store:Get("P-Druid", 22812)
        fw.assertTrue(cd, "Should match Barkskin by duration + BIG_DEFENSIVE on Druid")
        fw.assertEq(cd.duration, 45)
    end)
end)

fw.describe("Brain tracking — evidence system", function()
    fw.it("requiresEvidence=UnitFlags blocks match without UnitFlags event", function()
        local env = buildInitializedEnv()
        stubs.roster["party3"] = { guid = "P-Hunter", name = "Hunty", class = "HUNTER", race = "Orc" }

        env.stubs.setTime(18000)
        env.stubs.auraFilters["party3"] = {
            [1600] = { "HELPFUL|BIG_DEFENSIVE" },
        }

        -- No UnitFlags event fired → evidence is nil
        local secretId = {}
        local secretName = {}
        env.stubs.secretValues[secretId] = true
        env.stubs.secretValues[secretName] = true

        env.fire.OnAuraChanged("party3", {
            addedAuras = {
                { spellId = secretId, auraInstanceID = 1600, name = secretName },
            },
        })
        env.stubs.setTime(18008)
        env.fire.OnAuraChanged("party3", {
            removedAuraInstanceIDs = { 1600 },
        })

        -- Aspect of the Turtle requires UnitFlags → should not match
        local cdTurtle = env.Store:Get("P-Hunter", 186265)
        fw.assertNil(cdTurtle, "Turtle should not match without UnitFlags evidence")

        -- SotF (6s, requiresEvidence=false, minDuration=true) should not match 8s
        -- because minDuration means measured >= expected-tolerance = 5.5, and 8 >= 5.5 is true
        -- BUT SotF has minDuration=true so 8s >= 5.5s passes... however we expect
        -- the closer match (Turtle 8s) to win but it's blocked by evidence.
        -- SotF with minDuration=true: 8s >= 5.5s passes. Let's check if it matched SotF.
        local cdSotF = env.Store:Get("P-Hunter", 264735)
        fw.assertTrue(cdSotF, "SotF (minDuration=true, no evidence req) should match 8s on Hunter")
    end)

    fw.it("requiresEvidence=UnitFlags passes with UnitFlags event", function()
        local env = buildInitializedEnv()
        stubs.roster["party3"] = { guid = "P-Hunter2", name = "Hunty2", class = "HUNTER", race = "Orc" }

        env.stubs.setTime(19000)
        -- Fire UnitFlags event just before aura
        env.fire.OnUnitFlags("party3")

        env.stubs.auraFilters["party3"] = {
            [1700] = { "HELPFUL|BIG_DEFENSIVE" },
        }
        local secretId = {}
        local secretName = {}
        env.stubs.secretValues[secretId] = true
        env.stubs.secretValues[secretName] = true

        env.fire.OnAuraChanged("party3", {
            addedAuras = {
                { spellId = secretId, auraInstanceID = 1700, name = secretName },
            },
        })
        env.stubs.setTime(19008)
        env.fire.OnAuraChanged("party3", {
            removedAuraInstanceIDs = { 1700 },
        })

        local cdTurtle = env.Store:Get("P-Hunter2", 186265)
        fw.assertTrue(cdTurtle, "Turtle should match with UnitFlags evidence")
        fw.assertEq(cdTurtle.duration, 180)
    end)

    fw.it("FeignDeath suppresses UnitFlags evidence", function()
        local env = buildInitializedEnv()
        stubs.roster["party3"] = { guid = "P-Hunter3", name = "Hunty3", class = "HUNTER", race = "Orc", isFeign = true }

        env.stubs.setTime(21000)
        -- Fire UnitFlags while feigning → should record FeignDeath, not UnitFlags
        env.fire.OnUnitFlags("party3")

        env.stubs.auraFilters["party3"] = {
            [1800] = { "HELPFUL|BIG_DEFENSIVE" },
        }
        local secretId = {}
        local secretName = {}
        env.stubs.secretValues[secretId] = true
        env.stubs.secretValues[secretName] = true

        env.fire.OnAuraChanged("party3", {
            addedAuras = {
                { spellId = secretId, auraInstanceID = 1800, name = secretName },
            },
        })
        env.stubs.setTime(21008)
        env.fire.OnAuraChanged("party3", {
            removedAuraInstanceIDs = { 1800 },
        })

        -- Turtle requires UnitFlags but FeignDeath suppressed it → no match
        local cdTurtle = env.Store:Get("P-Hunter3", 186265)
        fw.assertNil(cdTurtle, "FeignDeath should suppress UnitFlags → no Turtle match")
    end)

    fw.it("requiresEvidence=Shield blocks AMS without shield event", function()
        local env = buildInitializedEnv()
        stubs.roster["party3"] = { guid = "P-DK4", name = "Deekay4", class = "DEATHKNIGHT", race = "Undead" }

        env.stubs.setTime(22000)
        env.stubs.auraFilters["party3"] = {
            [1900] = { "HELPFUL|BIG_DEFENSIVE" },
        }
        local secretId = {}
        local secretName = {}
        env.stubs.secretValues[secretId] = true
        env.stubs.secretValues[secretName] = true

        env.fire.OnAuraChanged("party3", {
            addedAuras = {
                { spellId = secretId, auraInstanceID = 1900, name = secretName },
            },
        })
        env.stubs.setTime(22005)
        env.fire.OnAuraChanged("party3", {
            removedAuraInstanceIDs = { 1900 },
        })

        local cdAMS = env.Store:Get("P-DK4", 48707)
        fw.assertNil(cdAMS, "AMS should not match without Shield evidence")
    end)

    fw.it("requiresEvidence=Shield passes with shield event", function()
        local env = buildInitializedEnv()
        stubs.roster["party3"] = { guid = "P-DK5", name = "Deekay5", class = "DEATHKNIGHT", race = "Undead" }

        env.stubs.setTime(23000)
        -- Fire shield event
        env.fire.OnShieldChanged("party3")

        env.stubs.auraFilters["party3"] = {
            [2100] = { "HELPFUL|BIG_DEFENSIVE" },
        }
        local secretId = {}
        local secretName = {}
        env.stubs.secretValues[secretId] = true
        env.stubs.secretValues[secretName] = true

        env.fire.OnAuraChanged("party3", {
            addedAuras = {
                { spellId = secretId, auraInstanceID = 2100, name = secretName },
            },
        })
        env.stubs.setTime(23005)
        env.fire.OnAuraChanged("party3", {
            removedAuraInstanceIDs = { 2100 },
        })

        local cdAMS = env.Store:Get("P-DK5", 48707)
        fw.assertTrue(cdAMS, "AMS should match with Shield evidence")
        fw.assertEq(cdAMS.duration, 60)
    end)
end)

fw.describe("Brain tracking — duration modes", function()
    fw.it("minDuration accepts longer measured duration", function()
        local env = buildInitializedEnv()
        stubs.roster["party3"] = { guid = "P-Hunter4", name = "Hunty4", class = "HUNTER", race = "Orc" }

        env.stubs.setTime(24000)
        env.stubs.auraFilters["party3"] = {
            [2200] = { "HELPFUL|BIG_DEFENSIVE" },
        }
        local secretId = {}
        local secretName = {}
        env.stubs.secretValues[secretId] = true
        env.stubs.secretValues[secretName] = true

        env.fire.OnAuraChanged("party3", {
            addedAuras = {
                { spellId = secretId, auraInstanceID = 2200, name = secretName },
            },
        })
        -- SotF base duration is 6s but with talent it can be 8s (minDuration=true)
        -- 8s measured should match SotF because 8 >= 5.5 (6-0.5)
        env.stubs.setTime(24008)
        env.fire.OnAuraChanged("party3", {
            removedAuraInstanceIDs = { 2200 },
        })

        local cd = env.Store:Get("P-Hunter4", 264735)
        fw.assertTrue(cd, "minDuration should accept 8s for a 6s base spell")
    end)

    fw.it("canCancelEarly accepts shorter measured duration", function()
        local env = buildInitializedEnv()
        env.stubs.setTime(25000)
        -- Fire UnitFlags for Divine Shield (requires UnitFlags evidence)
        env.fire.OnUnitFlags("player")

        env.stubs.auraFilters["player"] = {
            [2300] = { "HELPFUL|BIG_DEFENSIVE" },
        }
        local secretId = {}
        local secretName = {}
        env.stubs.secretValues[secretId] = true
        env.stubs.secretValues[secretName] = true

        env.fire.OnAuraChanged("player", {
            addedAuras = {
                { spellId = secretId, auraInstanceID = 2300, name = secretName },
            },
        })
        -- Cancel Divine Shield after 3s (canCancelEarly=true, duration=8)
        -- 3s <= 8.5 passes
        env.stubs.setTime(25003)
        env.fire.OnAuraChanged("player", {
            removedAuraInstanceIDs = { 2300 },
        })

        local cd = env.Store:Get("P-Player", 642)
        fw.assertTrue(cd, "canCancelEarly should accept 3s for an 8s base spell")
    end)
end)

fw.describe("Brain tracking — external attribution", function()
    fw.it("attributes external to unique matching caster", function()
        local env = buildInitializedEnv()
        -- Druid party2 is the only one who can cast Ironbark (Resto spec 105, set in roster)

        env.stubs.setTime(26000)
        env.stubs.auraFilters["party1"] = {
            [2400] = { "HELPFUL|EXTERNAL_DEFENSIVE" },
        }

        -- External appears on party1 (Monk), secret spellId but name is "Ironbark"
        env.fire.OnAuraChanged("party1", {
            addedAuras = {
                { auraInstanceID = 2400, name = "Ironbark" },
            },
        })
        env.stubs.setTime(26012)
        env.fire.OnAuraChanged("party1", {
            removedAuraInstanceIDs = { 2400 },
        })

        -- Should be attributed to the Druid (party2), not the Monk (party1)
        local cdDruid = env.Store:Get("P-Druid", 102342)
        fw.assertTrue(cdDruid, "Ironbark should be attributed to the Druid caster")
        fw.assertEq(cdDruid.duration, 90)

        local cdMonk = env.Store:Get("P-Monk", 102342)
        fw.assertNil(cdMonk, "Ironbark should not be on the target Monk")
    end)
end)

fw.describe("Brain tracking — deferred backfill", function()
    fw.it("evidence arriving after aura is collected by deferred timer", function()
        local env = buildInitializedEnv()
        stubs.roster["party3"] = { guid = "P-Hunter5", name = "Hunty5", class = "HUNTER", race = "Orc" }

        env.stubs.setTime(27000)
        env.stubs.auraFilters["party3"] = {
            [2500] = { "HELPFUL|BIG_DEFENSIVE" },
        }
        local secretId = {}
        local secretName = {}
        env.stubs.secretValues[secretId] = true
        env.stubs.secretValues[secretName] = true

        -- Aura arrives first (no evidence yet)
        env.fire.OnAuraChanged("party3", {
            addedAuras = {
                { spellId = secretId, auraInstanceID = 2500, name = secretName },
            },
        })

        -- UnitFlags arrives slightly after (within evidence window)
        env.stubs.setTime(27000.1)
        env.fire.OnUnitFlags("party3")

        -- Flush deferred backfill timers (deadline = 27000 + 0.15 = 27000.15)
        env.stubs.setTime(27000.2)
        env.stubs.flushTimers(27000.2)

        -- Now remove the aura — evidence should include UnitFlags
        env.stubs.setTime(27008)
        env.fire.OnAuraChanged("party3", {
            removedAuraInstanceIDs = { 2500 },
        })

        local cd = env.Store:Get("P-Hunter5", 186265)
        fw.assertTrue(cd, "Deferred backfill should capture late UnitFlags evidence for Turtle")
        fw.assertEq(cd.duration, 180)
    end)
end)

fw.describe("Brain tracking — auraFilter splits BigDefensive vs Important", function()
    -- Same-class same-display-category siblings (Fiery Brand BigDefensive,
    -- Metamorphosis Important on Vengeance DH) only differ by Blizzard's
    -- narrower filter. The auraFilter field routes each Blizzard filter to
    -- its dedicated spell so the two never collide on duration matching.
    local function buildDhEnv()
        local env = buildInitializedEnv()
        env.ns.SpellData[204021] = {
            name = "Fiery Brand", cooldown = 60, duration = 12,
            category = "Personal", class = "DEMONHUNTER",
            specs = { 581 }, requiresEvidence = false,
            auraFilter = "BigDefensive", minDuration = true,
        }
        env.ns.SpellData[187827] = {
            name = "Metamorphosis", cooldown = 120, duration = 15,
            category = "Personal", class = "DEMONHUNTER",
            specs = { 581 }, requiresEvidence = false,
            auraFilter = "Important", minDuration = true,
        }
        stubs.roster["party1"] = { guid = "P-DH", name = "Dh", class = "DEMONHUNTER",
                                   race = "NightElf", spec = 581, role = "TANK" }
        env.ns.Core.Brain:Init()
        return env
    end

    fw.it("BIG_DEFENSIVE-classified aura attributes to Fiery Brand, not Metamorphosis", function()
        local env = buildDhEnv()
        env.stubs.setTime(40000)
        local secretId, secretName = {}, {}
        env.stubs.secretValues[secretId] = true
        env.stubs.secretValues[secretName] = true
        env.stubs.auraFilters["party1"] = {
            [3001] = { "HELPFUL|BIG_DEFENSIVE" },
        }

        env.fire.OnAuraChanged("party1", {
            addedAuras = {
                { spellId = secretId, auraInstanceID = 3001, name = secretName },
            },
        })

        local cd = env.Store:Get("P-DH", 204021)
        fw.assertTrue(cd, "Fiery Brand must be detected immediately on a BigDefensive aura")
        fw.assertEq(cd.duration, 60)
        fw.assertNil(env.Store:Get("P-DH", 187827),
                     "Metamorphosis must not be triggered by a BigDefensive aura")
    end)

    fw.it("IMPORTANT-classified aura attributes to Metamorphosis, not Fiery Brand", function()
        local env = buildDhEnv()
        env.stubs.setTime(41000)
        local secretId, secretName = {}, {}
        env.stubs.secretValues[secretId] = true
        env.stubs.secretValues[secretName] = true
        env.stubs.auraFilters["party1"] = {
            [3002] = { "HELPFUL|IMPORTANT" },
        }

        env.fire.OnAuraChanged("party1", {
            addedAuras = {
                { spellId = secretId, auraInstanceID = 3002, name = secretName },
            },
        })

        local cd = env.Store:Get("P-DH", 187827)
        fw.assertTrue(cd, "Metamorphosis must be detected immediately on an Important aura")
        fw.assertEq(cd.duration, 120)
        fw.assertNil(env.Store:Get("P-DH", 204021),
                     "Fiery Brand must not be triggered by an Important aura")
    end)

    fw.it("auraFilter accepts a table for spells that surface under multiple filters", function()
        -- A spell can legitimately surface under several Blizzard filters
        -- (e.g. Divine Protection appearing as both BigDefensive and
        -- Important). The accepts() check must allow either.
        local env = buildDhEnv()
        local accepts = env.ns.Core.Brain._auraFilterAccepts
        fw.assertTrue(accepts({ "BigDefensive", "Important" }, "BigDefensive"))
        fw.assertTrue(accepts({ "BigDefensive", "Important" }, "Important"))
        fw.assertEq(accepts({ "BigDefensive", "Important" }, "External"), false)
    end)

    fw.it("auraFilter string form behaves identically to a single-element table", function()
        local env = buildDhEnv()
        local accepts = env.ns.Core.Brain._auraFilterAccepts
        fw.assertTrue(accepts("BigDefensive", "BigDefensive"))
        fw.assertEq(accepts("BigDefensive", "Important"), false)
    end)

    fw.it("auraFilter gate is disabled when either side is nil", function()
        local env = buildDhEnv()
        local accepts = env.ns.Core.Brain._auraFilterAccepts
        fw.assertTrue(accepts(nil, "BigDefensive"), "untagged spell accepts any aura")
        fw.assertTrue(accepts("BigDefensive", nil), "tagged spell accepts unclassified aura")
        fw.assertTrue(accepts(nil, nil))
    end)

    fw.it("Charred-Flesh-extended Fiery Brand removal still attributes to Fiery Brand", function()
        -- An 18s BigDefensive aura (FB extended via Charred Flesh) must
        -- stay attributed to FB. Without the auraFilter gate the absolute
        -- delta would pull the match toward Meta's 15s baseline.
        local env = buildDhEnv()
        env.stubs.setTime(42000)
        local secretId, secretName = {}, {}
        env.stubs.secretValues[secretId] = true
        env.stubs.secretValues[secretName] = true
        env.stubs.auraFilters["party1"] = {
            [3003] = { "HELPFUL|BIG_DEFENSIVE" },
        }
        env.fire.OnAuraChanged("party1", {
            addedAuras = {
                { spellId = secretId, auraInstanceID = 3003, name = secretName },
            },
        })
        env.stubs.setTime(42018)
        env.fire.OnAuraChanged("party1", {
            removedAuraInstanceIDs = { 3003 },
        })

        fw.assertTrue(env.Store:Get("P-DH", 204021),
                      "Fiery Brand kept as the BigDefensive candidate even at extended duration")
        fw.assertNil(env.Store:Get("P-DH", 187827),
                     "Metamorphosis must remain unattributed for a BigDefensive aura")
    end)
end)

fw.describe("Brain tracking — castSpellId remap on immediate detection", function()
    -- Talent overrides apply a buff whose spellId matches the cast id rather
    -- than the catalog id. The Brain must remap before looking up SpellData
    -- so an Ice-Cold-style override still triggers detection.
    fw.it("aura with cast id is mapped to its catalog entry", function()
        local env = buildInitializedEnv()

        -- Inject a catalog entry with castSpellId different from spellID.
        env.ns.SpellData[414659] = {
            name = "Ice Cold", cooldown = 240, duration = 6,
            category = "Personal", class = "MAGE",
            castSpellId = 414658, requiresEvidence = false,
        }
        stubs.roster["party1"] = { guid = "P-Mage1", name = "Mageo", class = "MAGE", race = "Human" }

        -- Re-init Brain so its castSpellIdIndex picks up the new entry.
        env.ns.Core.Brain:Init()

        env.stubs.setTime(30000)
        -- Aura uses the cast id, not the catalog id.
        env.fire.OnAuraChanged("party1", {
            addedAuras = {
                { spellId = 414658, auraInstanceID = 5000, name = "Ice Cold" },
            },
        })

        local cd = env.Store:Get("P-Mage1", 414659)
        fw.assertTrue(cd, "Catalog entry must be reached via the cast id remap")
        fw.assertEq(cd.duration, 240)
    end)
end)

fw.describe("Brain tracking — excludeFromPrediction skips unique-classify", function()
    -- Some spells share Blizzard's IMPORTANT filter with siblings that we
    -- don't catalog (Sub Rogue's Shadow Blades alongside Shadow Dance). For
    -- those we must not commit a unique-classify match on a secret spellId,
    -- since the aura might actually be the uncatalogued sibling. Duration
    -- match at removal still resolves them when the duration disambiguates.
    local function buildRogueEnv()
        local env = buildInitializedEnv()
        env.ns.SpellData[121471] = {
            name = "Shadow Blades", cooldown = 90, duration = 16,
            category = "Personal", class = "ROGUE",
            specs = { 261 }, requiresEvidence = false,
            auraFilter = "Important", minDuration = true,
            excludeFromPrediction = true,
        }
        stubs.roster["party3"] = { guid = "P-Rogue", name = "Wayfu",
                                   class = "ROGUE", race = "Human",
                                   spec = 261, role = "DAMAGER" }
        env.ns.Core.Brain:Init()
        return env
    end

    fw.it("does not commit at aura-add when only candidate is excluded", function()
        local env = buildRogueEnv()
        env.stubs.setTime(80000)
        local secretId, secretName = {}, {}
        env.stubs.secretValues[secretId] = true
        env.stubs.secretValues[secretName] = true
        env.stubs.auraFilters["party3"] = {
            [7001] = { "HELPFUL|IMPORTANT" },
        }
        env.fire.OnAuraChanged("party3", {
            addedAuras = {
                { spellId = secretId, auraInstanceID = 7001, name = secretName },
            },
        })
        fw.assertNil(env.Store:Get("P-Rogue", 121471),
                     "Shadow Blades must not unique-classify when excluded")
    end)

    fw.it("Still commits at aura-removal via duration match", function()
        local env = buildRogueEnv()
        env.stubs.setTime(81000)
        local secretId, secretName = {}, {}
        env.stubs.secretValues[secretId] = true
        env.stubs.secretValues[secretName] = true
        env.stubs.auraFilters["party3"] = {
            [7002] = { "HELPFUL|IMPORTANT" },
        }
        env.fire.OnAuraChanged("party3", {
            addedAuras = {
                { spellId = secretId, auraInstanceID = 7002, name = secretName },
            },
        })
        env.stubs.setTime(81016)
        env.fire.OnAuraChanged("party3", {
            removedAuraInstanceIDs = { 7002 },
        })

        fw.assertTrue(env.Store:Get("P-Rogue", 121471),
                      "duration match still resolves Shadow Blades at removal")
    end)
end)

fw.describe("Brain tracking — unique-classify defers when evidence is pending", function()
    -- When a candidate is gated only by an unmet requiresEvidence (e.g. DS
    -- waiting on UnitFlags), the unique-match commit is held off so a
    -- sibling with no evidence requirement (DP) cannot claim the cast.
    -- matchByDuration at removal — with full evidence — resolves it.
    local function buildPalEnv()
        local env = buildInitializedEnv()
        env.ns.SpellData[498] = {
            name = "Divine Protection", cooldown = 60, duration = 8,
            category = "Personal", class = "PALADIN",
            specs = { 65 }, requiresEvidence = false,
        }
        env.ns.Core.Brain:Init()  -- rebuild reverse indexes
        return env
    end

    fw.it("does not commit DP while DS is still waiting on UnitFlags", function()
        local env = buildPalEnv()
        env.stubs.setTime(50000)
        local secretId, secretName = {}, {}
        env.stubs.secretValues[secretId] = true
        env.stubs.secretValues[secretName] = true
        env.stubs.auraFilters["player"] = {
            [4001] = { "HELPFUL|BIG_DEFENSIVE" },
        }
        env.fire.OnAuraChanged("player", {
            addedAuras = {
                { spellId = secretId, auraInstanceID = 4001, name = secretName },
            },
        })

        fw.assertNil(env.Store:Get("P-Player", 498),
                     "DP must not commit while DS evidence is pending")
        fw.assertNil(env.Store:Get("P-Player", 642),
                     "DS must not commit either at this point")
    end)

    fw.it("commits the right spell at removal once evidence has been observed", function()
        local env = buildPalEnv()
        env.stubs.setTime(50000)
        local secretId, secretName = {}, {}
        env.stubs.secretValues[secretId] = true
        env.stubs.secretValues[secretName] = true
        env.stubs.auraFilters["player"] = {
            [4002] = { "HELPFUL|BIG_DEFENSIVE" },
        }
        env.fire.OnAuraChanged("player", {
            addedAuras = {
                { spellId = secretId, auraInstanceID = 4002, name = secretName },
            },
        })
        -- UnitFlags arrives after the aura, attached to recent auras.
        env.stubs.setTime(50000.05)
        env.fire.OnUnitFlags("player")

        env.stubs.setTime(50008)
        env.fire.OnAuraChanged("player", {
            removedAuraInstanceIDs = { 4002 },
        })

        fw.assertTrue(env.Store:Get("P-Player", 642),
                      "DS must win the duration tie thanks to its evidence requirement")
        fw.assertNil(env.Store:Get("P-Player", 498),
                     "DP must not commit when DS is the right answer")
    end)
end)

fw.describe("Brain tracking — duration-match tiebreaker prefers requiresEvidence", function()
    -- Same-duration siblings (Pal Prot's Divine Shield, Ardent Defender,
    -- Guardian of Ancient Kings — all 8s) tie on absolute delta. The
    -- tiebreaker promotes the candidate whose requiresEvidence gate is
    -- explicitly satisfied so iteration order does not decide the winner.
    local function buildProtEnv()
        local env = buildInitializedEnv()
        env.ns.SpellData[498] = nil  -- avoid Holy DP confusing matters
        env.ns.SpellData[31850] = {
            name = "Ardent Defender", cooldown = 90, duration = 8,
            category = "Personal", class = "PALADIN",
            specs = { 66 }, requiresEvidence = false,
        }
        env.ns.SpellData[86659] = {
            name = "Guardian of Ancient Kings", cooldown = 180, duration = 8,
            category = "Personal", class = "PALADIN",
            specs = { 66 }, requiresEvidence = false,
        }
        stubs.roster["party3"] = { guid = "P-ProtPal", name = "Tonk",
                                   class = "PALADIN", race = "Human",
                                   spec = 66, role = "TANK" }
        env.ns.Core.Brain:Init()
        return env
    end

    fw.it("Divine Shield wins over AD/GoAK when UnitFlags evidence is met", function()
        local env = buildProtEnv()
        env.stubs.setTime(60000)
        local secretId, secretName = {}, {}
        env.stubs.secretValues[secretId] = true
        env.stubs.secretValues[secretName] = true
        env.stubs.auraFilters["party3"] = {
            [5001] = { "HELPFUL|BIG_DEFENSIVE" },
        }
        env.fire.OnAuraChanged("party3", {
            addedAuras = {
                { spellId = secretId, auraInstanceID = 5001, name = secretName },
            },
        })
        env.stubs.setTime(60000.05)
        env.fire.OnUnitFlags("party3")

        env.stubs.setTime(60008)
        env.fire.OnAuraChanged("party3", {
            removedAuraInstanceIDs = { 5001 },
        })

        fw.assertTrue(env.Store:Get("P-ProtPal", 642),
                      "Divine Shield is preferred when UnitFlags evidence is observed")
        fw.assertNil(env.Store:Get("P-ProtPal", 31850), "AD must not be the chosen candidate")
        fw.assertNil(env.Store:Get("P-ProtPal", 86659), "GoAK must not be the chosen candidate")
    end)

    fw.it("Falls back to AD when no UnitFlags evidence is gathered", function()
        local env = buildProtEnv()
        env.stubs.setTime(61000)
        local secretId, secretName = {}, {}
        env.stubs.secretValues[secretId] = true
        env.stubs.secretValues[secretName] = true
        env.stubs.auraFilters["party3"] = {
            [5002] = { "HELPFUL|BIG_DEFENSIVE" },
        }
        env.fire.OnAuraChanged("party3", {
            addedAuras = {
                { spellId = secretId, auraInstanceID = 5002, name = secretName },
            },
        })
        -- No UnitFlags event fired. DS evidence stays unmet.
        env.stubs.setTime(61008)
        env.fire.OnAuraChanged("party3", {
            removedAuraInstanceIDs = { 5002 },
        })

        fw.assertNil(env.Store:Get("P-ProtPal", 642),
                     "DS must not commit without UnitFlags evidence")
        local ad = env.Store:Get("P-ProtPal", 31850)
        local goak = env.Store:Get("P-ProtPal", 86659)
        fw.assertTrue(ad or goak, "Either AD or GoAK must commit as the fallback")
    end)
end)

fw.describe("Brain tracking — external attribution uses cast evidence", function()
    -- Two Paladins in the same group make Blessing of Sacrifice ambiguous
    -- on class match alone. The cast-evidence pass picks the caster whose
    -- UNIT_SPELLCAST_SUCCEEDED fired within the evidence window of the
    -- aura's start, falling back to single-class attribution otherwise.
    local function buildTwoPalEnv()
        local env = buildInitializedEnv()
        stubs.roster["party3"] = { guid = "P-ProtPal", name = "Tonk",
                                   class = "PALADIN", race = "Human",
                                   spec = 66, role = "TANK" }
        -- buildInitializedEnv pins GetNumGroupMembers to 3; widen to include
        -- party3 so the roster iteration in tryAttributeExternal sees it.
        _G.GetNumGroupMembers = function() return 4 end
        env.ns.Core.Brain:Init()
        return env
    end

    fw.it("Resolves BoS to the Pal whose cast event fired near the aura", function()
        local env = buildTwoPalEnv()
        env.stubs.setTime(70000)

        -- BoS aura lands on party2 (the Druid healer in the test fixture).
        -- We stamp lastCastTime for the tank Pal (party3) but NOT for the
        -- player so only the tank passes the cast-evidence pass.
        env.Brain._lastCastTime["party3"] = 70000.02

        env.stubs.auraFilters["party2"] = {
            [6001] = { "HELPFUL|EXTERNAL_DEFENSIVE" },
        }
        local secretId, secretName = {}, {}
        env.stubs.secretValues[secretId] = true
        env.stubs.secretValues[secretName] = true

        env.fire.OnAuraChanged("party2", {
            addedAuras = {
                { spellId = secretId, auraInstanceID = 6001, name = secretName },
            },
        })
        -- Shield evidence on the buff target — required by the BoS rule.
        env.fire.OnShieldChanged("party2")
        env.stubs.setTime(70012)
        env.fire.OnAuraChanged("party2", {
            removedAuraInstanceIDs = { 6001 },
        })

        local tankRec = env.Store:GetPlayerRec("P-ProtPal")
        fw.assertTrue(tankRec, "Tank Pal must exist as the attributed caster")
        fw.assertTrue(tankRec.cooldowns[6940],
                      "Blessing of Sacrifice must be on cooldown for the tank Pal")
        local playerRec = env.Store:GetPlayerRec("P-Player")
        fw.assertTrue(not (playerRec and playerRec.cooldowns and playerRec.cooldowns[6940]),
                      "Player Pal must NOT be falsely attributed as the BoS caster")
    end)

    fw.it("Falls back to single-class attribution when no cast evidence exists", function()
        local env = buildTwoPalEnv()
        env.stubs.setTime(71000)

        -- Drop one of the two Paladins so the single-candidate fallback is
        -- the only remaining attribution path.
        stubs.roster["party3"] = nil

        env.stubs.auraFilters["party2"] = {
            [6002] = { "HELPFUL|EXTERNAL_DEFENSIVE" },
        }
        local secretId, secretName = {}, {}
        env.stubs.secretValues[secretId] = true
        env.stubs.secretValues[secretName] = true

        env.fire.OnAuraChanged("party2", {
            addedAuras = {
                { spellId = secretId, auraInstanceID = 6002, name = secretName },
            },
        })
        env.fire.OnShieldChanged("party2")
        env.stubs.setTime(71012)
        env.fire.OnAuraChanged("party2", {
            removedAuraInstanceIDs = { 6002 },
        })

        local rec = env.Store:GetPlayerRec("P-Player")
        fw.assertTrue(rec and rec.cooldowns[6940],
                      "Sole Pal candidate must be attributed when no cast evidence exists")
    end)
end)

fw.describe("Brain tracking — commitCooldown uses TR-resolved duration", function()
    -- Aura-add path passes info.duration (12) as the buffDuration parameter.
    -- TR resolves duration to 12+4=16 thanks to the talented bonus, and that
    -- TR result must take precedence over the parameter when storing the CD.
    -- Asserting before aura-removal isolates the aura-add commit from the
    -- second commit that happens on removal with measuredDuration.
    fw.it("Ironbark with talent-extended duration commits TR-resolved buffDuration", function()
        local env = buildInitializedEnv({
            spellDataOverrides = {
                [102342] = { name = "Ironbark", cooldown = 90, duration = 12,
                             category = "External", class = "DRUID", specs = { 105 },
                             durationModifiers = { { talent = 392116, bonus = 4 } } },
            },
            talentsByName = {
                Druido = { [392116] = true },
            },
        })

        env.stubs.setTime(0)
        env.fire.OnAuraChanged("party1", {
            addedAuras = {
                { spellId = 102342, auraInstanceID = 9100, name = "Ironbark",
                  sourceUnit = "party2" },
            },
        })

        local cd = env.Store:Get("P-Druid", 102342)
        fw.assertTrue(cd, "Ironbark CD must be committed on the Druid caster")
        fw.assertClose(cd.buffDuration, 16, 0.5,
                       "buffDuration must reflect TR-resolved 12+4=16, not the base 12")
    end)
end)

fw.describe("Brain tracking — player cast snapshot rejects mismatched spell", function()
    -- Two Paladins in group; player just cast Divine Shield (Personal),
    -- not Blessing of Sacrifice. A BoS aura then lands on a teammate. The
    -- player must NOT be credited as the BoS caster even though their cast
    -- timestamp falls within the evidence window — the snapshot's spellID
    -- list (642) provably does not match the External BoS (6940).
    local function buildTwoPalEnv()
        local env = buildInitializedEnv()
        stubs.roster["party3"] = { guid = "P-ProtPal", name = "Tonk",
                                   class = "PALADIN", race = "Human",
                                   spec = 66, role = "TANK" }
        _G.GetNumGroupMembers = function() return 4 end
        env.ns.Core.Brain:Init()
        return env
    end

    fw.it("player who cast Divine Shield is not credited for a BoS on a teammate", function()
        local env = buildTwoPalEnv()
        env.stubs.setTime(80000)

        -- Player cast Divine Shield 20ms before the BoS aura starts.
        env.fire.OnLocalCast(642)
        env.stubs.setTime(80000.02)

        env.stubs.auraFilters["party2"] = {
            [6101] = { "HELPFUL|EXTERNAL_DEFENSIVE" },
        }
        local secretId, secretName = {}, {}
        env.stubs.secretValues[secretId] = true
        env.stubs.secretValues[secretName] = true

        env.fire.OnAuraChanged("party2", {
            addedAuras = {
                { spellId = secretId, auraInstanceID = 6101, name = secretName },
            },
        })
        env.fire.OnShieldChanged("party2")
        env.stubs.setTime(80012)
        env.fire.OnAuraChanged("party2", {
            removedAuraInstanceIDs = { 6101 },
        })

        local playerRec = env.Store:GetPlayerRec("P-Player")
        fw.assertTrue(not (playerRec and playerRec.cooldowns and playerRec.cooldowns[6940]),
                      "Player must NOT be attributed as the BoS caster after casting Divine Shield")
    end)
end)

fw.describe("Brain tracking — self-cast External fallback", function()
    -- Disc Priest (party2) self-casts Pain Suppression. The aura lands on
    -- party2 themselves. Detection must attribute the External to the Disc
    -- Priest (the target IS the caster), not silently drop the event.
    fw.it("self-cast Pain Suppression on Disc Priest commits to themselves", function()
        local env = buildInitializedEnv({
            spellDataOverrides = {
                [33206] = { name = "Pain Suppression", cooldown = 180, duration = 8,
                            category = "External", class = "PRIEST", specs = { 256 } },
            },
        })
        stubs.roster["party2"] = { guid = "P-Disc", name = "Discy",
                                   class = "PRIEST", race = "Human",
                                   spec = 256, role = "HEALER" }
        env.ns.Core.Brain:Init()

        env.stubs.setTime(90000)

        env.stubs.auraFilters["party2"] = {
            [7001] = { "HELPFUL|EXTERNAL_DEFENSIVE" },
        }
        local secretId, secretName = {}, {}
        env.stubs.secretValues[secretId] = true
        env.stubs.secretValues[secretName] = true

        env.fire.OnAuraChanged("party2", {
            addedAuras = {
                { spellId = secretId, auraInstanceID = 7001, name = secretName },
            },
        })
        env.stubs.setTime(90008)
        env.fire.OnAuraChanged("party2", {
            removedAuraInstanceIDs = { 7001 },
        })

        local rec = env.Store:GetPlayerRec("P-Disc")
        fw.assertTrue(rec, "Disc Priest record must exist as the self-attributed caster")
        fw.assertTrue(rec.cooldowns[33206],
                      "Pain Suppression must be on cooldown for the self-casting Disc Priest")
    end)
end)

fw.describe("Brain tracking — racial defensive readable-spellID path", function()
    fw.it("Stoneform on a Dwarf commits via tryImmediateDetection", function()
        local env = buildInitializedEnv({
            spellDataOverrides = {
                [20594] = { name = "Stoneform", cooldown = 120, duration = 8,
                            category = "Personal", race = "Dwarf",
                            requiresEvidence = false },
            },
        })
        stubs.roster["party3"] = { guid = "P-Dwarf", name = "Brewbeard",
                                   class = "WARRIOR", race = "Dwarf",
                                   role = "TANK" }
        env.ns.Core.Brain:Init()

        env.stubs.setTime(30000)
        env.fire.OnAuraChanged("party3", {
            addedAuras = {
                { spellId = 20594, auraInstanceID = 4000, name = "Stoneform" },
            },
        })

        local cd = env.Store:Get("P-Dwarf", 20594)
        fw.assertTrue(cd, "Stoneform CD should exist for the Dwarf unit")
        fw.assertEq(cd.duration, 120)
        fw.assertTrue(cd.buffActive, "buff should be active")
    end)

    fw.it("Stoneform on a non-Dwarf does NOT commit", function()
        local env = buildInitializedEnv({
            spellDataOverrides = {
                [20594] = { name = "Stoneform", cooldown = 120, duration = 8,
                            category = "Personal", race = "Dwarf",
                            requiresEvidence = false },
            },
        })
        stubs.roster["party3"] = { guid = "P-Human", name = "Joe",
                                   class = "WARRIOR", race = "Human",
                                   role = "TANK" }
        env.ns.Core.Brain:Init()

        env.stubs.setTime(31000)
        env.fire.OnAuraChanged("party3", {
            addedAuras = {
                { spellId = 20594, auraInstanceID = 4001, name = "Stoneform" },
            },
        })

        local cd = env.Store:Get("P-Human", 20594)
        fw.assertNil(cd, "Stoneform must not be committed on a non-Dwarf unit")
    end)
end)

fw.describe("Brain tracking — racial defensive name fallback when spellId secret", function()
    fw.it("Fireblood on a Dark Iron Dwarf bearer commits via name fallback", function()
        local env = buildInitializedEnv({
            spellDataOverrides = {
                [265221] = { name = "Fireblood", cooldown = 120, duration = 8,
                             category = "Personal", race = "DarkIronDwarf",
                             requiresEvidence = false },
            },
        })
        stubs.roster["party1"] = { guid = "P-DID", name = "Happy",
                                   class = "WARRIOR", race = "DarkIronDwarf",
                                   role = "DAMAGER" }
        env.ns.Core.Brain:Init()

        env.stubs.setTime(40000)
        local secretId = {}
        env.stubs.secretValues[secretId] = true
        env.fire.OnAuraChanged("party1", {
            addedAuras = {
                { spellId = secretId, auraInstanceID = 4100, name = "Fireblood" },
            },
        })
        env.stubs.setTime(40008)
        env.fire.OnAuraChanged("party1", {
            removedAuraInstanceIDs = { 4100 },
        })

        local cd = env.Store:Get("P-DID", 265221)
        fw.assertTrue(cd, "Fireblood CD should commit on the Dark Iron Dwarf bearer")
        fw.assertEq(cd.duration, 120)
    end)

    fw.it("Fireblood name on a non-Dark-Iron-Dwarf bearer does NOT commit", function()
        local env = buildInitializedEnv({
            spellDataOverrides = {
                [265221] = { name = "Fireblood", cooldown = 120, duration = 8,
                             category = "Personal", race = "DarkIronDwarf",
                             requiresEvidence = false },
            },
        })
        stubs.roster["party1"] = { guid = "P-Human2", name = "Joe2",
                                   class = "WARRIOR", race = "Human",
                                   role = "DAMAGER" }
        env.ns.Core.Brain:Init()

        env.stubs.setTime(41000)
        local secretId = {}
        env.stubs.secretValues[secretId] = true
        env.fire.OnAuraChanged("party1", {
            addedAuras = {
                { spellId = secretId, auraInstanceID = 4101, name = "Fireblood" },
            },
        })
        env.stubs.setTime(41008)
        env.fire.OnAuraChanged("party1", {
            removedAuraInstanceIDs = { 4101 },
        })

        local cd = env.Store:Get("P-Human2", 265221)
        fw.assertNil(cd, "Fireblood must not commit on a non-DID bearer")
    end)
end)

fw.describe("Brain tracking — racial defensive seedForUnit path", function()
    fw.it("seed includes Stoneform when local player is a Dwarf", function()
        local env = buildInitializedEnv({
            spellDataOverrides = {
                [20594] = { name = "Stoneform", cooldown = 120, duration = 8,
                            category = "Personal", race = "Dwarf",
                            requiresEvidence = false },
            },
        })
        -- Make the local player a Dwarf and mark Stoneform as a known spell.
        stubs.roster["player"] = { guid = "P-Player", name = "Myself",
                                   class = "WARRIOR", race = "Dwarf",
                                   role = "TANK", spec = 73 }
        stubs.playerKnownSpells[20594] = true

        env.Brain._seedRoster()
        env.stubs.flushTimers(env.stubs.currentTime + 1)

        local cd = env.Store:Get("P-Player", 20594)
        fw.assertTrue(cd, "Stoneform must be seeded for a Dwarf player")
    end)

    fw.it("seed probes castSpellId when the catalog key is the aura ID", function()
        -- Real Stoneform: catalog key 65116 (aura), castSpellId 20594.
        -- IsPlayerSpell(65116) returns false; the seed must probe castSpellId
        -- instead so the entry is included for a Dwarf who knows the spell.
        local env = buildInitializedEnv({
            spellDataOverrides = {
                [65116] = { name = "Stoneform", cooldown = 120, duration = 8,
                            category = "Personal", race = "Dwarf",
                            castSpellId = 20594, requiresEvidence = false },
            },
        })
        stubs.roster["player"] = { guid = "P-Player", name = "Myself",
                                   class = "WARRIOR", race = "Dwarf",
                                   role = "TANK", spec = 73 }
        -- Only the cast ID is known to the player; aura ID is never returned by IsPlayerSpell.
        stubs.playerKnownSpells[20594] = true

        env.Brain._seedRoster()
        env.stubs.flushTimers(env.stubs.currentTime + 1)

        local cd = env.Store:Get("P-Player", 65116)
        fw.assertTrue(cd, "Stoneform aura ID must be seeded via castSpellId probe")
    end)

    fw.it("seed does NOT include Stoneform for a Human player", function()
        local env = buildInitializedEnv({
            spellDataOverrides = {
                [20594] = { name = "Stoneform", cooldown = 120, duration = 8,
                            category = "Personal", race = "Dwarf",
                            requiresEvidence = false },
            },
        })
        stubs.roster["player"] = { guid = "P-Player", name = "Myself",
                                   class = "WARRIOR", race = "Human",
                                   role = "TANK", spec = 73 }
        stubs.playerKnownSpells[20594] = true

        env.Brain._seedRoster()
        env.stubs.flushTimers(env.stubs.currentTime + 1)

        local cd = env.Store:Get("P-Player", 20594)
        fw.assertNil(cd, "Stoneform must not be seeded for a non-Dwarf player")
    end)
end)

fw.describe("Brain — spec change wipes stale source=aura entries", function()
    fw.it("reason='spec' purges a player record holding a converted entry", function()
        stubs.reset()
        stubs.playerKnownSpells[642] = true
        stubs.roster["player"] = { guid = "P-Player", name = "Myself",
                                   class = "PALADIN", race = "Human",
                                   role = "HEALER", spec = 65 }
        local env = buildInitializedEnv()

        env.stubs.setTime(1000)
        env.fire.OnLocalCast(642)
        local before = env.Store:Get("P-Player", 642)
        fw.assertTrue(before, "precondition: Divine Shield CD entry exists")
        fw.assertEq(before.source, "aura")

        env.stubs.roster["player"].spec = 70
        env.fireSpecChanged("player", "spec")

        local after = env.Store:Get("P-Player", 642)
        fw.assertTrue(after == nil or after.source ~= "aura",
                      "spec change must drop the stale source=aura entry")
    end)

    fw.it("reason='talents' preserves a converted entry (back-compat)", function()
        stubs.reset()
        stubs.playerKnownSpells[642] = true
        stubs.roster["player"] = { guid = "P-Player", name = "Myself",
                                   class = "PALADIN", race = "Human",
                                   role = "HEALER", spec = 65 }
        local env = buildInitializedEnv()

        env.stubs.setTime(1000)
        env.fire.OnLocalCast(642)
        local before = env.Store:Get("P-Player", 642)
        fw.assertTrue(before, "precondition: Divine Shield CD entry exists")
        fw.assertEq(before.source, "aura")

        env.fireSpecChanged("player", "talents")

        local after = env.Store:Get("P-Player", 642)
        fw.assertTrue(after, "talents-only respec must keep the active CD entry")
        fw.assertEq(after.source, "aura")
        fw.assertEq(after.startedAt, 1000)
    end)

    fw.it("nil reason behaves like talents (back-compat with 1-arg callers)", function()
        stubs.reset()
        stubs.playerKnownSpells[642] = true
        stubs.roster["player"] = { guid = "P-Player", name = "Myself",
                                   class = "PALADIN", race = "Human",
                                   role = "HEALER", spec = 65 }
        local env = buildInitializedEnv()

        env.stubs.setTime(1000)
        env.fire.OnLocalCast(642)

        env.fireSpecChanged("player", nil)

        local after = env.Store:Get("P-Player", 642)
        fw.assertTrue(after, "1-arg callers must not destroy active CD entries")
        fw.assertEq(after.source, "aura")
    end)
end)

fw.describe("Brain tracking — Raidwide cross-class duration match", function()
    -- Rallying Cry is class=WARRIOR, category=Raidwide. Its buff lands on
    -- every party member; the bearer's class is independent of the caster's.
    -- The bearer-cast lookup must not pin the buff on the wrong unit and
    -- the cross-class roster pass must attribute to the warrior caster.
    local function buildEnv()
        local env = buildInitializedEnv({
            spellDataOverrides = {
                [97463] = { name = "Rallying Cry", cooldown = 180, duration = 10,
                            category = "Raidwide", class = "WARRIOR",
                            requiresEvidence = false },
            },
        })
        stubs.roster["party3"] = { guid = "P-War", name = "Hapy",
                                   class = "WARRIOR", race = "Human",
                                   spec = 72, role = "DAMAGER" }
        _G.GetNumGroupMembers = function() return 4 end
        env.ns.Core.Brain:Init()
        return env
    end

    fw.it("Pal bearer of Rallying Cry attributes to the warrior caster via cast evidence", function()
        local env = buildEnv()
        env.stubs.setTime(50000)
        env.Brain._lastCastTime["party3"] = 50000.02

        local secretId, secretName = {}, {}
        env.stubs.secretValues[secretId] = true
        env.stubs.secretValues[secretName] = true
        env.stubs.auraFilters["player"] = {
            [9001] = { "HELPFUL|IMPORTANT" },
        }
        env.fire.OnAuraChanged("player", {
            addedAuras = {
                { spellId = secretId, auraInstanceID = 9001, name = secretName },
            },
        })
        env.stubs.setTime(50010)
        env.fire.OnAuraChanged("player", {
            removedAuraInstanceIDs = { 9001 },
        })

        local warRec = env.Store:GetPlayerRec("P-War")
        fw.assertTrue(warRec and warRec.cooldowns[97463],
                      "Rallying Cry must commit on the warrior, not the Pal bearer")
        local palRec = env.Store:GetPlayerRec("P-Player")
        fw.assertTrue(not (palRec and palRec.cooldowns and palRec.cooldowns[97463]),
                      "Pal bearer must not be marked as the Rallying Cry caster")
    end)

    fw.it("Warrior bearer commits on the warrior — bearer is the caster", function()
        local env = buildEnv()
        env.stubs.setTime(51000)

        local secretId, secretName = {}, {}
        env.stubs.secretValues[secretId] = true
        env.stubs.secretValues[secretName] = true
        env.stubs.auraFilters["party3"] = {
            [9002] = { "HELPFUL|IMPORTANT" },
        }
        env.fire.OnAuraChanged("party3", {
            addedAuras = {
                { spellId = secretId, auraInstanceID = 9002, name = secretName },
            },
        })
        env.stubs.setTime(51010)
        env.fire.OnAuraChanged("party3", {
            removedAuraInstanceIDs = { 9002 },
        })

        local cd = env.Store:Get("P-War", 97463)
        fw.assertTrue(cd, "Rallying Cry must commit on the warrior bearer")
    end)

    fw.it("Readable Rallying Cry spellID on a non-warrior bearer is not stamped on the bearer", function()
        local env = buildEnv()
        env.stubs.setTime(52000)
        env.Brain._lastCastTime["party3"] = 52000.02

        env.fire.OnAuraChanged("player", {
            addedAuras = {
                { spellId = 97463, auraInstanceID = 9003, name = "Rallying Cry" },
            },
        })
        env.stubs.setTime(52010)
        env.fire.OnAuraChanged("player", {
            removedAuraInstanceIDs = { 9003 },
        })

        local palRec = env.Store:GetPlayerRec("P-Player")
        fw.assertTrue(not (palRec and palRec.cooldowns and palRec.cooldowns[97463]),
                      "Bearer with mismatched class must never receive the cooldown")
        local warRec = env.Store:GetPlayerRec("P-War")
        fw.assertTrue(warRec and warRec.cooldowns[97463],
                      "Cross-class Raidwide must attribute to the warrior caster")
    end)
end)

fw.describe("Brain tracking — racial duration match (secret spellID)", function()
    -- Racials are race-keyed in SpellData (no info.class). The bearer-cast
    -- duration match must walk spellsByRace[bearer's race] alongside the
    -- per-class lists, otherwise an M+ tainted aura on a Dark Iron Dwarf
    -- never resolves to Fireblood.
    local function buildEnv()
        local env = buildInitializedEnv({
            spellDataOverrides = {
                [265221] = { name = "Fireblood", cooldown = 120, duration = 8,
                             category = "Personal", race = "DarkIronDwarf",
                             requiresEvidence = false },
            },
        })
        stubs.roster["party3"] = { guid = "P-Dwarf", name = "Hapy",
                                   class = "WARRIOR", race = "DarkIronDwarf",
                                   spec = 72, role = "DAMAGER" }
        _G.GetNumGroupMembers = function() return 4 end
        env.ns.Core.Brain:Init()
        return env
    end

    fw.it("Fireblood on a Dark Iron Dwarf resolves at removal", function()
        local env = buildEnv()
        env.stubs.setTime(53000)

        local secretId, secretName = {}, {}
        env.stubs.secretValues[secretId] = true
        env.stubs.secretValues[secretName] = true
        env.stubs.auraFilters["party3"] = {
            [9100] = { "HELPFUL|IMPORTANT" },
        }
        env.fire.OnAuraChanged("party3", {
            addedAuras = {
                { spellId = secretId, auraInstanceID = 9100, name = secretName },
            },
        })
        env.stubs.setTime(53008)
        env.fire.OnAuraChanged("party3", {
            removedAuraInstanceIDs = { 9100 },
        })

        local cd = env.Store:Get("P-Dwarf", 265221)
        fw.assertTrue(cd, "Fireblood must commit on the Dark Iron Dwarf bearer")
    end)

    fw.it("Same-duration racial does not match a non-matching race", function()
        local env = buildEnv()
        env.stubs.setTime(54000)
        stubs.roster["party4"] = { guid = "P-Human", name = "Notdwarf",
                                   class = "WARRIOR", race = "Human",
                                   spec = 72, role = "DAMAGER" }
        _G.GetNumGroupMembers = function() return 5 end
        env.ns.Core.Brain:Init()

        local secretId, secretName = {}, {}
        env.stubs.secretValues[secretId] = true
        env.stubs.secretValues[secretName] = true
        env.stubs.auraFilters["party4"] = {
            [9101] = { "HELPFUL|IMPORTANT" },
        }
        env.fire.OnAuraChanged("party4", {
            addedAuras = {
                { spellId = secretId, auraInstanceID = 9101, name = secretName },
            },
        })
        env.stubs.setTime(54008)
        env.fire.OnAuraChanged("party4", {
            removedAuraInstanceIDs = { 9101 },
        })

        fw.assertNil(env.Store:Get("P-Human", 265221),
                     "Fireblood must never attach to a Human bearer")
    end)
end)


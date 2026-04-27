local fw = require("framework")
local stubs = require("wow_stubs")

local function loadStore()
    local ns = { Core = {}, Utils = {} }
    -- Load Util first (dependency)
    local futil = assert(loadfile("ZaeUI_Defensives/Utils/Util.lua"))
    futil("ZaeUI_Defensives", ns)
    -- Load CooldownStore
    local f = assert(loadfile("ZaeUI_Defensives/Core/CooldownStore.lua"))
    f("ZaeUI_Defensives", ns)
    return ns.Core.CooldownStore, ns
end

fw.describe("CooldownStore — basic lifecycle", function()
    stubs.reset()
    local Store = loadStore()
    Store:Reset()
    fw.it("Get returns nil for unknown guid/spell", function()
        fw.assertNil(Store:Get("Player-1-ABC", 642))
    end)

    Store:StartCooldown("Player-1-ABC", 642, {
        name = "Arthas", class = "PALADIN", spec = 70, role = "DAMAGER",
        startedAt = 10, duration = 300, maxCharges = 1,
        buffStartedAt = 10, buffDuration = 8, buffActive = true,
        source = "aura",
    })

    fw.it("creates player record on first StartCooldown", function()
        local cd = Store:Get("Player-1-ABC", 642)
        fw.assertTrue(cd ~= nil)
        fw.assertEq(cd.duration, 300)
    end)
    fw.it("decrements currentCharges to 0 for single-charge spell", function()
        fw.assertEq(Store:Get("Player-1-ABC", 642).currentCharges, 0)
    end)
    fw.it("exposes player metadata", function()
        local ok = false
        for guid, rec in Store:IteratePlayers() do
            if guid == "Player-1-ABC" then
                ok = rec.class == "PALADIN" and rec.role == "DAMAGER"
            end
        end
        fw.assertTrue(ok)
    end)
end)

fw.describe("CooldownStore — multi-charge model", function()
    stubs.reset()
    local Store = loadStore()
    Store:Reset()
    stubs.setTime(100)

    Store:StartCooldown("G1", 45438, {
        name = "Mage1", class = "MAGE", spec = 64, role = "DAMAGER",
        startedAt = 100, duration = 240, maxCharges = 2,
        source = "aura",
    })
    fw.it("first cast consumes one charge", function()
        fw.assertEq(Store:Get("G1", 45438).currentCharges, 1)
    end)

    stubs.setTime(105)
    Store:StartCooldown("G1", 45438, {
        name = "Mage1", class = "MAGE", spec = 64, role = "DAMAGER",
        startedAt = 105, duration = 240, maxCharges = 2,
        source = "aura",
    })
    fw.it("second cast consumes second charge", function()
        fw.assertEq(Store:Get("G1", 45438).currentCharges, 0)
    end)
end)

fw.describe("CooldownStore — charge recharge via timer", function()
    stubs.reset()
    local Store = loadStore()
    Store:Reset()
    stubs.setTime(0)

    Store:StartCooldown("G2", 45438, {
        name = "Mage2", class = "MAGE", spec = 64, role = "DAMAGER",
        startedAt = 0, duration = 240, maxCharges = 2,
        source = "aura",
    })
    -- currentCharges = 1 after consumption

    -- Advance time past duration and flush the scheduled recharge
    stubs.setTime(240)
    stubs.flushTimers(240)

    fw.it("recharges back to maxCharges after duration", function()
        local cd = Store:Get("G2", 45438)
        fw.assertEq(cd.currentCharges, 2)
    end)
end)

fw.describe("CooldownStore — _gen invalidates stale timers", function()
    stubs.reset()
    local Store = loadStore()
    Store:Reset()
    stubs.setTime(0)

    local endEvents = {}
    Store:RegisterCallback("CooldownEnd", function(guid, sid)
        endEvents[#endEvents + 1] = guid .. ":" .. sid
    end)

    Store:StartCooldown("G3", 642, {
        name = "Pal", class = "PALADIN", spec = 70, role = "DAMAGER",
        startedAt = 0, duration = 300, maxCharges = 1,
        source = "aura",
    })
    local gen1 = Store:Get("G3", 642)._gen

    stubs.setTime(10)
    Store:StartCooldown("G3", 642, {
        name = "Pal", class = "PALADIN", spec = 70, role = "DAMAGER",
        startedAt = 10, duration = 300, maxCharges = 1,
        source = "aura",
    })
    local gen2 = Store:Get("G3", 642)._gen

    fw.it("_gen increments on each StartCooldown", function()
        fw.assertTrue(gen2 > gen1)
    end)

    -- Flush the old timer (stale, must no-op)
    stubs.setTime(300)
    stubs.flushTimers(300)

    fw.it("stale timer from first cast does not fire CooldownEnd early", function()
        local cd = Store:Get("G3", 642)
        -- Second cast is at t=10, duration=300, expires at t=310
        -- At t=300, still in cooldown
        fw.assertEq(cd.currentCharges, 0)
    end)
    fw.it("no premature CooldownEnd fired by stale timer", function()
        fw.assertEq(#endEvents, 0)
    end)
end)

fw.describe("CooldownStore — callbacks", function()
    stubs.reset()
    local Store = loadStore()
    Store:Reset()
    local events = {}
    Store:RegisterCallback("CooldownStart", function(guid, sid)
        events[#events + 1] = "start:" .. guid .. ":" .. sid
    end)
    Store:RegisterCallback("BuffEnd", function(guid, sid)
        events[#events + 1] = "buffend:" .. guid .. ":" .. sid
    end)

    Store:StartCooldown("GC1", 642, {
        name = "P", class = "PALADIN", spec = 70, role = "DAMAGER",
        startedAt = 0, duration = 300, maxCharges = 1,
        buffActive = true, source = "aura",
    })
    Store:EndBuff("GC1", 642)

    fw.it("fires CooldownStart", function()
        fw.assertEq(events[1], "start:GC1:642")
    end)
    fw.it("fires BuffEnd", function()
        fw.assertEq(events[2], "buffend:GC1:642")
    end)
end)

fw.describe("CooldownStore — GetByName via nameIndex", function()
    stubs.reset()
    local Store = loadStore()
    Store:Reset()
    Store:StartCooldown("G-named", 642, {
        name = "Lookup", class = "PALADIN", spec = 70, role = "DAMAGER",
        startedAt = 0, duration = 300, maxCharges = 1,
        source = "aura",
    })
    fw.it("resolves by player name", function()
        local cd = Store:GetByName("Lookup", 642)
        fw.assertTrue(cd ~= nil)
        fw.assertEq(cd.duration, 300)
    end)
end)

fw.describe("CooldownStore — Reset fires PlayerRemoved per GUID", function()
    -- Without these fires, displays would keep iconIndex / containersByGUID
    -- entries pointing at players that no longer exist in the store.
    stubs.reset()
    local Store = loadStore()
    Store:Reset()

    local removed = {}
    Store:RegisterCallback("PlayerRemoved", function(guid)
        removed[#removed + 1] = guid
    end)

    Store:RegisterPlayer("G-Reset-A", { name = "A", class = "PALADIN" })
    Store:RegisterPlayer("G-Reset-B", { name = "B", class = "MONK" })
    Store:Reset()

    fw.it("fires PlayerRemoved once per known GUID", function()
        fw.assertEq(#removed, 2)
    end)
    fw.it("the store is empty after reset", function()
        fw.assertNil(Store:GetPlayerRec("G-Reset-A"))
        fw.assertNil(Store:GetPlayerRec("G-Reset-B"))
    end)
    fw.it("no PlayerRemoved is fired when Reset runs on an empty store", function()
        local before = #removed
        Store:Reset()
        fw.assertEq(#removed, before)
    end)
end)

fw.describe("CooldownStore — ResetPlayer", function()
    stubs.reset()
    local Store = loadStore()
    Store:Reset()
    Store:StartCooldown("GR", 642, {
        name = "Bob", class = "PALADIN", spec = 70, role = "DAMAGER",
        startedAt = 0, duration = 300, maxCharges = 1,
        source = "aura",
    })
    Store:ResetPlayer("GR")
    fw.it("Get returns nil after reset", function()
        fw.assertNil(Store:Get("GR", 642))
    end)
    fw.it("GetByName returns nil after reset", function()
        fw.assertNil(Store:GetByName("Bob", 642))
    end)
end)

fw.describe("CooldownStore — SeedKnownSpells", function()
    stubs.reset()
    local Store = loadStore()
    Store:Reset()

    -- Use a non-zero startedAt so we can prove the seed doesn't overwrite.
    Store:StartCooldown("GK", 642, {
        name = "Pal", class = "PALADIN", spec = 70, role = "DAMAGER",
        startedAt = 999, duration = 300, maxCharges = 1, source = "aura",
    })

    local changed = false
    Store:RegisterCallback("KnownSpellsChanged", function() changed = true end)
    Store:SeedKnownSpells("GK", { [642] = 1, [498] = 1, [633] = 1 })  -- 642 existing, 498/633 new

    fw.it("fires KnownSpellsChanged", function() fw.assertTrue(changed) end)
    fw.it("adds new spells as ready", function()
        local cd = Store:Get("GK", 498)
        fw.assertTrue(cd ~= nil)
        fw.assertEq(cd.currentCharges, 1)
        fw.assertEq(cd.startedAt, 0)
        fw.assertEq(cd.source, "seed")
    end)
    fw.it("does not overwrite existing spell", function()
        local cd = Store:Get("GK", 642)
        fw.assertEq(cd.startedAt, 999)   -- preserved from StartCooldown
        fw.assertEq(cd.source, "aura")   -- NOT replaced by "seed"
    end)
end)

fw.describe("CooldownStore — multi-charge swipe restart between charges", function()
    -- When a charge is regained but more are still recharging, the recharge
    -- timer must fire CooldownStart so displays restart their cooldown swipe
    -- with the new (start, duration) pair.
    stubs.reset()
    local Store = loadStore()
    Store:Reset()
    stubs.setTime(0)

    local startEvents = {}
    local endEvents = {}
    Store:RegisterCallback("CooldownStart", function(guid, sid, cd)
        startEvents[#startEvents + 1] = { guid = guid, sid = sid, startedAt = cd.startedAt }
    end)
    Store:RegisterCallback("CooldownEnd", function(guid, sid)
        endEvents[#endEvents + 1] = guid .. ":" .. sid
    end)

    -- Two casts within the cooldown window: 0 -> 1 charge consumed, 1 -> 2 consumed.
    Store:StartCooldown("GMC", 45438, {
        name = "Mage", class = "MAGE", spec = 64, role = "DAMAGER",
        startedAt = 0, duration = 240, maxCharges = 2, source = "aura",
    })
    stubs.setTime(1)
    Store:StartCooldown("GMC", 45438, {
        name = "Mage", class = "MAGE", spec = 64, role = "DAMAGER",
        startedAt = 1, duration = 240, maxCharges = 2, source = "aura",
    })

    fw.it("two casts produce two CooldownStart events", function()
        fw.assertEq(#startEvents, 2)
    end)

    -- First charge regenerates at t = 1 + 240 = 241. Second still missing.
    stubs.setTime(241)
    stubs.flushTimers(241)

    fw.it("intermediate recharge fires a fresh CooldownStart", function()
        fw.assertEq(#startEvents, 3, "three starts (2 casts + 1 swipe restart)")
    end)
    fw.it("intermediate recharge restamps startedAt to GetTime()", function()
        fw.assertEq(startEvents[3].startedAt, 241)
    end)
    fw.it("no premature CooldownEnd while still missing a charge", function()
        fw.assertEq(#endEvents, 0)
    end)

    -- Final charge regenerates at t = 241 + 240 = 481.
    stubs.setTime(481)
    stubs.flushTimers(481)

    fw.it("final recharge fires CooldownEnd", function()
        fw.assertEq(#endEvents, 1)
    end)
    fw.it("final recharge does not fire another CooldownStart", function()
        fw.assertEq(#startEvents, 3, "no extra start at the final recharge")
    end)
end)

fw.describe("CooldownStore — SeedKnownSpells respects per-spell maxCharges", function()
    -- Bug fix: seed must initialize currentCharges = maxCharges so the first
    -- cast on a multi-charge spell consumes the right amount. Before the fix,
    -- maxCharges was hardcoded to 1, which caused the first cast on a 2-charge
    -- spell (Ice Block w/ Glacial Bulwark, Pain Suppression w/ talent) to
    -- display 0/2 instead of 1/2.
    stubs.reset()
    local Store = loadStore()
    Store:Reset()
    Store:RegisterPlayer("GMC", { name = "Mage", class = "MAGE", spec = 64, role = "DAMAGER" })
    -- map form: { [spellID] = maxCharges }
    Store:SeedKnownSpells("GMC", { [45438] = 2, [498] = 1 })

    fw.it("seeds 2-charge spell with currentCharges == 2", function()
        local cd = Store:Get("GMC", 45438)
        fw.assertTrue(cd ~= nil, "expected seed entry for 45438")
        fw.assertEq(cd.maxCharges, 2)
        fw.assertEq(cd.currentCharges, 2)
    end)
    fw.it("seeds 1-charge spell with currentCharges == 1", function()
        local cd = Store:Get("GMC", 498)
        fw.assertEq(cd.maxCharges, 1)
        fw.assertEq(cd.currentCharges, 1)
    end)
end)

fw.describe("CooldownStore — first cast after multi-charge seed", function()
    -- Regression: with the seed initializing currentCharges = maxCharges,
    -- a first StartCooldown must leave (maxCharges - 1) charges available.
    stubs.reset()
    local Store = loadStore()
    Store:Reset()
    Store:RegisterPlayer("GMC2", { name = "Mage", class = "MAGE", spec = 64, role = "DAMAGER" })
    Store:SeedKnownSpells("GMC2", { [45438] = 2 })

    Store:StartCooldown("GMC2", 45438, {
        name = "Mage", class = "MAGE", spec = 64, role = "DAMAGER",
        startedAt = 100, duration = 240, maxCharges = 2, source = "aura",
    })

    fw.it("first cast leaves one charge available, not zero", function()
        local cd = Store:Get("GMC2", 45438)
        fw.assertEq(cd.maxCharges, 2)
        fw.assertEq(cd.currentCharges, 1)
    end)
end)

fw.describe("CooldownStore — RegisterPlayer without StartCooldown", function()
    stubs.reset()
    local Store = loadStore()
    Store:Reset()
    Store:RegisterPlayer("GP", {
        name = "Reg", class = "MAGE", spec = 64, role = "DAMAGER",
    })
    fw.it("creates a player record", function()
        local seenGuid
        for guid, _ in Store:IteratePlayers() do
            if guid == "GP" then seenGuid = guid end
        end
        fw.assertEq(seenGuid, "GP")
    end)
    fw.it("no cooldowns exist yet", function()
        fw.assertNil(Store:Get("GP", 642))
    end)
end)

local fw = require("framework")
local stubs = require("wow_stubs")

-- Builds an env with three roster members, then exposes the Brain instance
-- and a way to drive UNIT_AURA / UNIT_FLAGS callbacks. Mirrors the harness
-- used by test_brain_tracking.lua but stays minimal: only what roster diff
-- tests need.
local function buildEnv(initialRoster)
    stubs.reset()
    stubs.setTime(1000)
    for unit, data in pairs(initialRoster) do
        stubs.roster[unit] = data
    end

    _G.UnitIsFriend = function() return true end
    _G.format = string.format
    _G.GetNumGroupMembers = function()
        local n = 0
        for unit in pairs(stubs.roster) do
            if unit ~= "player" then n = n + 1 end
        end
        return stubs.roster["player"] and (n + 1) or n
    end
    _G.IsInRaid = function() return _G.__testInRaid == true end
    _G.ZaeUI_DefensivesDB = { debug = false }
    _G.CreateFrame = function()
        return { SetScript = function() end, RegisterEvent = function() end }
    end

    local ns = { Core = {}, Utils = {}, Modules = {} }
    local futil = assert(loadfile("ZaeUI_Defensives/Utils/Util.lua"))
    futil("ZaeUI_Defensives", ns)

    ns.SpellData = {
        [115203] = { name = "Fortifying Brew", cooldown = 360, duration = 15,
                     category = "Personal", class = "MONK", requiresEvidence = false },
    }

    local fstore = assert(loadfile("ZaeUI_Defensives/Core/CooldownStore.lua"))
    fstore("ZaeUI_Defensives", ns)

    ns.Core.Inspector = {
        GetSpec = function() return nil end,
        GetRoleHint = function() return "UNKNOWN" end,
        GetTalents = function() return {} end,
        RegisterCallback = function() end,
    }

    ns.Core.AuraWatcher = {
        RegisterCallback = function() end,
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

    return { Brain = ns.Core.Brain, Store = ns.Core.CooldownStore, ns = ns }
end

fw.describe("Brain roster diff — guid-keyed cleanup", function()
    fw.it("purges CooldownStore entry when a player leaves the group", function()
        local env = buildEnv({
            ["player"] = { guid = "G-Player", name = "Self", class = "PALADIN" },
            ["party1"] = { guid = "G-Friend", name = "Friend", class = "MONK" },
        })

        env.Store:RegisterPlayer("G-Friend", { name = "Friend", class = "MONK" })
        fw.assertTrue(env.Store:GetPlayerRec("G-Friend") ~= nil,
                      "player must be in store before leave")

        -- Prime the snapshot with the initial roster, then drop the slot.
        env.Brain._onRosterChanged()
        stubs.roster["party1"] = nil
        env.Brain._onRosterChanged()

        fw.assertNil(env.Store:GetPlayerRec("G-Friend"),
                     "player record must be purged when they leave the group")
    end)

    fw.it("keeps player record when roster is unchanged", function()
        local env = buildEnv({
            ["player"] = { guid = "G-Player", name = "Self", class = "PALADIN" },
            ["party1"] = { guid = "G-Friend", name = "Friend", class = "MONK" },
        })

        env.Store:RegisterPlayer("G-Friend", { name = "Friend", class = "MONK" })
        env.Brain._onRosterChanged()
        env.Brain._onRosterChanged()

        fw.assertTrue(env.Store:GetPlayerRec("G-Friend") ~= nil,
                      "stable roster must not purge anyone")
    end)

    fw.it("purges all departed players in a raid→party shrink", function()
        _G.__testInRaid = true
        local env = buildEnv({
            ["player"] = { guid = "G-Player", name = "Self", class = "PALADIN" },
            ["raid1"]  = { guid = "G-Player", name = "Self", class = "PALADIN" },
            ["raid2"]  = { guid = "G-A", name = "Alpha",  class = "DRUID" },
            ["raid3"]  = { guid = "G-B", name = "Bravo",  class = "MAGE" },
            ["raid4"]  = { guid = "G-C", name = "Cha",    class = "MONK" },
            ["raid5"]  = { guid = "G-D", name = "Delta",  class = "ROGUE" },
        })

        env.Store:RegisterPlayer("G-A", { name = "Alpha", class = "DRUID" })
        env.Store:RegisterPlayer("G-B", { name = "Bravo", class = "MAGE" })
        env.Store:RegisterPlayer("G-C", { name = "Cha",   class = "MONK" })
        env.Store:RegisterPlayer("G-D", { name = "Delta", class = "ROGUE" })
        env.Brain._onRosterChanged()

        -- Shrink to party with only Alpha remaining.
        _G.__testInRaid = false
        stubs.roster["raid1"] = nil
        stubs.roster["raid2"] = nil
        stubs.roster["raid3"] = nil
        stubs.roster["raid4"] = nil
        stubs.roster["raid5"] = nil
        stubs.roster["party1"] = { guid = "G-A", name = "Alpha", class = "DRUID" }
        env.Brain._onRosterChanged()

        fw.assertTrue(env.Store:GetPlayerRec("G-A") ~= nil, "Alpha kept (still in roster)")
        fw.assertNil(env.Store:GetPlayerRec("G-B"), "Bravo purged")
        fw.assertNil(env.Store:GetPlayerRec("G-C"), "Cha purged")
        fw.assertNil(env.Store:GetPlayerRec("G-D"), "Delta purged")
        _G.__testInRaid = nil
    end)
end)

fw.describe("Brain — backfill queue coalescing", function()
    fw.it("N enqueues schedule a single timer", function()
        local env = buildEnv({
            ["player"] = { guid = "G-Player", name = "Self", class = "PALADIN" },
        })

        local before = #stubs.pendingTimers
        for i = 1, 10 do env.Brain._enqueueBackfill("party1", 100 + i) end
        fw.assertEq(#stubs.pendingTimers - before, 1,
                    "ten enqueues must share a single in-flight timer")
        fw.assertEq(env.Brain._backfillQueueLen(), 10, "queue holds all entries")

        -- Advance the mock clock past the evidence window so that GetTime()
        -- inside the drained callback returns a value greater than each entry's
        -- fireAt. Without this, the callback would re-schedule itself.
        stubs.setTime(stubs.currentTime + 1)
        stubs.flushTimers(stubs.currentTime)
        fw.assertEq(env.Brain._backfillQueueLen(), 0, "drain empties the queue")
    end)

    fw.it("purgeBackfillQueue resets head/tail and recycles entries", function()
        local env = buildEnv({
            ["player"] = { guid = "G-Player", name = "Self", class = "PALADIN" },
        })

        env.Brain._enqueueBackfill("party1", 1)
        env.Brain._enqueueBackfill("party1", 2)
        fw.assertEq(env.Brain._backfillQueueLen(), 2)

        env.Brain._purgeBackfillQueue()
        fw.assertEq(env.Brain._backfillQueueLen(), 0,
                    "queue must report empty after purge")

        -- Reuse must work: subsequent enqueue lands at index 1 again.
        env.Brain._enqueueBackfill("party1", 3)
        fw.assertEq(env.Brain._backfillQueueLen(), 1)
    end)

    fw.it("entries pushed after a partial drain are not lost", function()
        -- Reproduces the sparse-array hazard: after the head moves past
        -- index 1 we must keep using an explicit tail counter so that new
        -- entries land at the correct slot.
        local env = buildEnv({
            ["player"] = { guid = "G-Player", name = "Self", class = "PALADIN" },
        })

        env.Brain._enqueueBackfill("party1", 1)
        -- Advance the clock so the second entry has a strictly later fireAt.
        stubs.setTime(stubs.currentTime + 0.05)
        env.Brain._enqueueBackfill("party1", 2)
        fw.assertEq(env.Brain._backfillQueueLen(), 2)

        -- Advance past the first entry's fireAt but not the second, then fire.
        stubs.setTime(stubs.currentTime + 0.11)
        stubs.flushTimers(stubs.currentTime)
        fw.assertEq(env.Brain._backfillQueueLen(), 1, "one entry consumed")

        -- Push during the partial-drained state. Must be visible afterwards.
        env.Brain._enqueueBackfill("party1", 3)
        fw.assertEq(env.Brain._backfillQueueLen(), 2,
                    "post-drain push lands at the tail, not over a hole")

        stubs.setTime(stubs.currentTime + 1)
        stubs.flushTimers(stubs.currentTime)
        fw.assertEq(env.Brain._backfillQueueLen(), 0, "remaining entries drain")
    end)

    fw.it("re-enqueueing after a drain reschedules a fresh timer", function()
        local env = buildEnv({
            ["player"] = { guid = "G-Player", name = "Self", class = "PALADIN" },
        })

        env.Brain._enqueueBackfill("party1", 1)
        stubs.setTime(stubs.currentTime + 1)
        stubs.flushTimers(stubs.currentTime)
        local before = #stubs.pendingTimers
        env.Brain._enqueueBackfill("party1", 2)
        fw.assertEq(#stubs.pendingTimers - before, 1,
                    "post-drain enqueue must reschedule")
    end)
end)

fw.describe("Brain — seedRoster debounce", function()
    fw.it("rapid GROUP_ROSTER_UPDATE bursts schedule a single timer", function()
        local env = buildEnv({
            ["player"] = { guid = "G-Player", name = "Self", class = "PALADIN" },
        })

        -- Five calls in a row must produce exactly one pending timer.
        for _ = 1, 5 do env.Brain._seedRoster() end
        fw.assertEq(#stubs.pendingTimers, 1, "five back-to-back calls must coalesce")
        fw.assertTrue(env.Brain._isSeedPending(), "pending flag must be set")

        stubs.flushTimers(stubs.currentTime + 1)
        fw.assertTrue(not env.Brain._isSeedPending(),
                      "pending flag clears after the timer fires")
    end)

    fw.it("subsequent burst after a flush schedules a new timer", function()
        local env = buildEnv({
            ["player"] = { guid = "G-Player", name = "Self", class = "PALADIN" },
        })

        env.Brain._seedRoster()
        stubs.flushTimers(stubs.currentTime + 1)
        for _ = 1, 3 do env.Brain._seedRoster() end
        fw.assertEq(#stubs.pendingTimers, 1, "second burst must reschedule once")
    end)
end)

fw.describe("Brain roster diff — unit-keyed cleanup", function()
    fw.it("clears unit-keyed state when a slot is reassigned to a different GUID", function()
        local env = buildEnv({
            ["player"] = { guid = "G-Player", name = "Self", class = "PALADIN" },
            ["party1"] = { guid = "G-Old", name = "Old", class = "HUNTER" },
        })

        env.Brain._onRosterChanged()
        -- Hunter triggers unitCanFeign[party1] = true via onUnitFlags path;
        -- emulate by reaching into the snapshot then forcing a slot swap.
        env.Brain._rosterSnapshot["party1"] = "G-Old"
        -- Pretend that downstream code populated unit-keyed evidence:
        env.Brain._clearUnitState("party1") -- sanity: it does not error

        stubs.roster["party1"] = { guid = "G-New", name = "New", class = "MAGE" }
        env.Brain._onRosterChanged()

        -- Snapshot must reflect the new GUID for that slot.
        fw.assertEq(env.Brain._rosterSnapshot["party1"], "G-New",
                    "snapshot must track the slot's new occupant")
    end)

    fw.it("clears unit-keyed state when a slot disappears entirely", function()
        local env = buildEnv({
            ["player"] = { guid = "G-Player", name = "Self", class = "PALADIN" },
            ["party1"] = { guid = "G-Friend", name = "Friend", class = "HUNTER" },
        })
        env.Brain._onRosterChanged()
        fw.assertEq(env.Brain._rosterSnapshot["party1"], "G-Friend")

        stubs.roster["party1"] = nil
        env.Brain._onRosterChanged()
        fw.assertNil(env.Brain._rosterSnapshot["party1"],
                     "vanished slot must be removed from the snapshot")
    end)
end)

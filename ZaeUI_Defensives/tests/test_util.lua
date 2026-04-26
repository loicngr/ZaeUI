local fw = require("framework")
local stubs = require("wow_stubs")

-- Util utilise le pattern `local _, ns = ...`. En Lua 5.1, un chunk chargé
-- par loadfile() reçoit les arguments passés à son appel comme varargs.
-- On lui passe donc un ns frais et on lit ns.Utils.Util après exécution.
local function loadUtil()
    local ns = { Utils = {} }
    local f = assert(loadfile("ZaeUI_Defensives/Utils/Util.lua"))
    f("ZaeUI_Defensives", ns)
    return ns.Utils.Util
end

fw.describe("Util.IsSecret", function()
    stubs.reset()
    local Util = loadUtil()
    fw.it("false for nil", function()
        fw.assertEq(Util.IsSecret(nil), false)
    end)
    fw.it("false for plain value", function()
        fw.assertEq(Util.IsSecret("hello"), false)
    end)
    fw.it("true when secret", function()
        local v = "tainted"
        stubs.secretValues[v] = true
        fw.assertEq(Util.IsSecret(v), true)
    end)
end)

fw.describe("Util.SafeAuraField", function()
    stubs.reset()
    local Util = loadUtil()
    fw.it("returns field when not secret", function()
        local aura = { spellId = 642 }
        fw.assertEq(Util.SafeAuraField(aura, "spellId"), 642)
    end)
    fw.it("returns nil when aura is nil", function()
        fw.assertNil(Util.SafeAuraField(nil, "spellId"))
    end)
    fw.it("returns nil when field is secret", function()
        local aura = { spellId = "tainted" }
        stubs.secretValues[aura.spellId] = true
        fw.assertNil(Util.SafeAuraField(aura, "spellId"))
    end)
end)

fw.describe("Util.SafeGUID", function()
    stubs.reset()
    stubs.roster["player"] = { guid = "Player-1-ABC" }
    local Util = loadUtil()
    fw.it("returns guid for valid unit", function()
        fw.assertEq(Util.SafeGUID("player"), "Player-1-ABC")
    end)
    fw.it("nil for unknown unit", function()
        fw.assertNil(Util.SafeGUID("party99"))
    end)
    fw.it("nil when guid is secret", function()
        stubs.secretValues["Player-1-ABC"] = true
        fw.assertNil(Util.SafeGUID("player"))
    end)
end)

fw.describe("Util.SafeNameUnmodified", function()
    stubs.reset()
    stubs.roster["player"] = { name = "Arthas" }
    local Util = loadUtil()
    fw.it("returns unmodified name", function()
        fw.assertEq(Util.SafeNameUnmodified("player"), "Arthas")
    end)
    fw.it("nil when unit missing", function()
        fw.assertNil(Util.SafeNameUnmodified("party99"))
    end)
end)

fw.describe("Util.GetSpellIcon", function()
    stubs.reset()
    stubs.spells = { [642] = { icon = 135892 } }
    local Util = loadUtil()
    fw.it("prefers originalIconID", function()
        fw.assertEq(Util.GetSpellIcon(642), 135892)
    end)
    fw.it("returns nil for unknown spell", function()
        fw.assertNil(Util.GetSpellIcon(999999))
    end)
end)

fw.describe("Util.SafeCall", function()
    local Util = loadUtil()
    fw.it("runs successful function and returns true", function()
        local called = false
        local ok = Util.SafeCall(function(a, b) called = (a + b == 3) end, 1, 2)
        fw.assertTrue(ok)
        fw.assertTrue(called)
    end)
    fw.it("swallows errors and returns false", function()
        local ok = Util.SafeCall(function() error("boom") end)
        fw.assertEq(ok, false)
    end)
end)

fw.describe("Util.ShouldDisplayCooldown — role filters", function()
    stubs.reset()
    stubs.roster["player"] = { name = "Self" }
    local Util = loadUtil()
    local cd = {}
    local info = { category = "Personal" }

    fw.it("hides TANK cooldowns when toggle is false", function()
        local rec = { role = "TANK", name = "Tonk" }
        local db = { trackerShowTankCooldowns = false }
        fw.assertEq(Util.ShouldDisplayCooldown(cd, info, rec, db), false)
    end)

    fw.it("hides HEALER cooldowns when toggle is false", function()
        local rec = { role = "HEALER", name = "Healz" }
        local db = { trackerShowHealerCooldowns = false }
        fw.assertEq(Util.ShouldDisplayCooldown(cd, info, rec, db), false)
    end)

    fw.it("hides DAMAGER cooldowns when toggle is false", function()
        local rec = { role = "DAMAGER", name = "Dps" }
        local db = { trackerShowDpsCooldowns = false }
        fw.assertEq(Util.ShouldDisplayCooldown(cd, info, rec, db), false)
    end)

    fw.it("shows by default when toggles are absent", function()
        local rec = { role = "TANK", name = "Tonk" }
        fw.assertTrue(Util.ShouldDisplayCooldown(cd, info, rec, {}))
    end)
end)

fw.describe("Util.ShouldDisplayCooldown — category filters", function()
    stubs.reset()
    stubs.roster["player"] = { name = "Self" }
    local Util = loadUtil()
    local cd = {}
    local rec = { role = "DAMAGER", name = "Dps" }

    fw.it("hides External when trackerShowExternal=false", function()
        local db = { trackerShowExternal = false }
        fw.assertEq(Util.ShouldDisplayCooldown(cd, { category = "External" }, rec, db), false)
    end)
    fw.it("hides Personal when trackerShowPersonal=false", function()
        local db = { trackerShowPersonal = false }
        fw.assertEq(Util.ShouldDisplayCooldown(cd, { category = "Personal" }, rec, db), false)
    end)
    fw.it("hides Raidwide when trackerShowRaidwide=false", function()
        local db = { trackerShowRaidwide = false }
        fw.assertEq(Util.ShouldDisplayCooldown(cd, { category = "Raidwide" }, rec, db), false)
    end)
end)

fw.describe("Util.ShouldDisplayCooldown — hide own externals", function()
    stubs.reset()
    stubs.roster["player"] = { name = "Self" }
    local Util = loadUtil()
    local cd = {}

    fw.it("hides Externals cast on the local player when toggle is on", function()
        local rec = { role = "DAMAGER", name = "Self" }
        local db = { trackerHideOwnExternals = true }
        fw.assertEq(
            Util.ShouldDisplayCooldown(cd, { category = "External" }, rec, db),
            false
        )
    end)

    fw.it("does not hide Externals on someone else", function()
        local rec = { role = "DAMAGER", name = "Other" }
        local db = { trackerHideOwnExternals = true }
        fw.assertTrue(
            Util.ShouldDisplayCooldown(cd, { category = "External" }, rec, db)
        )
    end)

    fw.it("does not hide Personal cooldowns under the same toggle", function()
        local rec = { role = "DAMAGER", name = "Self" }
        local db = { trackerHideOwnExternals = true }
        fw.assertTrue(
            Util.ShouldDisplayCooldown(cd, { category = "Personal" }, rec, db)
        )
    end)
end)

fw.describe("Util.ShouldDisplayCooldown — defensive guards", function()
    local Util = loadUtil()
    fw.it("returns false when db is nil", function()
        fw.assertEq(Util.ShouldDisplayCooldown({}, { category = "Personal" },
                                               { role = "TANK" }, nil), false)
    end)
    fw.it("returns false when info is nil", function()
        fw.assertEq(Util.ShouldDisplayCooldown({}, nil, { role = "TANK" }, {}), false)
    end)
    fw.it("returns false when rec is nil", function()
        fw.assertEq(Util.ShouldDisplayCooldown({}, { category = "Personal" }, nil, {}),
                    false)
    end)
end)

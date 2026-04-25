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

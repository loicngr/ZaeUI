local fw = require("framework")
local stubs = require("wow_stubs")

-- Inspector touches a lot of WoW APIs; we stub only what is required to
-- successfully load the module and exercise the public surface used by
-- the regression test below.
local function loadInspector()
    _G.LibStub = function() return nil end
    _G.hooksecurefunc = function() end
    _G.CreateFrame = function()
        return { SetScript = function() end, RegisterEvent = function() end }
    end
    _G.UnitExists = function() return true end
    _G.CanInspect = function() return true end
    _G.UnitIsConnected = function() return true end
    _G.UnitIsFriend = function() return true end
    _G.NotifyInspect = function() end
    _G.ClearInspectPlayer = function() end
    _G.GetInspectSpecialization = function() return 0 end
    _G.InCombatLockdown = function() return false end
    _G.GetNumGroupMembers = function() return 0 end
    _G.IsInRaid = function() return false end
    _G.C_TooltipInfo = nil
    _G.C_ClassTalents = nil
    _G.C_Traits = nil
    _G.Constants = nil

    local ns = { Core = {}, Utils = {} }
    local futil = assert(loadfile("ZaeUI_Defensives/Utils/Util.lua"))
    futil("ZaeUI_Defensives", ns)
    local f = assert(loadfile("ZaeUI_Defensives/Core/Inspector.lua"))
    f("ZaeUI_Defensives", ns)
    return ns.Core.Inspector, ns
end

fw.describe("Inspector — RebuildPlayerTalents notifies listeners for player", function()
    -- Bug fix: TRAIT_CONFIG_UPDATED used to invalidate the TalentResolver
    -- cache only. Brain's seedForUnit was never re-triggered, so on a respec
    -- without spec change the player's seed kept the stale requiresTalent /
    -- excludeIfTalent gates and the wrong chargeModifiers-derived maxCharges.
    -- The fix routes the event through Inspector:RebuildPlayerTalents which
    -- ends with fireSpecChanged("player") so Brain re-seeds.
    stubs.reset()
    stubs.roster["player"] = { guid = "G-Player", name = "Self", class = "PRIEST" }

    local Inspector = loadInspector()
    local fired = {}
    Inspector:RegisterCallback(function(unit) fired[#fired + 1] = unit end)

    Inspector:RebuildPlayerTalents()

    fw.it("fires spec-change callback exactly once for player", function()
        fw.assertEq(#fired, 1)
        fw.assertEq(fired[1], "player")
    end)
end)

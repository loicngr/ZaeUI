local fw = require("framework")
require("wow_stubs")

local function loadMigration()
    local ns = {}
    ns.Config = {}
    local f = assert(loadfile("ZaeUI_Defensives/Config/Migration.lua"))
    f("ZaeUI_Defensives", ns)
    return ns.Config.Migration, ns
end

fw.describe("Migration — fresh install", function()
    local Migration = loadMigration()
    local db = {}
    Migration.Migrate(db)
    fw.it("sets schemaVersion to 3", function() fw.assertEq(db.schemaVersion, 3) end)
    fw.it("defaults role filters to true", function()
        fw.assertEq(db.trackerShowTankCooldowns, true)
        fw.assertEq(db.trackerShowHealerCooldowns, true)
        fw.assertEq(db.trackerShowDpsCooldowns, true)
    end)
    fw.it("drops legacy trackerForceAnchoredInRaid key (raid always floats)", function()
        fw.assertNil(db.trackerForceAnchoredInRaid)
    end)
    fw.it("defaults enabledInRaid to true", function()
        fw.assertEq(db.enabledInRaid, true)
    end)
    fw.it("defaults enabledInMythicPlus to true", function()
        fw.assertEq(db.enabledInMythicPlus, true)
    end)
    fw.it("defaults debug to false", function()
        fw.assertEq(db.debug, false)
    end)
end)

fw.describe("Migration — from v2 classic style", function()
    local Migration = loadMigration()
    local db = {
        displayStyle = "classic",
        trackerEnabled = true,
        trackerOpacity = 80,
        framePoint = { "CENTER", nil, "CENTER", 0, 0 },
    }
    Migration.Migrate(db)
    fw.it("drops displayStyle", function() fw.assertNil(db.displayStyle) end)
    fw.it("marks classic notice as unseen", function()
        fw.assertEq(db.classicStyleNoticeShown, false)
    end)
    fw.it("preserves unchanged keys", function()
        fw.assertEq(db.trackerEnabled, true)
        fw.assertEq(db.trackerOpacity, 80)
        fw.assertEq(db.framePoint[1], "CENTER")
    end)
    fw.it("sets schemaVersion to 3", function() fw.assertEq(db.schemaVersion, 3) end)
end)

fw.describe("Migration — from v2 modern style", function()
    local Migration = loadMigration()
    local db = { displayStyle = "modern" }
    Migration.Migrate(db)
    fw.it("drops displayStyle", function() fw.assertNil(db.displayStyle) end)
    fw.it("does NOT trigger classic notice for modern users", function()
        fw.assertNil(db.classicStyleNoticeShown)
    end)
end)

fw.describe("Migration — idempotent on v3", function()
    local Migration = loadMigration()
    local db = {
        schemaVersion = 3,
        trackerShowTankCooldowns = false,
        debug = true,
    }
    Migration.Migrate(db)
    fw.it("preserves v3 explicit false", function()
        fw.assertEq(db.trackerShowTankCooldowns, false)
    end)
    fw.it("preserves v3 explicit true", function()
        fw.assertEq(db.debug, true)
    end)
    fw.it("still v3", function() fw.assertEq(db.schemaVersion, 3) end)
end)

fw.describe("Migration — partial v2 db", function()
    local Migration = loadMigration()
    local db = { trackerEnabled = false }
    Migration.Migrate(db)
    fw.it("preserves partial key", function() fw.assertEq(db.trackerEnabled, false) end)
    fw.it("upgrades to v3", function() fw.assertEq(db.schemaVersion, 3) end)
end)

fw.describe("Migration — v2 without displayStyle (historic user)", function()
    local Migration = loadMigration()
    local db = { trackerEnabled = true, trackerOpacity = 75 }
    Migration.Migrate(db)
    fw.it("does not set classicStyleNoticeShown", function()
        fw.assertNil(db.classicStyleNoticeShown)
    end)
    fw.it("applies role defaults", function()
        fw.assertEq(db.trackerShowTankCooldowns, true)
    end)
    fw.it("upgrades to v3", function() fw.assertEq(db.schemaVersion, 3) end)
end)

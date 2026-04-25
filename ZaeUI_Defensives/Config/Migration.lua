-- ZaeUI_Defensives/Config/Migration.lua
-- Soft migration of ZaeUI_DefensivesDB from v2 to v3.
-- Idempotent: safe to call on any db including already-v3.

local _, ns = ...
ns.Config = ns.Config or {}

local Migration = {}

--- Migrate a Defensives DB to schema v3.
--- Cosmetic keys are preserved; dead keys are dropped; new keys get defaults.
--- @param db table The ZaeUI_DefensivesDB table (mutated in-place).
function Migration.Migrate(db)
    if not db then return end

    if db.schemaVersion == nil or db.schemaVersion < 3 then
        -- Drop the classic style, keep users on the unified modern visual
        if db.displayStyle == "classic" then
            db.displayStyle = nil
            db.classicStyleNoticeShown = false
        elseif db.displayStyle == "modern" then
            -- Modern was the default and is now implicit — drop the key
            db.displayStyle = nil
        end

        -- New role filters, default true (show everyone)
        if db.trackerShowTankCooldowns == nil then
            db.trackerShowTankCooldowns = true
        end
        if db.trackerShowHealerCooldowns == nil then
            db.trackerShowHealerCooldowns = true
        end
        if db.trackerShowDpsCooldowns == nil then
            db.trackerShowDpsCooldowns = true
        end

        -- v3.0.0: raid (>5 players) always uses the floating view.
        -- Drop any legacy override key so the behaviour is consistent.
        db.trackerForceAnchoredInRaid = nil

        -- Context opt-outs (enable/disable addon in raid / M+). Default true.
        if db.enabledInRaid == nil then
            db.enabledInRaid = true
        end
        if db.enabledInMythicPlus == nil then
            db.enabledInMythicPlus = true
        end

        -- Debug flag, default false
        if db.debug == nil then
            db.debug = false
        end

        -- One-shot notice flag for when a custom unit-frame framework is
        -- detected and the anchored mode falls back to floating.
        if db.frameDisplayCustomWarningShown == nil then
            db.frameDisplayCustomWarningShown = false
        end

        -- framePoint[2] was sometimes stored as the string "UIParent" by v2.
        -- The v3 displays pass db.framePoint[2] directly to SetPoint as the
        -- relativeTo argument — a string there throws "attempt to index a
        -- string value". Normalize to nil so SetPoint defaults to UIParent.
        if type(db.framePoint) == "table" and type(db.framePoint[2]) == "string" then
            db.framePoint[2] = nil
        end

        db.schemaVersion = 3
    end
end

ns.Config.Migration = Migration
return Migration

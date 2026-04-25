-- ZaeUI_Defensives v3 — entry point.
-- Detection-based tracker for allied defensive cooldowns. Works in every
-- context including active Mythic+ keystones, raid encounters and arenas,
-- by observing aura events locally instead of relying on addon-to-addon
-- communication.
-- luacheck: no self

local _, ns = ...

local ADDON_NAME = "ZaeUI_Defensives"
local PREFIX     = "|cff3bb5ff[ZaeUI_Defensives]|r "

-- ------------------------------------------------------------------
-- Database defaults and init (migration runs after)
-- ------------------------------------------------------------------

local DEFAULTS = {
    trackerEnabled = true,
    trackerOpacity = 80,
    trackerLocked  = false,
    trackerShowExternal = true,
    trackerShowPersonal = true,
    trackerShowRaidwide = true,
    trackerHideOwnExternals = false,
    trackerHideWhenSolo = true,
    collapsed = false,
    framePoint = { "CENTER", nil, "CENTER", 0, 0 },
    displayMode = "floating",
    frameWidth = 250,
    frameHeight = 0,
    anchoredIconSize = 28,
    anchoredSpacing = 3,
    anchoredIconsPerRow = 2,
    anchoredSide = "RIGHT",
    anchoredOffsetX = 2,
    anchoredOffsetY = 30,
    anchoredShowPlayer = false,
    showLoadMessage = true,
    -- v3 keys (kept in sync with Config/Migration.lua so a fresh install
    -- and a v2→v3 migration converge to the same state).
    trackerShowTankCooldowns = true,
    trackerShowHealerCooldowns = true,
    trackerShowDpsCooldowns = true,
    -- Context toggles: disable the addon altogether in raids or active
    -- Mythic+ keystones. Defaults to enabled in both contexts.
    enabledInRaid = true,
    enabledInMythicPlus = true,
    debug = false,
    frameDisplayCustomWarningShown = false,
    schemaVersion = 3,
}

local function initDB()
    if not ZaeUI_DefensivesDB then
        ZaeUI_DefensivesDB = {}
    end
    for key, value in pairs(DEFAULTS) do
        if ZaeUI_DefensivesDB[key] == nil then
            if type(value) == "table" then
                local copy = {}
                for k, v in pairs(value) do copy[k] = v end
                ZaeUI_DefensivesDB[key] = copy
            else
                ZaeUI_DefensivesDB[key] = value
            end
        end
    end
    ns.db = ZaeUI_DefensivesDB
end

-- ------------------------------------------------------------------
-- v3 helpers exposed globally via ns (used by Options and slash commands)
-- ------------------------------------------------------------------

--- Returns true when the addon should be visibly active in the current
--- instance context. Users can opt-out of raid and/or Mythic+ via the
--- Options panel. Defaults: enabled everywhere.
--- @return boolean
function ns.isEnabledInCurrentContext()
    local db = ZaeUI_DefensivesDB
    if not db then return true end
    if IsInRaid and IsInRaid() and db.enabledInRaid == false then
        return false
    end
    if db.enabledInMythicPlus == false
       and C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
       and C_ChallengeMode.IsChallengeModeActive() then
        return false
    end
    return true
end

--- Resets all Defensives settings. Stops TestMode, clears runtime caches,
--- wipes the DB, reloads the UI.
function ns.ResetAll()
    if ns.Modules and ns.Modules.TestMode and ns.Modules.TestMode.IsActive
       and ns.Modules.TestMode:IsActive() then
        ns.Modules.TestMode:Stop()
    end
    if ns.Core and ns.Core.CooldownStore and ns.Core.CooldownStore.Reset then
        ns.Core.CooldownStore:Reset()
    end
    if ns.Core and ns.Core.Inspector and ns.Core.Inspector.ClearCache then
        ns.Core.Inspector:ClearCache()
    end
    ZaeUI_DefensivesDB = nil
    if ReloadUI then ReloadUI() end
end

--- Routes refresh to the floating display (which coordinates with the frame
--- display via ApplyMode internally).
function ns.routeRefreshDisplay()
    if ns.Modules and ns.Modules.FloatingDisplay and ns.Modules.FloatingDisplay.ApplyMode then
        ns.Modules.FloatingDisplay:ApplyMode()
    elseif ns.Modules and ns.Modules.FrameDisplay and ns.Modules.FrameDisplay.ApplyMode then
        ns.Modules.FrameDisplay:ApplyMode()
    end
end

-- ------------------------------------------------------------------
-- Event frame + handlers
-- ------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")

local events = {}

function events.ADDON_LOADED(_, addonName)
    if addonName ~= ADDON_NAME then return end
    if not ZaeUI_Shared then
        local msg = "ZaeUI_Shared is required. Install it from CurseForge."
        print(PREFIX .. "Error: " .. msg .. " Addon disabled.")
        C_Timer.After(5, function()
            if UIErrorsFrame then
                UIErrorsFrame:AddMessage("|cffff0000[" .. ADDON_NAME .. "]|r " .. msg,
                                          1, 0.2, 0.2, 1, 5)
            end
        end)
        return
    end

    initDB()

    -- v3 pipeline bootstrap (ordre critique)
    if ns.Config and ns.Config.Migration and ns.Config.Migration.Migrate then
        ns.Config.Migration.Migrate(ZaeUI_DefensivesDB)
    end
    if ns.Core then
        if ns.Core.Inspector and ns.Core.Inspector.Init then
            ns.Core.Inspector:Init()
        end
        if ns.Core.AuraWatcher and ns.Core.AuraWatcher.Init then
            ns.Core.AuraWatcher:Init()
        end
        if ns.Core.Brain and ns.Core.Brain.Init then
            ns.Core.Brain:Init()
        end
    end
    if ns.Modules then
        if ns.Modules.FloatingDisplay and ns.Modules.FloatingDisplay.Init then
            ns.Modules.FloatingDisplay:Init()
        end
        if ns.Modules.FrameDisplay and ns.Modules.FrameDisplay.Init then
            ns.Modules.FrameDisplay:Init()
        end
        if ns.Modules.TestMode and ns.Modules.TestMode.Init then
            ns.Modules.TestMode:Init()
        end
    end
    if ns.Config and ns.Config.Options and ns.Config.Options.Init then
        ns.Config.Options:Init()
    end

    frame:UnregisterEvent("ADDON_LOADED")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:RegisterEvent("GROUP_JOINED")
    frame:RegisterEvent("GROUP_LEFT")
    -- Re-evaluate visibility when the Mythic+ keystone starts / ends.
    frame:RegisterEvent("CHALLENGE_MODE_START")
    frame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    frame:RegisterEvent("CHALLENGE_MODE_RESET")

    -- One-shot migration notice for users who were on the retired classic style
    if ZaeUI_DefensivesDB.classicStyleNoticeShown == false then
        print(PREFIX .. "Classic style has been retired. You're now on the "
              .. "unified visual style — let me know if anything looks off.")
        ZaeUI_DefensivesDB.classicStyleNoticeShown = true
    end

    if ZaeUI_DefensivesDB.showLoadMessage then
        print(PREFIX .. "Loaded. Type /zdef help for commands.")
    end
end

function events.PLAYER_LOGIN()
    if ns.routeRefreshDisplay then ns.routeRefreshDisplay() end
    frame:UnregisterEvent("PLAYER_LOGIN")
end

function events.GROUP_JOINED()
    if ns.routeRefreshDisplay then ns.routeRefreshDisplay() end
end

function events.GROUP_LEFT()
    if ns.routeRefreshDisplay then ns.routeRefreshDisplay() end
end

-- Context transitions that may affect isEnabledInCurrentContext()
function events.CHALLENGE_MODE_START()
    if ns.routeRefreshDisplay then ns.routeRefreshDisplay() end
end
function events.CHALLENGE_MODE_COMPLETED()
    if ns.routeRefreshDisplay then ns.routeRefreshDisplay() end
end
function events.CHALLENGE_MODE_RESET()
    if ns.routeRefreshDisplay then ns.routeRefreshDisplay() end
end

frame:SetScript("OnEvent", function(_, event, ...)
    if events[event] then events[event](frame, ...) end
end)

-- ------------------------------------------------------------------
-- Slash command
-- ------------------------------------------------------------------

SLASH_ZAEUIDEFENSIVES1 = "/zdef"

SlashCmdList["ZAEUIDEFENSIVES"] = function(msg)
    msg = strtrim and strtrim(msg) or msg

    if msg == "" or msg == "options" then
        if ns.settingsCategory and Settings and Settings.OpenToCategory then
            Settings.OpenToCategory(ns.settingsCategory.ID)
        else
            print(PREFIX .. "Options panel not yet loaded.")
        end
        return
    end

    if msg == "tracker" then
        ZaeUI_DefensivesDB.trackerEnabled = not ZaeUI_DefensivesDB.trackerEnabled
        print(PREFIX .. "Tracker " .. (ZaeUI_DefensivesDB.trackerEnabled and "enabled" or "disabled") .. ".")
        if ns.routeRefreshDisplay then ns.routeRefreshDisplay() end
        if ns.refreshWidgets then ns.refreshWidgets() end
        return
    end

    if msg == "reset" then
        if ns.ResetAll then ns.ResetAll() end
        return
    end

    if msg == "test" then
        if ns.Modules and ns.Modules.TestMode then
            ns.Modules.TestMode:Start(false, false)
            print(PREFIX .. "Test mode started (party).")
        end
        return
    end
    if msg == "test raid" then
        if ns.Modules and ns.Modules.TestMode then
            ns.Modules.TestMode:StartRaid(false)
            print(PREFIX .. "Test mode started (raid).")
        end
        return
    end
    if msg == "test force" then
        if ns.Modules and ns.Modules.TestMode then
            ns.Modules.TestMode:Start(false, true)
            print(PREFIX .. "Test mode started (party, force — won't stop in combat).")
        end
        return
    end
    if msg == "test stop" then
        if ns.Modules and ns.Modules.TestMode then
            ns.Modules.TestMode:Stop()
            print(PREFIX .. "Test mode stopped.")
        end
        return
    end

    if msg == "debug" then
        ZaeUI_DefensivesDB.debug = not ZaeUI_DefensivesDB.debug
        print(PREFIX .. "Debug " .. (ZaeUI_DefensivesDB.debug and "enabled" or "disabled") .. ".")
        return
    end

    if msg == "help" then
        print(PREFIX .. "Usage:")
        print(PREFIX .. "  /zdef - Open the options panel")
        print(PREFIX .. "  /zdef tracker - Toggle the tracker display")
        print(PREFIX .. "  /zdef reset - Reset all settings to defaults")
        print(PREFIX .. "  /zdef test - Launch party test mode")
        print(PREFIX .. "  /zdef test raid - Launch raid test mode")
        print(PREFIX .. "  /zdef test force - Party test that keeps running in combat")
        print(PREFIX .. "  /zdef test stop - Stop test mode")
        print(PREFIX .. "  /zdef debug - Toggle debug prints")
        return
    end

    print(PREFIX .. "Unknown command. Type /zdef help for usage.")
end

-- Expose constants for external tools
ns.ADDON_NAME = ADDON_NAME
ns.PREFIX = PREFIX
ns.constants = { DEFAULTS = DEFAULTS }

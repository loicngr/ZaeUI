-- NameplateScale: Scale up the nameplate of your current target
-- Uses the native CVar nameplateSelectedScale

-- Local references to WoW APIs
local CreateFrame = CreateFrame
local GetCVar = GetCVar
local SetCVar = SetCVar

-- Constants
local ADDON_NAME = "NameplateScale"
local DEFAULT_SCALE = 1.2
local MIN_SCALE = 0.5
local MAX_SCALE = 3.0

-- Main frame and event handling
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")

frame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == ADDON_NAME then
        if not NameplateScaleDB then
            NameplateScaleDB = { scale = DEFAULT_SCALE }
        end

        SetCVar("nameplateSelectedScale", NameplateScaleDB.scale)

        self:UnregisterEvent("ADDON_LOADED")

        print("|cff00ccff[NameplateScale]|r Loaded. Target nameplate scale: " .. NameplateScaleDB.scale)
    end
end)

-- Slash command handler
SLASH_NAMEPLATESSCALE1 = "/nps"

SlashCmdList["NAMEPLATESSCALE"] = function(msg)
    msg = strtrim(msg)

    if msg == "" then
        local current = GetCVar("nameplateSelectedScale")
        print("|cff00ccff[NameplateScale]|r Current scale: " .. current)
        return
    end

    if msg == "reset" then
        NameplateScaleDB.scale = DEFAULT_SCALE
        SetCVar("nameplateSelectedScale", DEFAULT_SCALE)
        print("|cff00ccff[NameplateScale]|r Scale reset to default: " .. DEFAULT_SCALE)
        return
    end

    local value = tonumber(msg)
    if not value then
        print("|cff00ccff[NameplateScale]|r Usage: /nps <number> | /nps reset")
        return
    end

    if value < MIN_SCALE or value > MAX_SCALE then
        print("|cff00ccff[NameplateScale]|r Scale must be between " .. MIN_SCALE .. " and " .. MAX_SCALE)
        return
    end

    NameplateScaleDB.scale = value
    SetCVar("nameplateSelectedScale", value)
    print("|cff00ccff[NameplateScale]|r Target nameplate scale set to: " .. value)
end

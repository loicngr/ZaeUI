-- ZaeUI_NameplateScale: Scale up the nameplate of your current target
-- Uses the native CVars nameplateSelectedScale and nameplateOverlapV

-- Local references to WoW APIs
local CreateFrame = CreateFrame
local GetCVar = GetCVar
local SetCVar = SetCVar
local strtrim = strtrim
local tonumber = tonumber

-- Constants
local ADDON_NAME = "ZaeUI_NameplateScale"
local DEFAULT_SCALE = 1.2
local MIN_SCALE = 0.5
local MAX_SCALE = 3.0
local MIN_OVERLAP = 0.5
local MAX_OVERLAP = 5.0
local PREFIX = "|cff00ccff[ZaeUI_NameplateScale]|r "

-- Local state: original overlap captured at load time
local originalOverlapV

--- Apply the overlap value (auto-proportional or manual override).
--- @param scale number The current nameplate scale
local function applyOverlap(scale)
    local db = ZaeUI_NameplateScaleDB
    if db.overlapV then
        SetCVar("nameplateOverlapV", db.overlapV)
    else
        SetCVar("nameplateOverlapV", originalOverlapV * scale)
    end
end

--- Apply scale and recalculate overlap.
--- @param scale number The scale factor to apply
local function applyScale(scale)
    SetCVar("nameplateSelectedScale", scale)
    applyOverlap(scale)
end

-- Main frame and event handling
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")

frame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == ADDON_NAME then
        if not ZaeUI_NameplateScaleDB then
            -- First install: capture Blizzard's default overlap value
            ZaeUI_NameplateScaleDB = {
                scale = DEFAULT_SCALE,
                overlapV = nil, -- nil = auto mode, number = manual override
                baseOverlapV = tonumber(GetCVar("nameplateOverlapV")) or 1.1,
            }
        end

        originalOverlapV = ZaeUI_NameplateScaleDB.baseOverlapV

        applyScale(ZaeUI_NameplateScaleDB.scale)

        self:UnregisterEvent("ADDON_LOADED")

        print(PREFIX .. "Loaded. Target nameplate scale: " .. ZaeUI_NameplateScaleDB.scale)
        print(PREFIX .. "Made by loicngr")
        print(PREFIX .. "Type /znps help for commands.")
    end
end)

-- Slash command handler
SLASH_ZAEUINAMEPLATESSCALE1 = "/znps"

SlashCmdList["ZAEUINAMEPLATESSCALE"] = function(msg)
    msg = strtrim(msg)

    if msg == "" then
        local currentScale = GetCVar("nameplateSelectedScale")
        local currentOverlap = GetCVar("nameplateOverlapV")
        local mode = ZaeUI_NameplateScaleDB.overlapV and "manual" or "auto"
        print(PREFIX .. "Scale: " .. currentScale .. " | Overlap: " .. currentOverlap .. " (" .. mode .. ")")
        return
    end

    if msg == "help" then
        print(PREFIX .. "Usage:")
        print(PREFIX .. "  /znps <number> - Set target nameplate scale (" .. MIN_SCALE .. "-" .. MAX_SCALE .. ")")
        print(PREFIX .. "  /znps reset - Reset scale and overlap to defaults")
        print(PREFIX .. "  /znps overlap <number> - Override overlap (" .. MIN_OVERLAP .. "-" .. MAX_OVERLAP .. ")")
        print(PREFIX .. "  /znps overlap auto - Reset overlap to automatic")
        return
    end

    if msg == "reset" then
        ZaeUI_NameplateScaleDB.scale = DEFAULT_SCALE
        ZaeUI_NameplateScaleDB.overlapV = nil
        applyScale(DEFAULT_SCALE)
        print(PREFIX .. "Scale and overlap reset to defaults.")
        return
    end

    -- Overlap subcommand
    if msg == "overlap auto" then
        ZaeUI_NameplateScaleDB.overlapV = nil
        applyOverlap(ZaeUI_NameplateScaleDB.scale)
        print(PREFIX .. "Overlap set to automatic.")
        return
    end

    local overlapArg = msg:match("^overlap%s+(.+)$")
    if overlapArg then
        local value = tonumber(overlapArg)
        if not value then
            print(PREFIX .. "Usage: /znps overlap <number> | /znps overlap auto")
            return
        end
        if value < MIN_OVERLAP or value > MAX_OVERLAP then
            print(PREFIX .. "Overlap must be between " .. MIN_OVERLAP .. " and " .. MAX_OVERLAP)
            return
        end
        ZaeUI_NameplateScaleDB.overlapV = value
        applyOverlap(ZaeUI_NameplateScaleDB.scale)
        print(PREFIX .. "Overlap manually set to: " .. value)
        return
    end

    -- Scale command
    local value = tonumber(msg)
    if not value then
        print(PREFIX .. "Usage: /znps <number> | /znps reset | /znps help")
        return
    end

    if value < MIN_SCALE or value > MAX_SCALE then
        print(PREFIX .. "Scale must be between " .. MIN_SCALE .. " and " .. MAX_SCALE)
        return
    end

    ZaeUI_NameplateScaleDB.scale = value
    applyScale(value)
    print(PREFIX .. "Target nameplate scale set to: " .. value)
end

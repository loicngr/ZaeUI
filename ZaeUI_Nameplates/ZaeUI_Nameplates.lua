-- ZaeUI_Nameplates: Enhance your target nameplate with scaling, overlap adjustment and highlight
-- Uses native CVars and nameplate frame manipulation

-- Local references to WoW APIs
local CreateFrame = CreateFrame
local GetCVar = GetCVar
local SetCVar = SetCVar
local C_NamePlate = C_NamePlate
local UnitIsUnit = UnitIsUnit
local strtrim = strtrim

-- Constants
local ADDON_NAME = "ZaeUI_Nameplates"
local DEFAULT_SCALE = 1.2
local MIN_SCALE = 0.5
local MAX_SCALE = 3.0
local MIN_OVERLAP = 0.5
local MAX_OVERLAP = 5.0
local DEFAULT_HIGHLIGHT = true
local PREFIX = "|cff00ccff[ZaeUI_Nameplates]|r "

-- Local state
local originalOverlapV
local db
local highlightFrame
local highlightTexture

-- Default settings
local DEFAULTS = {
    scale = DEFAULT_SCALE,
    overlapV = nil,
    baseOverlapV = nil,
    highlight = DEFAULT_HIGHLIGHT,
    highlightColor = { r = 0, g = 0.8, b = 1, a = 0.3 },
}

--- Migrate settings from the old ZaeUI_NameplateScaleDB if present.
local function migrateOldDB()
    if not ZaeUI_NameplateScaleDB then
        return
    end
    if not ZaeUI_NameplatesDB then
        ZaeUI_NameplatesDB = {}
    end
    ZaeUI_NameplatesDB.scale = ZaeUI_NameplateScaleDB.scale
    ZaeUI_NameplatesDB.overlapV = ZaeUI_NameplateScaleDB.overlapV
    ZaeUI_NameplatesDB.baseOverlapV = ZaeUI_NameplateScaleDB.baseOverlapV
    ZaeUI_NameplateScaleDB = nil
    print(PREFIX .. "Settings migrated from ZaeUI_NameplateScale.")
end

--- Initialize database with defaults for any missing keys.
local function initDB()
    if not ZaeUI_NameplatesDB then
        ZaeUI_NameplatesDB = {}
    end
    for key, value in pairs(DEFAULTS) do
        if ZaeUI_NameplatesDB[key] == nil then
            if type(value) == "table" then
                ZaeUI_NameplatesDB[key] = { r = value.r, g = value.g, b = value.b, a = value.a }
            else
                ZaeUI_NameplatesDB[key] = value
            end
        end
    end
    if not ZaeUI_NameplatesDB.baseOverlapV then
        ZaeUI_NameplatesDB.baseOverlapV = tonumber(GetCVar("nameplateOverlapV")) or 1.1
    end
    db = ZaeUI_NameplatesDB
end

--- Apply the overlap value (auto-proportional or manual override).
--- @param scale number The current nameplate scale
local function applyOverlap(scale)
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

-- Highlight

--- Show a colored background behind the target nameplate.
--- Uses a dedicated overlay frame to avoid issues with nameplate recycling.
local function showHighlight()
    if not db.highlight then
        return
    end
    local namePlate = C_NamePlate.GetNamePlateForUnit("target")
    if not namePlate then
        return
    end
    if not highlightFrame then
        highlightFrame = CreateFrame("Frame")
        highlightTexture = highlightFrame:CreateTexture(nil, "BACKGROUND")
    end
    highlightFrame:SetParent(namePlate)
    highlightFrame:SetAllPoints(namePlate)
    highlightFrame:SetFrameStrata("BACKGROUND")
    local c = db.highlightColor
    highlightTexture:SetColorTexture(c.r, c.g, c.b, c.a)
    highlightTexture:SetAllPoints(highlightFrame)
    highlightFrame:Show()
    highlightTexture:Show()
end

--- Hide the highlight overlay.
local function hideHighlight()
    if highlightFrame then
        highlightFrame:Hide()
    end
end

-- Main frame and event handling
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")

local events = {}

function events:ADDON_LOADED(addonName)
    if addonName ~= ADDON_NAME then
        return
    end
    migrateOldDB()
    initDB()

    originalOverlapV = db.baseOverlapV
    applyScale(db.scale)

    frame:UnregisterEvent("ADDON_LOADED")
    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")

    print(PREFIX .. "Loaded. Scale: " .. db.scale .. " | Highlight: " .. (db.highlight and "on" or "off"))
    print(PREFIX .. "Made by loicngr")
    print(PREFIX .. "Type /znp help for commands.")
end

function events:PLAYER_TARGET_CHANGED()
    hideHighlight()
    showHighlight()
end

function events:NAME_PLATE_UNIT_ADDED(unit)
    if UnitIsUnit(unit, "target") then
        hideHighlight()
        showHighlight()
    end
end

function events:NAME_PLATE_UNIT_REMOVED(unit)
    if UnitIsUnit(unit, "target") then
        hideHighlight()
    end
end

frame:SetScript("OnEvent", function(self, event, ...)
    if events[event] then
        events[event](self, ...)
    end
end)

-- Slash command handler
SLASH_ZAEUINAMEPLATES1 = "/znp"

SlashCmdList["ZAEUINAMEPLATES"] = function(msg)
    msg = strtrim(msg)

    if msg == "" then
        local currentScale = GetCVar("nameplateSelectedScale")
        local currentOverlap = GetCVar("nameplateOverlapV")
        local overlapMode = db.overlapV and "manual" or "auto"
        local highlightStatus = db.highlight and "on" or "off"
        print(PREFIX .. "Scale: " .. currentScale .. " | Overlap: " .. currentOverlap .. " (" .. overlapMode .. ") | Highlight: " .. highlightStatus)
        return
    end

    if msg == "help" then
        print(PREFIX .. "Usage:")
        print(PREFIX .. "  /znp <number> - Set target nameplate scale (" .. MIN_SCALE .. "-" .. MAX_SCALE .. ")")
        print(PREFIX .. "  /znp reset - Reset all settings to defaults")
        print(PREFIX .. "  /znp overlap <number> - Override overlap (" .. MIN_OVERLAP .. "-" .. MAX_OVERLAP .. ")")
        print(PREFIX .. "  /znp overlap auto - Reset overlap to automatic")
        print(PREFIX .. "  /znp highlight - Toggle highlight on/off")
        return
    end

    if msg == "reset" then
        db.scale = DEFAULT_SCALE
        db.overlapV = nil
        db.highlight = DEFAULT_HIGHLIGHT
        local dc = DEFAULTS.highlightColor
        db.highlightColor = { r = dc.r, g = dc.g, b = dc.b, a = dc.a }
        applyScale(DEFAULT_SCALE)
        hideHighlight()
        showHighlight()
        print(PREFIX .. "All settings reset to defaults.")
        return
    end

    -- Overlap subcommand
    if msg == "overlap auto" then
        db.overlapV = nil
        applyOverlap(db.scale)
        print(PREFIX .. "Overlap set to automatic.")
        return
    end

    local overlapArg = msg:match("^overlap%s+(.+)$")
    if overlapArg then
        local value = tonumber(overlapArg)
        if not value then
            print(PREFIX .. "Usage: /znp overlap <number> | /znp overlap auto")
            return
        end
        if value < MIN_OVERLAP or value > MAX_OVERLAP then
            print(PREFIX .. "Overlap must be between " .. MIN_OVERLAP .. " and " .. MAX_OVERLAP)
            return
        end
        db.overlapV = value
        applyOverlap(db.scale)
        print(PREFIX .. "Overlap manually set to: " .. value)
        return
    end

    -- Highlight subcommand
    if msg == "highlight" then
        db.highlight = not db.highlight
        if db.highlight then
            showHighlight()
            print(PREFIX .. "Highlight enabled.")
        else
            hideHighlight()
            print(PREFIX .. "Highlight disabled.")
        end
        return
    end

    -- Scale command
    local value = tonumber(msg)
    if not value then
        print(PREFIX .. "Usage: /znp <number> | /znp reset | /znp help")
        return
    end

    if value < MIN_SCALE or value > MAX_SCALE then
        print(PREFIX .. "Scale must be between " .. MIN_SCALE .. " and " .. MAX_SCALE)
        return
    end

    db.scale = value
    applyScale(value)
    print(PREFIX .. "Target nameplate scale set to: " .. value)
end

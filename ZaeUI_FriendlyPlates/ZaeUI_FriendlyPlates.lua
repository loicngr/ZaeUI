-- ZaeUI_FriendlyPlates: Friendly nameplates with name-only mode, class colors and custom font size
-- Uses native CVars and global font objects

local _, ns = ...

-- Local references to WoW APIs
local CreateFrame = CreateFrame
local GetCVar = GetCVar
local SetCVar = SetCVar
local InCombatLockdown = InCombatLockdown
local wipe = wipe
local C_NamePlate = C_NamePlate
local C_Timer = C_Timer
local hooksecurefunc = hooksecurefunc
local UnitIsFriend = UnitIsFriend
local strtrim = strtrim
local math_floor = math.floor

-- Constants
local ADDON_NAME = "ZaeUI_FriendlyPlates"
local PREFIX = "|cff00ccff[ZaeUI_FriendlyPlates]|r "
local DEFAULT_ENABLED = false
local DEFAULT_SHOW_ONLY_NAME = true
local DEFAULT_CLASS_COLOR = true
local DEFAULT_CUSTOM_FONT = false
local DEFAULT_FONT_SIZE = 14
local MIN_FONT_SIZE = 8
local MAX_FONT_SIZE = 28

-- Original font values, captured in ADDON_LOADED before any modification
local defaultFont = {}
local defaultFont2 = {}

-- Local state
local db
local baseCVars

-- Default settings
local DEFAULTS = {
    enabled = DEFAULT_ENABLED,
    showOnlyName = DEFAULT_SHOW_ONLY_NAME,
    classColor = DEFAULT_CLASS_COLOR,
    customFont = DEFAULT_CUSTOM_FONT,
    fontSize = DEFAULT_FONT_SIZE,
}

-- Combat-safe CVar wrapper: queues SetCVar calls when in combat lockdown
local pendingCVars = {}
local combatFrame = CreateFrame("Frame")

local function safeCVar(cvar, value)
    if InCombatLockdown() then
        pendingCVars[cvar] = value
        combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        SetCVar(cvar, value)
    end
end

combatFrame:SetScript("OnEvent", function(self)
    for cvar, value in pairs(pendingCVars) do
        SetCVar(cvar, value)
    end
    wipe(pendingCVars)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
end)

--- Initialize database with defaults for any missing keys.
local function initDB()
    if not ZaeUI_FriendlyPlatesDB then
        ZaeUI_FriendlyPlatesDB = {}
    end
    for key, value in pairs(DEFAULTS) do
        if ZaeUI_FriendlyPlatesDB[key] == nil then
            ZaeUI_FriendlyPlatesDB[key] = value
        end
    end
    db = ZaeUI_FriendlyPlatesDB
    ns.db = db
end

--- Save the original CVar values for later restoration.
--- Persists in SavedVariables so originals survive across sessions even when
--- the addon has already modified CVars before logout.
local function saveCVars()
    if db.originalCVars then
        baseCVars = db.originalCVars
        return
    end
    baseCVars = {
        nameplateShowFriendlyPlayers = GetCVar("nameplateShowFriendlyPlayers"),
        nameplateShowOnlyNameForFriendlyPlayerUnits = GetCVar("nameplateShowOnlyNameForFriendlyPlayerUnits"),
        nameplateUseClassColorForFriendlyPlayerUnitNames = GetCVar("nameplateUseClassColorForFriendlyPlayerUnitNames"),
    }
    db.originalCVars = baseCVars
end

--- Restore the original CVar values.
local function restoreCVars()
    if not baseCVars then return end
    for cvar, value in pairs(baseCVars) do
        if value then
            safeCVar(cvar, value)
        end
    end
end

--- Force WoW to re-render all friendly player names.
local function reloadNameplates()
    local val = GetCVar("UnitNameFriendlyPlayerName")
    if val then safeCVar("UnitNameFriendlyPlayerName", val) end
end

--- Apply all CVar-based settings.
local function applyCVars()
    safeCVar("nameplateShowFriendlyPlayers", db.enabled and "1" or "0")
    if db.enabled then
        safeCVar("nameplateShowOnlyNameForFriendlyPlayerUnits", db.showOnlyName and "1" or "0")
        safeCVar("nameplateUseClassColorForFriendlyPlayerUnitNames", db.classColor and "1" or "0")
        -- Force the "show only name" mode to actually apply on friendly player nameplates
        if db.showOnlyName and TextureLoadingGroupMixin and NamePlateFriendlyFrameOptions then
            TextureLoadingGroupMixin.RemoveTexture({ textures = NamePlateFriendlyFrameOptions }, "updateNameUsesGetUnitName")
        end
    end
    reloadNameplates()
end

--- Apply the custom font to both global font objects.
local function applyFont()
    if not db.customFont then return end
    SystemFont_NamePlate_Outlined:SetFont(defaultFont.name, db.fontSize, defaultFont.flags)
    SystemFont_NamePlate:SetFont(defaultFont2.name, db.fontSize, defaultFont2.flags)
end

--- Restore both global font objects to their original values.
local function restoreFont()
    SystemFont_NamePlate_Outlined:SetFont(defaultFont.name, defaultFont.size, defaultFont.flags)
    SystemFont_NamePlate:SetFont(defaultFont2.name, defaultFont2.size, defaultFont2.flags)
end

--- Apply font to all visible non-forbidden nameplate FontStrings.
local function setFontForAll()
    if not db.customFont then return end
    for _, frame in pairs(C_NamePlate.GetNamePlates()) do
        if frame and frame.UnitFrame and frame.UnitFrame.name then
            frame.UnitFrame.name:SetFont(defaultFont.name, db.fontSize, defaultFont.flags)
        end
    end
end

--- Force WoW to re-render nameplates by temporarily changing font size.
--- @param needDelay boolean Use a delay for forbidden nameplates
local function forceUpdateFont(needDelay)
    if not db.customFont then return end
    local transientSize = db.fontSize > MIN_FONT_SIZE and (db.fontSize - 1) or (db.fontSize + 1)
    SystemFont_NamePlate_Outlined:SetFont(defaultFont.name, transientSize, defaultFont.flags)
    SystemFont_NamePlate:SetFont(defaultFont2.name, transientSize, defaultFont2.flags)
    if not needDelay then
        applyFont()
    else
        C_Timer.After(0.1, function() applyFont() end)
    end
end

-- Main frame and event handling
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")

local events = {}

function events.ADDON_LOADED(_, addonName)
    if addonName ~= ADDON_NAME then
        return
    end
    if not ZaeUI_Shared then
        local msg = "ZaeUI_Shared is required. Install it from CurseForge."
        print(PREFIX .. "Error: " .. msg .. " Addon disabled.")
        C_Timer.After(5, function() UIErrorsFrame:AddMessage("|cffff0000[" .. ADDON_NAME .. "]|r " .. msg, 1, 0.2, 0.2, 1, 5) end)
        return
    end

    -- Capture original font values before any addon modifies them
    local f1, s1, fl1 = SystemFont_NamePlate_Outlined:GetFont()
    defaultFont.name, defaultFont.size, defaultFont.flags = f1, s1, fl1
    local f2, s2, fl2 = SystemFont_NamePlate:GetFont()
    defaultFont2.name, defaultFont2.size, defaultFont2.flags = f2, s2, fl2

    initDB()

    frame:UnregisterEvent("ADDON_LOADED")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
end

function events.PLAYER_LOGIN()
    -- Apply settings after all Blizzard addons are loaded
    -- (NamePlateDriverFrame, NamePlateFriendlyFrameOptions are available now)
    saveCVars()
    applyCVars()

    if db.customFont then
        applyFont()
    end

    -- Hook for new nameplates (including forbidden ones in instances)
    hooksecurefunc(NamePlateDriverFrame, "OnNamePlateAdded", function(_, unit)
        if not db.customFont then return end
        if not unit:match("^nameplate") then return end
        local np = C_NamePlate.GetNamePlateForUnit(unit)
        if not np then
            forceUpdateFont(false)
        else
            if np.UnitFrame and np.UnitFrame.name then
                np.UnitFrame.name:SetFont(defaultFont.name, db.fontSize, defaultFont.flags)
            end
        end
    end)

    -- Hook for font re-sync when Blizzard updates nameplate size
    hooksecurefunc(NamePlateDriverFrame, "UpdateNamePlateSize", function()
        if not db.enabled then return end
        if not db.customFont then return end
        forceUpdateFont(true)
    end)

    -- Hook for forbidden nameplates: apply show-only-name on friendly NPC units
    hooksecurefunc(NamePlateUnitFrameMixin, "OnUnitSet", function(self)
        local unit = self.unit or self.displayedUnit
        if not unit then return end
        if not UnitIsFriend("player", unit) then return end
        local np = C_NamePlate.GetNamePlateForUnit(unit)
        if not np then
            if not self:IsPlayer() and db.showOnlyName and TableUtil and TableUtil.TrySet then
                TableUtil.TrySet(self, "showOnlyName", true)
            end
        end
    end)

    -- Hook for forbidden nameplates: class color, cast bar, health bar
    -- Only modify friendly nameplates — enemy nameplates must stay untouched
    hooksecurefunc(NamePlateUnitFrameMixin, "UpdateNameClassColor", function(self)
        local unit = self.unit or self.displayedUnit
        if not unit then return end
        if not UnitIsFriend("player", unit) then return end
        local np = C_NamePlate.GetNamePlateForUnit(unit)
        if not np then
            if db.classColor and TableUtil and TableUtil.TrySet and TextureLoadingGroupMixin then
                TableUtil.TrySet(self.optionTable, "colorNameBySelection", true)
                TextureLoadingGroupMixin.AddTexture({ textures = self }, "explicitIsPlayer")
            end

            if db.showOnlyName and TableUtil and TableUtil.TrySet then
                -- Hide cast bar
                TableUtil.TrySet(self.castBar, "showOnlyName", true)
                TableUtil.TrySet(self.castBar, "widgetsOnly", true)
            end
        end
    end)

    frame:UnregisterEvent("PLAYER_LOGIN")
    print(PREFIX .. "Loaded. Type /zfp help for commands.")
end

function events.PLAYER_ENTERING_WORLD()
    applyCVars()
    -- Delayed reload: nameplates are not yet initialized right after a loading screen
    C_Timer.After(0.5, function() reloadNameplates() end)
end

frame:SetScript("OnEvent", function(_, event, ...)
    if events[event] then
        events[event](frame, ...)
    end
end)

-- Slash command handler
SLASH_ZAEUIFRIENDLYPLATES1 = "/zfp"

SlashCmdList["ZAEUIFRIENDLYPLATES"] = function(msg)
    msg = strtrim(msg)

    if msg == "" or msg == "options" then
        if ns.settingsCategory then
            Settings.OpenToCategory(ns.settingsCategory.ID)
        else
            print(PREFIX .. "Options panel not yet loaded.")
        end
        return
    end

    if msg == "help" then
        print(PREFIX .. "Usage:")
        print(PREFIX .. "  /zfp - Open the options panel")
        print(PREFIX .. "  /zfp toggle - Toggle friendly nameplates on/off")
        print(PREFIX .. "  /zfp size <number> - Set font size (" .. MIN_FONT_SIZE .. "-" .. MAX_FONT_SIZE .. ")")
        print(PREFIX .. "  /zfp reset - Reset all settings to defaults")
        return
    end

    if msg == "toggle" then
        db.enabled = not db.enabled
        applyCVars()
        if db.enabled then
            print(PREFIX .. "Friendly nameplates enabled.")
        else
            print(PREFIX .. "Friendly nameplates disabled.")
        end
        if ns.refreshWidgets then
            ns.refreshWidgets()
        end
        return
    end

    local sizeArg = msg:match("^size%s+(.+)$")
    if sizeArg then
        local value = tonumber(sizeArg)
        if not value then
            print(PREFIX .. "Usage: /zfp size <number>")
            return
        end
        value = math_floor(value)
        if value < MIN_FONT_SIZE or value > MAX_FONT_SIZE then
            print(PREFIX .. "Font size must be between " .. MIN_FONT_SIZE .. " and " .. MAX_FONT_SIZE)
            return
        end
        db.fontSize = value
        if db.customFont then
            forceUpdateFont(true)
            setFontForAll()
        end
        print(PREFIX .. "Font size set to: " .. value)
        if ns.refreshWidgets then
            ns.refreshWidgets()
        end
        return
    end

    if msg == "reset" then
        restoreCVars()
        restoreFont()
        db.originalCVars = nil
        baseCVars = nil
        for key, value in pairs(DEFAULTS) do
            db[key] = value
        end
        reloadNameplates()
        if ns.refreshWidgets then
            ns.refreshWidgets()
        end
        print(PREFIX .. "All settings reset to defaults.")
        return
    end

    print(PREFIX .. "Unknown command. Type /zfp help for usage.")
end

-- Expose to namespace for Options.lua
ns.constants = {
    MIN_FONT_SIZE = MIN_FONT_SIZE,
    MAX_FONT_SIZE = MAX_FONT_SIZE,
    DEFAULT_ENABLED = DEFAULT_ENABLED,
    DEFAULT_SHOW_ONLY_NAME = DEFAULT_SHOW_ONLY_NAME,
    DEFAULT_CLASS_COLOR = DEFAULT_CLASS_COLOR,
    DEFAULT_CUSTOM_FONT = DEFAULT_CUSTOM_FONT,
    DEFAULT_FONT_SIZE = DEFAULT_FONT_SIZE,
    DEFAULTS = DEFAULTS,
}
ns.applyCVars = applyCVars
ns.applyFont = applyFont
ns.restoreFont = restoreFont
ns.forceUpdateFont = forceUpdateFont
ns.setFontForAll = setFontForAll
ns.reloadNameplates = reloadNameplates
ns.restoreCVars = restoreCVars

-- ZaeUI_Defensives: Track defensive cooldowns for your group
-- Uses addon messaging to share cooldown state between group members

local _, ns = ...

-- Local references to WoW APIs
local CreateFrame = CreateFrame
local C_ChatInfo = C_ChatInfo
local C_Timer = C_Timer
local C_Spell = C_Spell
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local UnitName = UnitName
local UnitClass = UnitClass
local GetNumGroupMembers = GetNumGroupMembers
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local GetTime = GetTime
local IsSpellKnown = IsSpellKnown
local strtrim = strtrim
local strsplit = strsplit
local tonumber = tonumber
local tostring = tostring
local table_concat = table.concat
local pairs = pairs
local pcall = pcall

--- Check if the player is in any type of group.
--- @return boolean
function ns.isInAnyGroup()
    return not not (IsInGroup() or IsInGroup(LE_PARTY_CATEGORY_INSTANCE) or IsInRaid())
end

-- Constants
local ADDON_NAME = "ZaeUI_Defensives"
local COMM_PREFIX = "ZaeDef"
local HEARTBEAT_INTERVAL = 10
local PREFIX = "|cff00ccff[ZaeUI_Defensives]|r "

-- Local state
local db
local mySpells = {}
local groupData = {}
local syncList = {}

-- Default settings
local DEFAULTS = {
    trackerEnabled = true,
    trackerOpacity = 80,
    trackerLocked = false,
    trackerShowExternal = true,
    trackerShowPersonal = true,
    trackerShowRaidwide = true,
    trackerHideWhenSolo = true,
    collapsed = false,
    framePoint = { "CENTER", nil, "CENTER", 0, 0 },
}

--- Initialize database with defaults for any missing keys.
local function initDB()
    if not ZaeUI_DefensivesDB then
        ZaeUI_DefensivesDB = {}
    end
    for key, value in pairs(DEFAULTS) do
        if key == "framePoint" then
            if ZaeUI_DefensivesDB[key] == nil then
                ZaeUI_DefensivesDB[key] = { value[1], value[2], value[3], value[4], value[5] }
            end
        else
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
    end
    db = ZaeUI_DefensivesDB
    ns.db = db
end

-- Heartbeat timer
local heartbeatElapsed = 0
local heartbeatFrame = CreateFrame("Frame")

--- Start the heartbeat sync timer.
local function startHeartbeat()
    heartbeatElapsed = 0
    heartbeatFrame:SetScript("OnUpdate", function(_, elapsed)
        heartbeatElapsed = heartbeatElapsed + elapsed
        if heartbeatElapsed >= HEARTBEAT_INTERVAL then
            heartbeatElapsed = 0
            ns.sendSync()
        end
    end)
end

--- Stop the heartbeat sync timer.
local function stopHeartbeat()
    heartbeatFrame:SetScript("OnUpdate", nil)
end

-- Messaging ----------------------------------------------------------------

--- Check if we can safely send addon messages.
--- @return boolean
local function canSendMessage()
    return ns.isInAnyGroup() and GetNumGroupMembers() > 0
end

--- Get the appropriate channel for addon messages.
--- @return string channel
local function getChannel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    return "PARTY"
end

--- Safely send an addon message, suppressing errors during instance transitions.
--- @param msg string The message to send
local function safeSend(msg)
    if not canSendMessage() then return end
    pcall(C_ChatInfo.SendAddonMessage, COMM_PREFIX, msg, getChannel())
end

--- Send a SYNC message with all tracked spell IDs.
function ns.sendSync()
    local n = 0
    for spellID in pairs(mySpells) do
        n = n + 1
        syncList[n] = tostring(spellID)
    end
    for i = n + 1, #syncList do syncList[i] = nil end
    if n == 0 then return end
    safeSend("SYNC:" .. table_concat(syncList, ","))
end

--- Send a USED message when a tracked spell is cast.
--- @param spellID number
--- @param cooldown number
function ns.sendUsed(spellID, cooldown)
    safeSend("USED:" .. spellID .. ":" .. cooldown)
end

--- Send a READY message when a tracked spell's cooldown ends.
--- @param spellID number
function ns.sendReady(spellID)
    safeSend("READY:" .. spellID)
end

--- Handle incoming addon messages.
--- @param message string
--- @param sender string
function ns.handleAddonMessage(message, sender)
    local msgType, payload = message:match("^(%a+):(.+)$")
    if not msgType then return end
    local name = strsplit("-", sender)
    local myName = UnitName("player")
    if name == myName then return end

    if msgType == "SYNC" then
        groupData[name] = groupData[name] or { spells = {}, cooldowns = {} }
        groupData[name].hasAddon = true
        local spells = groupData[name].spells
        for k in pairs(spells) do spells[k] = nil end
        for idStr in payload:gmatch("[^,]+") do
            local id = tonumber(idStr)
            if id then spells[id] = true end
        end
    elseif msgType == "USED" then
        local spellIDStr, cdStr = strsplit(":", payload)
        local spellID = tonumber(spellIDStr)
        local cooldown = tonumber(cdStr)
        if spellID and cooldown then
            groupData[name] = groupData[name] or { spells = {}, cooldowns = {} }
            groupData[name].cooldowns[spellID] = GetTime() + cooldown
        end
    elseif msgType == "READY" then
        local spellID = tonumber(payload)
        if spellID then
            groupData[name] = groupData[name] or { spells = {}, cooldowns = {} }
            groupData[name].cooldowns[spellID] = nil
        end
    end
    if ns.refreshDisplay then ns.refreshDisplay() end
end

-- Spell scanning -----------------------------------------------------------

--- Scan the local player's spellbook for known defensive spells.
function ns.scanMySpells()
    for k in pairs(mySpells) do mySpells[k] = nil end
    local spellData = ns.spellData
    if not spellData then return end
    for spellID, _ in pairs(spellData) do
        if IsSpellKnown(spellID) then
            mySpells[spellID] = true
        end
    end
    local myName = UnitName("player")
    if myName then
        groupData[myName] = groupData[myName] or { spells = {}, cooldowns = {} }
        local spells = groupData[myName].spells
        for k in pairs(spells) do spells[k] = nil end
        for spellID in pairs(mySpells) do
            spells[spellID] = true
        end
    end
end

--- Remove data for players no longer in the group.
function ns.cleanGroupData()
    local currentMembers = {}
    local numMembers = GetNumGroupMembers()
    local isRaid = IsInRaid()
    local count = isRaid and numMembers or (numMembers - 1)
    for i = 1, count do
        local unit = isRaid and ("raid" .. i) or ("party" .. i)
        local name = UnitName(unit)
        if name then currentMembers[name] = true end
    end
    local myName = UnitName("player")
    currentMembers[myName] = true
    for name, _ in pairs(groupData) do
        if not currentMembers[name] then
            groupData[name] = nil
        end
    end
end

-- Class color cache --------------------------------------------------------

--- Pre-computed class color hex strings (static, computed once).
local classColorByClass = {}
for className, c in pairs(RAID_CLASS_COLORS) do
    classColorByClass[className] = string.format("%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
end

--- Cached player-to-hex mapping, rebuilt on GROUP_ROSTER_UPDATE.
local classColorCache = {}

--- Rebuild the class color cache from current group roster.
function ns.rebuildClassColorCache()
    for k in pairs(classColorCache) do classColorCache[k] = nil end
    local numMembers = GetNumGroupMembers()
    local isRaid = IsInRaid()
    local count = isRaid and numMembers or (numMembers - 1)
    for i = 1, count do
        local unit = isRaid and ("raid" .. i) or ("party" .. i)
        local name = UnitName(unit)
        if name and not classColorCache[name] then
            local _, className = UnitClass(unit)
            if className and classColorByClass[className] then
                classColorCache[name] = classColorByClass[className]
            end
        end
    end
    local myName = UnitName("player")
    if myName and not classColorCache[myName] then
        local _, className = UnitClass("player")
        if className and classColorByClass[className] then
            classColorCache[myName] = classColorByClass[className]
        end
    end
end

--- Get class color hex string for a player name.
--- @param playerName string
--- @return string hex "rrggbb"
function ns.getClassColorHex(playerName)
    return classColorCache[playerName] or "ffffff"
end

--- Shared backdrop definition for all addon frames.
local SHARED_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

--- Apply standard backdrop styling to a frame.
--- @param target table The frame (must inherit BackdropTemplate)
function ns.applyBackdrop(target)
    target:SetBackdrop(SHARED_BACKDROP)
    target:SetBackdropColor(0, 0, 0, 0.8)
    target:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    local opacity = (ns.db and ns.db.trackerOpacity or 80) / 100
    target:SetAlpha(opacity)
end

-- Main frame and event handling --------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")

local events = {}

function events.ADDON_LOADED(_, addonName)
    if addonName ~= ADDON_NAME then return end
    C_ChatInfo.RegisterAddonMessagePrefix(COMM_PREFIX)
    initDB()
    ns.scanMySpells()
    ns.rebuildClassColorCache()

    frame:UnregisterEvent("ADDON_LOADED")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    frame:RegisterEvent("UNIT_PET")

    print(PREFIX .. "Loaded. Type /zdef help for commands.")
end

function events.PLAYER_LOGIN()
    if db.trackerEnabled then
        if not db.trackerHideWhenSolo or ns.isInAnyGroup() then
            if ns.showDisplay then ns.showDisplay() end
        end
    end
    frame:UnregisterEvent("PLAYER_LOGIN")
end

function events.GROUP_ROSTER_UPDATE()
    if ns.isInAnyGroup() then
        startHeartbeat()
    else
        stopHeartbeat()
    end
    ns.rebuildClassColorCache()
    ns.cleanGroupData()
    ns.sendSync()
    if ns.refreshDisplay then ns.refreshDisplay() end
end

function events.CHAT_MSG_ADDON(_, prefix, message, _, sender)
    if prefix ~= COMM_PREFIX then return end
    ns.handleAddonMessage(message, sender)
end

function events.PLAYER_SPECIALIZATION_CHANGED()
    ns.scanMySpells()
    ns.sendSync()
end

function events.UNIT_PET(_, unit)
    if unit ~= "player" then return end
    ns.scanMySpells()
    ns.sendSync()
end

function events.PLAYER_ENTERING_WORLD()
    ns.scanMySpells()
    ns.rebuildClassColorCache()
    ns.sendSync()
    if ns.refreshDisplay then ns.refreshDisplay() end
end

function events.UNIT_SPELLCAST_SUCCEEDED(_, unit, _, spellID)
    if unit ~= "player" and unit ~= "pet" then return end
    if not mySpells[spellID] then return end
    local spellData = ns.spellData
    local info = spellData and spellData[spellID]
    if not info then return end
    -- Use actual cooldown from spell system (respects talent modifiers).
    -- C_Spell.GetSpellCooldown can return tainted values; pcall avoids the
    -- "secret number" comparison error.
    local cd = info.cooldown
    local ok, cdInfo = pcall(C_Spell.GetSpellCooldown, spellID)
    if ok and cdInfo then
        local okDur, dur = pcall(function() return cdInfo.duration and cdInfo.duration > 0 and cdInfo.duration end)
        if okDur and dur then cd = dur end
    end
    if cd > 0 then
        ns.sendUsed(spellID, cd)
        local myName = UnitName("player")
        if not myName then return end
        groupData[myName] = groupData[myName] or { spells = {}, cooldowns = {} }
        groupData[myName].cooldowns[spellID] = GetTime() + cd
        C_Timer.After(cd, function()
            ns.sendReady(spellID)
            if groupData[myName] then
                groupData[myName].cooldowns[spellID] = nil
            end
            if ns.refreshDisplay then ns.refreshDisplay() end
        end)
        if ns.refreshDisplay then ns.refreshDisplay() end
    end
end

frame:SetScript("OnEvent", function(_, event, ...)
    if events[event] then
        events[event](frame, ...)
    end
end)

-- Slash command handler ----------------------------------------------------

SLASH_ZAEUIDEFENSIVES1 = "/zdef"

SlashCmdList["ZAEUIDEFENSIVES"] = function(msg)
    msg = strtrim(msg)

    if msg == "" or msg == "options" then
        if ns.settingsCategory then
            Settings.OpenToCategory(ns.settingsCategory.ID)
        else
            print(PREFIX .. "Options panel not yet loaded.")
        end
        return
    end

    if msg == "tracker" then
        db.trackerEnabled = not db.trackerEnabled
        if db.trackerEnabled then
            if ns.showDisplay then ns.showDisplay() end
            print(PREFIX .. "Tracker enabled.")
        else
            if ns.hideDisplay then ns.hideDisplay() end
            print(PREFIX .. "Tracker disabled.")
        end
        if ns.refreshWidgets then ns.refreshWidgets() end
        return
    end

    if msg == "reset" then
        ZaeUI_DefensivesDB = nil
        initDB()
        if ns.refreshWidgets then ns.refreshWidgets() end
        if ns.refreshDisplay then ns.refreshDisplay() end
        print(PREFIX .. "All settings reset to defaults.")
        return
    end

    if msg == "help" then
        print(PREFIX .. "Usage:")
        print(PREFIX .. "  /zdef - Open the options panel")
        print(PREFIX .. "  /zdef tracker - Toggle the floating tracker")
        print(PREFIX .. "  /zdef reset - Reset all settings to defaults")
        return
    end

    print(PREFIX .. "Unknown command. Type /zdef help for usage.")
end

-- Expose to namespace ------------------------------------------------------

ns.mySpells = mySpells
ns.groupData = groupData
ns.COMM_PREFIX = COMM_PREFIX
ns.PREFIX = PREFIX
ns.ADDON_NAME = ADDON_NAME
ns.constants = { DEFAULTS = DEFAULTS }
ns.safeSend = safeSend

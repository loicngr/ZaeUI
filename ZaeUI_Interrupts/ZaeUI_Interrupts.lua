-- ZaeUI_Interrupts: Track interrupt, stun and knockback cooldowns for your group
-- Uses addon messaging to share cooldown state between group members

local _, ns = ...

-- Local references to WoW APIs
local CreateFrame = CreateFrame
local C_ChatInfo = C_ChatInfo
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local UnitClass = UnitClass
local UnitName = UnitName
local GetNumGroupMembers = GetNumGroupMembers
local IsInInstance = IsInInstance
local strtrim = strtrim
local strsplit = strsplit

-- Constants
local ADDON_NAME = "ZaeUI_Interrupts"
local COMM_PREFIX = "ZaeInt"
local HEARTBEAT_INTERVAL = 10
local PREFIX = "|cff00ccff[ZaeUI_Interrupts]|r "

-- Local state
local db
local mySpells = {}       -- spells the local player can use { [spellID] = true }
local groupData = {}      -- data from all group members { [playerName] = { spells = {}, cooldowns = {} } }

-- Default settings
local DEFAULTS = {
    showFrame = true,
    autoHide = true,
    showCounter = true,
    autoResetCounters = true,
    framePoint = { "CENTER", nil, "CENTER", 0, 0 },
    customSpells = {},    -- { [spellID] = true } added by user
    removedSpells = {},   -- { [spellID] = true } removed by user
}

--- Initialize database with defaults for any missing keys.
local function initDB()
    if not ZaeUI_InterruptsDB then
        ZaeUI_InterruptsDB = {}
    end
    for key, value in pairs(DEFAULTS) do
        if ZaeUI_InterruptsDB[key] == nil then
            if type(value) == "table" then
                local copy = {}
                for k, v in pairs(value) do copy[k] = v end
                ZaeUI_InterruptsDB[key] = copy
            else
                ZaeUI_InterruptsDB[key] = value
            end
        end
    end
    db = ZaeUI_InterruptsDB
    ns.db = db
end

-- Heartbeat timer
local heartbeatElapsed = 0
local heartbeatFrame = CreateFrame("Frame")

-- Main frame and event handling
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")

local events = {}

function events.ADDON_LOADED(_, addonName)
    if addonName ~= ADDON_NAME then return end
    C_ChatInfo.RegisterAddonMessagePrefix(COMM_PREFIX)
    initDB()

    frame:UnregisterEvent("ADDON_LOADED")
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    frame:RegisterEvent("UNIT_PET")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")

    -- Heartbeat timer is started/stopped via GROUP_ROSTER_UPDATE

    -- Scan spells on load
    ns.scanMySpells()

    -- Show tracker if enabled (deferred so Display.lua has loaded its functions)
    C_Timer.After(0, function()
        if db.showFrame and ns.showDisplay then
            if not db.autoHide or IsInGroup() or IsInRaid() then
                ns.showDisplay()
            end
        end
    end)

    print(PREFIX .. "Loaded. Type /zint help for commands.")
end

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

function events.GROUP_ROSTER_UPDATE()
    -- Start or stop heartbeat based on group status
    if IsInGroup() or IsInRaid() then
        startHeartbeat()
    else
        stopHeartbeat()
    end
    -- Clean stale group members, send sync
    ns.cleanGroupData()
    ns.sendSync()
end

function events.CHAT_MSG_ADDON(_, prefix, message, channel, sender)
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
    if db.autoResetCounters then
        local _, instanceType = IsInInstance()
        if instanceType == "party" or instanceType == "raid" then
            ns.resetCounters()
        end
    end
end

function events.UNIT_SPELLCAST_SUCCEEDED(_, unit, _, spellID)
    if unit ~= "player" and unit ~= "pet" then return end
    if not mySpells[spellID] then return end
    local spellData = ns.spellData
    local info = spellData and spellData[spellID]
    local cd = info and info.cooldown or 0
    if cd > 0 then
        ns.sendUsed(spellID, cd)
        local myName = UnitName("player")
        if not myName then return end
        groupData[myName] = groupData[myName] or { spells = {}, cooldowns = {}, counters = {} }
        groupData[myName].cooldowns[spellID] = GetTime() + cd
        groupData[myName].counters[spellID] = (groupData[myName].counters[spellID] or 0) + 1
        C_Timer.After(cd, function()
            ns.sendReady(spellID)
            groupData[myName].cooldowns[spellID] = nil
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

-- Expose to namespace
ns.mySpells = mySpells
ns.groupData = groupData
ns.COMM_PREFIX = COMM_PREFIX
ns.PREFIX = PREFIX
ns.ADDON_NAME = ADDON_NAME

--- Scan the local player's spellbook for known interrupt/stun/knockback spells.
function ns.scanMySpells()
    for k in pairs(mySpells) do mySpells[k] = nil end
    local spellData = ns.spellData
    if not spellData then return end
    for spellID, info in pairs(spellData) do
        if not (db.removedSpells[spellID]) then
            local isPetSpell = info.pet
            if IsSpellKnown(spellID, isPetSpell) then
                mySpells[spellID] = true
            end
        end
    end
    -- Add custom spells
    for spellID, _ in pairs(db.customSpells) do
        if IsSpellKnown(spellID) then
            mySpells[spellID] = true
        end
    end

    -- Register the local player in groupData so the display works even solo
    local myName = UnitName("player")
    if myName then
        groupData[myName] = groupData[myName] or { spells = {}, cooldowns = {}, counters = {} }
        groupData[myName].counters = groupData[myName].counters or {}
        -- Sync spells list (wipe and repopulate)
        local spells = groupData[myName].spells
        for k in pairs(spells) do spells[k] = nil end
        for spellID, _ in pairs(mySpells) do
            spells[spellID] = true
        end
    end
end

--- Get the appropriate channel for addon messages.
--- @return string channel "RAID" or "PARTY"
local function getChannel()
    if IsInRaid() then return "RAID" end
    return "PARTY"
end

--- Send a SYNC message with all tracked spell IDs.
function ns.sendSync()
    if not (IsInGroup() or IsInRaid()) then return end
    local spellList = {}
    for spellID, _ in pairs(mySpells) do
        spellList[#spellList + 1] = tostring(spellID)
    end
    if #spellList == 0 then return end
    local msg = "SYNC:" .. table.concat(spellList, ",")
    C_ChatInfo.SendAddonMessage(COMM_PREFIX, msg, getChannel())
end

--- Send a USED message when a tracked spell is cast.
--- @param spellID number The spell ID used
--- @param cooldown number The cooldown duration in seconds
function ns.sendUsed(spellID, cooldown)
    if not (IsInGroup() or IsInRaid()) then return end
    local msg = "USED:" .. spellID .. ":" .. cooldown
    C_ChatInfo.SendAddonMessage(COMM_PREFIX, msg, getChannel())
end

--- Send a READY message when a tracked spell's cooldown ends.
--- @param spellID number The spell ID that is ready
function ns.sendReady(spellID)
    if not (IsInGroup() or IsInRaid()) then return end
    local msg = "READY:" .. spellID
    C_ChatInfo.SendAddonMessage(COMM_PREFIX, msg, getChannel())
end

--- Handle incoming addon messages.
--- @param message string The raw message
--- @param sender string The sender's name
function ns.handleAddonMessage(message, sender)
    local msgType, payload = message:match("^(%a+):(.+)$")
    if not msgType then return end

    -- Strip realm name from sender if present
    local name = strsplit("-", sender)

    -- Skip messages from self (already handled locally via UNIT_SPELLCAST_SUCCEEDED)
    local myName = UnitName("player")
    if name == myName then return end

    if msgType == "SYNC" then
        local spellIDs = { strsplit(",", payload) }
        groupData[name] = groupData[name] or { spells = {}, cooldowns = {}, counters = {} }
        groupData[name].spells = {}
        for _, idStr in ipairs(spellIDs) do
            local id = tonumber(idStr)
            if id then groupData[name].spells[id] = true end
        end
    elseif msgType == "USED" then
        local spellIDStr, cdStr = strsplit(":", payload)
        local spellID = tonumber(spellIDStr)
        local cooldown = tonumber(cdStr)
        if spellID and cooldown then
            groupData[name] = groupData[name] or { spells = {}, cooldowns = {}, counters = {} }
            groupData[name].cooldowns[spellID] = GetTime() + cooldown
            groupData[name].counters[spellID] = (groupData[name].counters[spellID] or 0) + 1
        end
    elseif msgType == "READY" then
        local spellID = tonumber(payload)
        if spellID then
            groupData[name] = groupData[name] or { spells = {}, cooldowns = {}, counters = {} }
            groupData[name].cooldowns[spellID] = nil
        end
    end

    -- Refresh display
    if ns.refreshDisplay then
        ns.refreshDisplay()
    end
end

--- Reset all spell use counters for every player.
function ns.resetCounters()
    for _, data in pairs(groupData) do
        if data.counters then
            for k in pairs(data.counters) do data.counters[k] = nil end
        end
    end
    if ns.refreshDisplay then ns.refreshDisplay() end
end

--- Remove data for players no longer in the group.
function ns.cleanGroupData()
    local currentMembers = {}
    local numMembers = GetNumGroupMembers()
    for i = 1, numMembers do
        local unit = IsInRaid() and ("raid" .. i) or ("party" .. i)
        local name = UnitName(unit)
        if name then currentMembers[name] = true end
    end
    -- Always include the player
    local myName = UnitName("player")
    currentMembers[myName] = true
    for name, _ in pairs(groupData) do
        if not currentMembers[name] then
            groupData[name] = nil
        end
    end
end

-- Slash command handler
SLASH_ZAEUIINTERRUPTS1 = "/zint"

SlashCmdList["ZAEUIINTERRUPTS"] = function(msg)
    msg = strtrim(msg)

    if msg == "" then
        if ns.toggleDisplay then
            ns.toggleDisplay()
        else
            print(PREFIX .. "Display not available. Type /zint help for commands.")
        end
        return
    end

    if msg == "options" then
        if ns.settingsCategory then
            Settings.OpenToCategory(ns.settingsCategory.ID)
        else
            print(PREFIX .. "Options panel not yet loaded.")
        end
        return
    end

    if msg == "resetcount" then
        ns.resetCounters()
        print(PREFIX .. "Spell counters reset.")
        return
    end

    if msg == "reset" then
        ZaeUI_InterruptsDB = nil
        initDB()
        print(PREFIX .. "All settings reset to defaults.")
        return
    end

    if msg == "help" then
        print(PREFIX .. "Usage:")
        print(PREFIX .. "  /zint - Toggle the tracker window")
        print(PREFIX .. "  /zint options - Open the options panel")
        print(PREFIX .. "  /zint resetcount - Reset spell use counters")
        print(PREFIX .. "  /zint reset - Reset all settings to defaults")
        return
    end

    print(PREFIX .. "Unknown command. Type /zint help for usage.")
end

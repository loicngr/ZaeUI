-- ZaeUI_Interrupts: Track interrupt, stun and knockback cooldowns for your group
-- Uses addon messaging to share cooldown state between group members

local _, ns = ...

-- Local references to WoW APIs
local CreateFrame = CreateFrame
local C_ChatInfo = C_ChatInfo
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local UnitName = UnitName
local UnitClass = UnitClass
local GetNumGroupMembers = GetNumGroupMembers
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local IsInInstance = IsInInstance
local GetTime = GetTime
local C_Spell = C_Spell
local IsSpellKnown = IsSpellKnown
local strtrim = strtrim
local strsplit = strsplit
local tonumber = tonumber
local tostring = tostring
local table_concat = table.concat
local pairs = pairs
local pcall = pcall

--- Check if the player is in any type of group (home, instance/LFG, or raid).
--- Covers manual groups (LE_PARTY_CATEGORY_HOME) and LFG/instance groups
--- (LE_PARTY_CATEGORY_INSTANCE) so the addon works in all scenarios.
--- @return boolean
function ns.isInAnyGroup()
    return not not (IsInGroup() or IsInGroup(LE_PARTY_CATEGORY_INSTANCE) or IsInRaid())
end

-- Constants
local ADDON_NAME = "ZaeUI_Interrupts"
local COMM_PREFIX = "ZaeInt"
local HEARTBEAT_INTERVAL = 10
local PREFIX = "|cff00ccff[ZaeUI_Interrupts]|r "

-- Local state
local db
local mySpells = {}       -- spells the local player can use { [spellID] = true }
local groupData = {}      -- data from all group members { [playerName] = { spells = {}, cooldowns = {} } }
local syncList = {}       -- reusable table for sendSync

-- Default settings
local DEFAULTS = {
    showFrame = true,
    autoHide = true,
    showCounter = false,
    autoResetCounters = true,
    hideReady = false,
    showInterrupts = true,
    showStuns = true,
    showOthers = true,
    lockFrame = false,
    collapsed = false,
    collapsedCategories = {},
    frameOpacity = 80,
    framePoint = { "CENTER", nil, "CENTER", 0, 0 },
    customSpells = {},    -- { [spellID] = true } added by user
    removedSpells = {},   -- { [spellID] = true } removed by user
    separateMarkerWindow = false, -- show markers in separate window instead of tracker
    markerAssignments = {}, -- persisted kick marker assignments
    assignPanelPoint = { "CENTER", nil, "CENTER", 0, 0 },
    markerWindowPoint = { "CENTER", nil, "CENTER", 0, 0 },
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
    ns.markerAssignments = db.markerAssignments

    frame:UnregisterEvent("ADDON_LOADED")
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    frame:RegisterEvent("UNIT_PET")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")

    -- Heartbeat timer is started/stopped via GROUP_ROSTER_UPDATE

    -- Scan spells on load and build class color cache
    ns.scanMySpells()
    ns.rebuildClassColorCache()

    -- Show tracker if enabled (all TOC files are loaded before events fire,
    -- so ns.showDisplay is already available here — no timer needed)
    if db.showFrame then
        if not db.autoHide or ns.isInAnyGroup() then
            ns.showDisplay()
        end
    end

    -- Refresh marker display if there are persisted assignments
    if next(ns.markerAssignments) then
        if ns.refreshMarkerDisplay then ns.refreshMarkerDisplay() end
    end

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
    if ns.isInAnyGroup() then
        startHeartbeat()
    else
        stopHeartbeat()
    end
    -- Rebuild class color cache, clean stale group members and assignments, send sync
    ns.rebuildClassColorCache()
    ns.cleanGroupData()
    if ns.cleanStaleAssignments then ns.cleanStaleAssignments() end
    ns.sendSync()
    -- Refresh assignment panel and marker display
    if ns.refreshAssignPanel then ns.refreshAssignPanel() end
    if ns.refreshMarkerDisplay then ns.refreshMarkerDisplay() end
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
    if db.autoResetCounters then
        local _, instanceType = IsInInstance()
        if instanceType == "party" or instanceType == "raid" then
            ns.resetCounters()
        end
    end
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
        groupData[myName] = groupData[myName] or { spells = {}, cooldowns = {}, counters = {} }
        groupData[myName].cooldowns[spellID] = GetTime() + cd
        groupData[myName].counters[spellID] = (groupData[myName].counters[spellID] or 0) + 1
        C_Timer.After(cd, function()
            ns.sendReady(spellID)
            local entry = groupData[myName]
            if entry then entry.cooldowns[spellID] = nil end
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

--- Check if we can safely send addon messages.
--- @return boolean canSend Whether the player is in a valid group
local function canSendMessage()
    return ns.isInAnyGroup() and GetNumGroupMembers() > 0
end

--- Get the appropriate channel for addon messages.
--- @return string channel "INSTANCE_CHAT", "RAID" or "PARTY"
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
ns.safeSend = safeSend

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
    local opacity = (ns.db and ns.db.frameOpacity or 80) / 100
    target:SetAlpha(opacity)
end

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
--- Shared utility used by Display.lua, MarkerAssign.lua and MarkerDisplay.lua.
--- @param playerName string
--- @return string hex "rrggbb"
function ns.getClassColorHex(playerName)
    return classColorCache[playerName] or "ffffff"
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
--- @param spellID number The spell ID used
--- @param cooldown number The cooldown duration in seconds
function ns.sendUsed(spellID, cooldown)
    safeSend("USED:" .. spellID .. ":" .. cooldown)
end

--- Send a READY message when a tracked spell's cooldown ends.
--- @param spellID number The spell ID that is ready
function ns.sendReady(spellID)
    safeSend("READY:" .. spellID)
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
        groupData[name] = groupData[name] or { spells = {}, cooldowns = {}, counters = {} }
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
    elseif msgType == "MARKS" then
        if ns.handleMarksMessage then
            ns.handleMarksMessage(payload)
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
    local isRaid = IsInRaid()
    local count = isRaid and numMembers or (numMembers - 1)
    for i = 1, count do
        local unit = isRaid and ("raid" .. i) or ("party" .. i)
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

    if msg == "" or msg == "options" then
        if ns.settingsCategory then
            Settings.OpenToCategory(ns.settingsCategory.ID)
        else
            print(PREFIX .. "Options panel not yet loaded.")
        end
        return
    end

    if msg == "assign" then
        if ns.toggleAssignPanel then
            ns.toggleAssignPanel()
        else
            print(PREFIX .. "Assignment panel not available.")
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
        if ns.refreshWidgets then
            ns.refreshWidgets()
        end
        print(PREFIX .. "All settings reset to defaults.")
        return
    end

    if msg == "help" then
        print(PREFIX .. "Usage:")
        print(PREFIX .. "  /zint - Open the options panel")
        print(PREFIX .. "  /zint assign - Open kick marker assignments (leader only)")
        print(PREFIX .. "  /zint resetcount - Reset spell use counters")
        print(PREFIX .. "  /zint reset - Reset all settings to defaults")
        return
    end

    print(PREFIX .. "Unknown command. Type /zint help for usage.")
end

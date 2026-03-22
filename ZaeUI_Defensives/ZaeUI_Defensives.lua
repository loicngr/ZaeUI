-- ZaeUI_Defensives: Track defensive cooldowns for your group
-- Uses addon messaging to share cooldown state between group members

local _, ns = ...

-- Local references to WoW APIs
local CreateFrame = CreateFrame
local C_ChatInfo = C_ChatInfo
local C_Timer = C_Timer
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local UnitName = UnitName
local UnitClass = UnitClass
local GetNumGroupMembers = GetNumGroupMembers
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local GetTime = GetTime
local IsSpellKnown = IsSpellKnown
local IsPlayerSpell = IsPlayerSpell
local GetSpecialization = GetSpecialization
local GetSpecializationInfo = GetSpecializationInfo
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
    if not ZaeUI_Shared then return false end
    return ZaeUI_Shared.isInAnyGroup()
end

-- Constants
local ADDON_NAME = "ZaeUI_Defensives"
local COMM_PREFIX = "ZaeDef"
local HEARTBEAT_INTERVAL = 10
local PREFIX = "|cff00ccff[ZaeUI_Defensives]|r "

-- Local state
local db
local mySpells = {}
local cooldownOverrides = {} -- talent-adjusted cooldowns { [spellID] = effectiveCD }
local groupData = {}
local syncList = {}

-- Forward declarations for mode-aware routing (defined after event handlers)
local refreshDisplay, showDisplay, hideDisplay

-- Default settings
local DEFAULTS = {
    trackerEnabled = true,
    trackerOpacity = 80,
    trackerLocked = false,
    trackerShowExternal = true,
    trackerShowPersonal = false,
    trackerShowRaidwide = true,
    trackerHideWhenSolo = true,
    collapsed = false,
    framePoint = { "CENTER", nil, "CENTER", 0, 0 },
    displayMode = "floating",
    anchoredIconSize = 28,
    anchoredSpacing = 3,
    anchoredIconsPerRow = 2,
    anchoredSide = "RIGHT",
    anchoredOffsetX = 2,
    anchoredOffsetY = 30,
    anchoredShowPlayer = false,
}

--- Initialize database with defaults for any missing keys.
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
    refreshDisplay()
end

-- Spell scanning -----------------------------------------------------------

--- Scan the local player's spellbook for known defensive spells.
--- Also computes talent-adjusted cooldowns for the local player's spells.
function ns.scanMySpells()
    for k in pairs(mySpells) do mySpells[k] = nil end
    for k in pairs(cooldownOverrides) do cooldownOverrides[k] = nil end
    local spellData = ns.spellData
    if not spellData then return end
    -- Resolve specID once for all spells
    local currentSpecID
    local specIdx = GetSpecialization()
    if specIdx then
        currentSpecID = GetSpecializationInfo(specIdx)
    end
    for spellID, info in pairs(spellData) do
        if IsSpellKnown(spellID) then
            mySpells[spellID] = true
            -- Resolve base cooldown (may vary by spec)
            local baseCd = info.cooldown
            if currentSpecID and info.cooldownBySpec and info.cooldownBySpec[currentSpecID] then
                baseCd = info.cooldownBySpec[currentSpecID]
            end
            -- Apply talent-based cooldown modifiers
            if info.cdModifiers then
                local cd = baseCd
                for _, mod in pairs(info.cdModifiers) do
                    if mod.ranks then
                        for r = #mod.ranks, 1, -1 do
                            if IsPlayerSpell(mod.ranks[r].talent) then
                                cd = cd - mod.ranks[r].reduction
                                break
                            end
                        end
                    elseif IsPlayerSpell(mod.talent) then
                        local reduction = mod.reduction
                        if currentSpecID and mod.reductionBySpec and mod.reductionBySpec[currentSpecID] then
                            reduction = mod.reductionBySpec[currentSpecID]
                        end
                        cd = cd - reduction
                    end
                end
                if cd ~= baseCd then
                    cooldownOverrides[spellID] = cd
                end
            elseif baseCd ~= info.cooldown then
                cooldownOverrides[spellID] = baseCd
            end
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
    if myName then currentMembers[myName] = true end
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

--- Apply standard backdrop styling to a frame.
--- @param target table The frame (must inherit BackdropTemplate)
function ns.applyBackdrop(target)
    if not ZaeUI_Shared then return end
    ZaeUI_Shared.applyBackdrop(target)
    local opacity = (ns.db and ns.db.trackerOpacity or 80) / 100
    target:SetAlpha(opacity)
end

-- Main frame and event handling --------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")

local events = {}

function events.ADDON_LOADED(_, addonName)
    if addonName ~= ADDON_NAME then return end
    if not ZaeUI_Shared then
        local msg = "ZaeUI_Shared is required. Install it from CurseForge."
        print(PREFIX .. "Error: " .. msg .. " Addon disabled.")
        C_Timer.After(5, function() UIErrorsFrame:AddMessage("|cffff0000[" .. ADDON_NAME .. "]|r " .. msg, 1, 0.2, 0.2, 1, 5) end)
        return
    end
    C_ChatInfo.RegisterAddonMessagePrefix(COMM_PREFIX)
    initDB()
    ns.scanMySpells()
    ns.rebuildClassColorCache()
    if ns.frameDisplay_Init then ns.frameDisplay_Init() end

    frame:UnregisterEvent("ADDON_LOADED")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    frame:RegisterEvent("UNIT_PET")
    frame:RegisterEvent("GROUP_JOINED")
    frame:RegisterEvent("GROUP_LEFT")

    print(PREFIX .. "Loaded. Type /zdef help for commands.")
end

function events.PLAYER_LOGIN()
    if db.trackerEnabled then
        if not db.trackerHideWhenSolo or ns.isInAnyGroup() then
            showDisplay()
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
    refreshDisplay()
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

function events.GROUP_JOINED()
    if not db then return end
    if not db.trackerEnabled then return end
    if db.trackerHideWhenSolo then
        showDisplay()
    end
end

function events.GROUP_LEFT()
    if not db then return end
    if not db.trackerEnabled then return end
    if db.trackerHideWhenSolo then
        hideDisplay()
    end
end

function events.PLAYER_ENTERING_WORLD()
    ns.scanMySpells()
    ns.rebuildClassColorCache()
    ns.sendSync()
    refreshDisplay()
end

function events.UNIT_SPELLCAST_SUCCEEDED(_, unit, _, spellID)
    if unit ~= "player" and unit ~= "pet" then return end
    if not mySpells[spellID] then return end
    local spellData = ns.spellData
    local info = spellData and spellData[spellID]
    if not info then return end
    -- Use talent-adjusted cooldown if available, otherwise static from SpellData
    local cd = cooldownOverrides[spellID] or info.cooldown
    if cd > 0 then
        local myName = UnitName("player")
        if not myName then return end
        groupData[myName] = groupData[myName] or { spells = {}, cooldowns = {} }
        groupData[myName].cooldowns[spellID] = GetTime() + cd
        ns.sendUsed(spellID, cd)
        C_Timer.After(cd, function()
            ns.sendReady(spellID)
            if groupData[myName] then
                groupData[myName].cooldowns[spellID] = nil
            end
            refreshDisplay()
        end)
        refreshDisplay()
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
            showDisplay()
            print(PREFIX .. "Tracker enabled.")
        else
            hideDisplay()
            print(PREFIX .. "Tracker disabled.")
        end
        if ns.refreshWidgets then ns.refreshWidgets() end
        return
    end

    if msg == "reset" then
        ZaeUI_DefensivesDB = nil
        initDB()
        for k in pairs(mySpells) do mySpells[k] = nil end
        for k in pairs(groupData) do groupData[k] = nil end
        ns.scanMySpells()
        if ns.refreshWidgets then ns.refreshWidgets() end
        refreshDisplay()
        print(PREFIX .. "All settings reset to defaults.")
        return
    end

    if msg == "help" then
        print(PREFIX .. "Usage:")
        print(PREFIX .. "  /zdef - Open the options panel")
        print(PREFIX .. "  /zdef tracker - Toggle the tracker display")
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

-- Mode-aware display routing ------------------------------------------------

refreshDisplay = function()
    if not db then return end
    if not db.trackerEnabled then return end
    if db.displayMode == "anchored" then
        if ns.frameDisplay_RefreshAll then ns.frameDisplay_RefreshAll() end
    else
        if ns.refreshTrackerDisplay then ns.refreshTrackerDisplay() end
    end
end

showDisplay = function()
    if not db then return end
    if not db.trackerEnabled then return end
    if db.displayMode == "anchored" then
        if ns.frameDisplay_RefreshAll then ns.frameDisplay_RefreshAll() end
    else
        if ns.showTrackerDisplay then ns.showTrackerDisplay() end
    end
end

hideDisplay = function()
    if ns.frameDisplay_HideAll then ns.frameDisplay_HideAll() end
    if ns.hideTrackerDisplay then ns.hideTrackerDisplay() end
end

ns.routeRefreshDisplay = refreshDisplay
ns.routeShowDisplay = showDisplay
ns.routeHideDisplay = hideDisplay

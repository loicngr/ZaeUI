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
local GetServerTime = GetServerTime
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
local chargeOverrides = {}   -- talent-adjusted max charges { [spellID] = maxCharges }
local myCharges = {}         -- local player current charges { [spellID] = currentCharges }
local groupData = {}
local syncList = {}
local chargeSyncList = {}

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
    displayStyle = "modern",
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

-- Message queue for retrying failed sends (lockdown / throttle)
local sendQueue = {}
local table_remove = table.remove
local QUEUE_RETRY_INTERVAL = 1
local QUEUE_MAX_AGE = 30

--- Try to send a message, returns true on success (result == 0).
--- @param msg string The message to send
--- @return boolean sent
local function trySend(msg)
    -- Enum.SendAddonMessageResult: 0 = Success
    local result = C_ChatInfo.SendAddonMessage(COMM_PREFIX, msg, getChannel())
    return result == 0
end

--- Flush queued messages that were blocked by lockdown/throttle.
local function flushQueue()
    if #sendQueue == 0 then return end
    local now = GetTime()
    -- Prune expired entries
    local i = 1
    while i <= #sendQueue do
        if now - sendQueue[i].time > QUEUE_MAX_AGE then
            table_remove(sendQueue, i)
        else
            i = i + 1
        end
    end
    -- Try sending from the head
    if not canSendMessage() then return end
    while #sendQueue > 0 do
        if trySend(sendQueue[1].msg) then
            table_remove(sendQueue, 1)
        else
            break
        end
    end
end

local queueFrame = CreateFrame("Frame")
local queueElapsed = 0

local function queueOnUpdate(_, elapsed)
    queueElapsed = queueElapsed + elapsed
    if queueElapsed >= QUEUE_RETRY_INTERVAL then
        queueElapsed = 0
        flushQueue()
        if #sendQueue == 0 then
            queueFrame:SetScript("OnUpdate", nil)
        end
    end
end

--- Safely send an addon message, queuing on lockdown/throttle.
--- @param msg string The message to send
local function safeSend(msg)
    if not canSendMessage() then return end
    if not trySend(msg) then
        sendQueue[#sendQueue + 1] = { msg = msg, time = GetTime() }
        if #sendQueue == 1 then
            queueElapsed = 0
            queueFrame:SetScript("OnUpdate", queueOnUpdate)
        end
    end
end

--- Send a SYNC message with all tracked spell IDs and charge state.
--- Format: SYNC:id1,id2,id3 or SYNC:id1,id2,id3:C:id1=cur/max,id2=cur/max
function ns.sendSync()
    local n = 0
    for spellID in pairs(mySpells) do
        n = n + 1
        syncList[n] = tostring(spellID)
    end
    for i = n + 1, #syncList do syncList[i] = nil end
    if n == 0 then return end
    -- Build charge section for spells with charges
    local chargeCount = 0
    for spellID in pairs(mySpells) do
        local maxCh = chargeOverrides[spellID]
        if maxCh and maxCh > 1 then
            local curCh = myCharges[spellID] or maxCh
            chargeCount = chargeCount + 1
            chargeSyncList[chargeCount] = spellID .. "=" .. curCh .. "/" .. maxCh
        end
    end
    for i = chargeCount + 1, #chargeSyncList do chargeSyncList[i] = nil end
    if chargeCount > 0 then
        safeSend("SYNC:" .. table_concat(syncList, ",") .. ":C:" .. table_concat(chargeSyncList, ","))
    else
        safeSend("SYNC:" .. table_concat(syncList, ","))
    end
end

--- Send a USED message when a tracked spell is cast.
--- @param spellID number
--- @param cooldown number
--- @param currentCharges number|nil Current charges remaining (nil for non-charge spells)
--- @param maxCharges number|nil Maximum charges (nil for non-charge spells)
function ns.sendUsed(spellID, cooldown, currentCharges, maxCharges)
    local ts = GetServerTime()
    if currentCharges and maxCharges then
        safeSend("USED:" .. spellID .. ":" .. cooldown .. ":" .. currentCharges .. ":" .. maxCharges .. ":" .. ts)
    else
        safeSend("USED:" .. spellID .. ":" .. cooldown .. ":" .. ts)
    end
end

--- Send a READY message when a tracked spell's cooldown ends (or a charge recharges).
--- @param spellID number
--- @param currentCharges number|nil Current charges after recharge (nil for non-charge spells)
--- @param maxCharges number|nil Maximum charges (nil for non-charge spells)
--- @param rechargeDuration number|nil Recharge duration for next charge (nil if fully recharged)
function ns.sendReady(spellID, currentCharges, maxCharges, rechargeDuration)
    if currentCharges and maxCharges then
        if rechargeDuration then
            safeSend("READY:" .. spellID .. ":" .. currentCharges .. ":" .. maxCharges .. ":" .. rechargeDuration)
        else
            safeSend("READY:" .. spellID .. ":" .. currentCharges .. ":" .. maxCharges)
        end
    else
        safeSend("READY:" .. spellID)
    end
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
        groupData[name] = groupData[name] or { spells = {}, cooldowns = {}, charges = {} }
        local spells = groupData[name].spells
        local charges = groupData[name].charges
        for k in pairs(spells) do spells[k] = nil end
        for k in pairs(charges) do charges[k] = nil end
        -- Split spell IDs from charge section (format: ids:C:chargeData)
        local spellSection, chargeSection = payload:match("^(.-)%:C%:(.+)$")
        if not spellSection then spellSection = payload end
        for idStr in spellSection:gmatch("[^,]+") do
            local id = tonumber(idStr)
            if id then spells[id] = true end
        end
        -- Parse charge data if present
        if chargeSection then
            for entry in chargeSection:gmatch("[^,]+") do
                local idStr, curStr, maxStr = entry:match("^(%d+)=(%d+)/(%d+)$")
                local id = tonumber(idStr)
                local cur = tonumber(curStr)
                local max = tonumber(maxStr)
                if id and cur and max then
                    local existing = charges[id]
                    if existing then
                        existing.current = cur
                        existing.max = max
                    else
                        charges[id] = { current = cur, max = max }
                    end
                end
            end
        end
    elseif msgType == "USED" then
        -- Format: spellID:cd[:charges:max]:timestamp (timestamp optional for compat)
        local p1, p2, p3, p4, p5 = strsplit(":", payload)
        local spellID = tonumber(p1)
        local cooldown = tonumber(p2)
        if spellID and cooldown then
            -- Detect format by field count: 3=no charges+ts, 5=charges+ts, 2/4=old compat
            local currentCharges, maxCharges, castTime
            if p5 then
                -- 5 fields: spellID:cd:charges:max:timestamp
                currentCharges = tonumber(p3)
                maxCharges = tonumber(p4)
                castTime = tonumber(p5)
            elseif p4 then
                -- 4 fields: old format spellID:cd:charges:max (no timestamp)
                currentCharges = tonumber(p3)
                maxCharges = tonumber(p4)
            elseif p3 then
                -- 3 fields: spellID:cd:timestamp (no charges)
                castTime = tonumber(p3)
            end
            -- Adjust for delivery delay using server timestamp
            local remaining = cooldown
            if castTime then
                local delay = GetServerTime() - castTime
                if delay > 0 then remaining = cooldown - delay end
            end
            groupData[name] = groupData[name] or { spells = {}, cooldowns = {}, charges = {} }
            if remaining > 0 then
                groupData[name].cooldowns[spellID] = GetTime() + remaining
            end
            if currentCharges and maxCharges then
                local existing = groupData[name].charges[spellID]
                if existing then
                    existing.current = currentCharges
                    existing.max = maxCharges
                else
                    groupData[name].charges[spellID] = { current = currentCharges, max = maxCharges }
                end
            end
        end
    elseif msgType == "READY" then
        local p1, p2, p3, p4 = strsplit(":", payload)
        local spellID = tonumber(p1)
        local currentCharges = tonumber(p2)
        local maxCharges = tonumber(p3)
        local rechargeDuration = tonumber(p4)
        if spellID then
            groupData[name] = groupData[name] or { spells = {}, cooldowns = {}, charges = {} }
            if currentCharges and maxCharges and currentCharges < maxCharges then
                -- Still recharging: update charges and set new cooldown for next charge
                local existing = groupData[name].charges[spellID]
                if existing then
                    existing.current = currentCharges
                    existing.max = maxCharges
                else
                    groupData[name].charges[spellID] = { current = currentCharges, max = maxCharges }
                end
                if rechargeDuration then
                    groupData[name].cooldowns[spellID] = GetTime() + rechargeDuration
                end
            else
                -- Fully recharged: clear cooldown but keep charge data for badge display
                groupData[name].cooldowns[spellID] = nil
                local existing = groupData[name].charges[spellID]
                if existing then
                    existing.current = currentCharges or maxCharges
                    existing.max = maxCharges
                end
            end
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
    for k in pairs(chargeOverrides) do chargeOverrides[k] = nil end
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
            -- Compute max charges (talent-adjusted)
            if info.charges then
                local maxCharges = info.charges
                if info.chargeModifiers then
                    for _, mod in pairs(info.chargeModifiers) do
                        if IsPlayerSpell(mod.talent) then
                            maxCharges = maxCharges + mod.bonus
                        end
                    end
                end
                chargeOverrides[spellID] = maxCharges
                if not myCharges[spellID] then
                    myCharges[spellID] = maxCharges
                end
            end
        end
    end
    -- Detect talent overrides: if a known spell is overridden by a talent
    -- variant that exists in spellData, swap to the override spell ID
    if FindSpellOverrideByID then
        local swaps = {}
        for spellID in pairs(mySpells) do
            local overrideID = FindSpellOverrideByID(spellID)
            if overrideID and overrideID ~= spellID and spellData[overrideID] then
                swaps[#swaps + 1] = { old = spellID, new = overrideID }
            end
        end
        for _, swap in ipairs(swaps) do
            mySpells[swap.old] = nil
            cooldownOverrides[swap.old] = nil
            chargeOverrides[swap.old] = nil
            mySpells[swap.new] = true
            -- Compute cooldown override for the replacement spell
            local info = spellData[swap.new]
            if info then
                local baseCd = info.cooldown
                if currentSpecID and info.cooldownBySpec and info.cooldownBySpec[currentSpecID] then
                    baseCd = info.cooldownBySpec[currentSpecID]
                end
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
                        cooldownOverrides[swap.new] = cd
                    end
                elseif baseCd ~= info.cooldown then
                    cooldownOverrides[swap.new] = baseCd
                end
                -- Compute max charges for the replacement spell
                if info.charges then
                    local maxCharges = info.charges
                    if info.chargeModifiers then
                        for _, mod in pairs(info.chargeModifiers) do
                            if IsPlayerSpell(mod.talent) then
                                maxCharges = maxCharges + mod.bonus
                            end
                        end
                    end
                    chargeOverrides[swap.new] = maxCharges
                    if not myCharges[swap.new] then
                        myCharges[swap.new] = maxCharges
                    end
                end
            end
        end
    end
    local myName = UnitName("player")
    if myName then
        groupData[myName] = groupData[myName] or { spells = {}, cooldowns = {}, charges = {} }
        local spells = groupData[myName].spells
        for k in pairs(spells) do spells[k] = nil end
        for spellID in pairs(mySpells) do
            spells[spellID] = true
        end
        -- Populate charge data for display
        local charges = groupData[myName].charges
        for spellID in pairs(mySpells) do
            local maxCh = chargeOverrides[spellID]
            if maxCh and maxCh > 1 then
                local curCh = myCharges[spellID] or maxCh
                local existing = charges[spellID]
                if existing then
                    existing.current = curCh
                    existing.max = maxCh
                else
                    charges[spellID] = { current = curCh, max = maxCh }
                end
            end
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
--- Cached player-to-className mapping, rebuilt alongside classColorCache.
local classNameCache = {}

--- Rebuild the class color cache from current group roster.
function ns.rebuildClassColorCache()
    for k in pairs(classColorCache) do classColorCache[k] = nil end
    for k in pairs(classNameCache) do classNameCache[k] = nil end
    local numMembers = GetNumGroupMembers()
    local isRaid = IsInRaid()
    local count = isRaid and numMembers or (numMembers - 1)
    for i = 1, count do
        local unit = isRaid and ("raid" .. i) or ("party" .. i)
        local name = UnitName(unit)
        if name and not classColorCache[name] then
            local _, className = UnitClass(unit)
            if className then
                classNameCache[name] = className
                if classColorByClass[className] then
                    classColorCache[name] = classColorByClass[className]
                end
            end
        end
    end
    local myName = UnitName("player")
    if myName and not classColorCache[myName] then
        local _, className = UnitClass("player")
        if className then
            classNameCache[myName] = className
            if classColorByClass[className] then
                classColorCache[myName] = classColorByClass[className]
            end
        end
    end
end

--- Get class color hex string for a player name.
--- @param playerName string
--- @return string hex "rrggbb"
function ns.getClassColorHex(playerName)
    return classColorCache[playerName] or "ffffff"
end

--- Get RAID_CLASS_COLORS entry for a player name.
--- @param playerName string
--- @return table|nil colorEntry RAID_CLASS_COLORS entry with r, g, b fields
function ns.getClassColor(playerName)
    local className = classNameCache[playerName]
    if className then
        return RAID_CLASS_COLORS[className]
    end
    return nil
end

--- Check if the current display style is modern.
--- @return boolean
function ns.isModernStyle()
    return ns.db.displayStyle == "modern"
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

    if db.showLoadMessage then
        print(PREFIX .. "Loaded. Type /zdef help for commands.")
    end
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
    if cd <= 0 then return end
    local myName = UnitName("player")
    if not myName then return end
    groupData[myName] = groupData[myName] or { spells = {}, cooldowns = {}, charges = {} }

    local maxCharges = chargeOverrides[spellID]
    if maxCharges and maxCharges > 1 then
        -- Charge-based spell
        local current = myCharges[spellID]
        if not current then current = maxCharges end
        current = current - 1
        if current < 0 then current = 0 end
        myCharges[spellID] = current

        groupData[myName].cooldowns[spellID] = GetTime() + cd
        ns.sendUsed(spellID, cd, current, maxCharges)

        -- Timer for when this charge recharges
        C_Timer.After(cd, function()
            local newCurrent = (myCharges[spellID] or 0) + 1
            if newCurrent > maxCharges then newCurrent = maxCharges end
            myCharges[spellID] = newCurrent

            if newCurrent >= maxCharges then
                ns.sendReady(spellID, newCurrent, maxCharges)
                if groupData[myName] then
                    groupData[myName].cooldowns[spellID] = nil
                    -- Keep charge data for badge display
                    groupData[myName].charges = groupData[myName].charges or {}
                    local existing = groupData[myName].charges[spellID]
                    if existing then
                        existing.current = newCurrent
                        existing.max = maxCharges
                    else
                        groupData[myName].charges[spellID] = { current = newCurrent, max = maxCharges }
                    end
                end
            else
                -- Still recharging: set new cooldown timer and send rechargeDuration
                ns.sendReady(spellID, newCurrent, maxCharges, cd)
                if groupData[myName] then
                    groupData[myName].cooldowns[spellID] = GetTime() + cd
                    groupData[myName].charges = groupData[myName].charges or {}
                    local existing = groupData[myName].charges[spellID]
                    if existing then
                        existing.current = newCurrent
                        existing.max = maxCharges
                    else
                        groupData[myName].charges[spellID] = { current = newCurrent, max = maxCharges }
                    end
                end
            end
            refreshDisplay()
        end)

        -- Update local groupData charges
        groupData[myName].charges = groupData[myName].charges or {}
        local existing = groupData[myName].charges[spellID]
        if existing then
            existing.current = current
            existing.max = maxCharges
        else
            groupData[myName].charges[spellID] = { current = current, max = maxCharges }
        end
        refreshDisplay()
    else
        -- Normal non-charge spell
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
        for k in pairs(myCharges) do myCharges[k] = nil end
        ns.scanMySpells()
        if ns.refreshWidgets then ns.refreshWidgets() end
        print(PREFIX .. "All settings reset to defaults. Please /reload to apply.")
        return
    end

    if msg == "help" then
        print(PREFIX .. "Usage:")
        print(PREFIX .. "  /zdef - Open the options panel")
        print(PREFIX .. "  /zdef tracker - Toggle the tracker display")
        print(PREFIX .. "  /zdef reset - Reset all settings to defaults")
        print(PREFIX .. "  Display style: Classic or Modern (change in options)")
        return
    end

    print(PREFIX .. "Unknown command. Type /zdef help for usage.")
end

-- Expose to namespace ------------------------------------------------------

ns.mySpells = mySpells
ns.groupData = groupData
ns.chargeOverrides = chargeOverrides
ns.myCharges = myCharges
ns.COMM_PREFIX = COMM_PREFIX
ns.PREFIX = PREFIX
ns.ADDON_NAME = ADDON_NAME
ns.constants = { DEFAULTS = DEFAULTS }
ns.safeSend = safeSend

-- Style-aware dispatchers for floating mode ---------------------------------

--- Show the appropriate floating tracker (classic or modern).
function ns.showTrackerDisplay()
    if ns.isModernStyle() then
        if ns.showModernTrackerDisplay then ns.showModernTrackerDisplay() end
    else
        if ns.showClassicTrackerDisplay then ns.showClassicTrackerDisplay() end
    end
end

--- Hide the appropriate floating tracker (classic or modern).
function ns.hideTrackerDisplay()
    if ns.isModernStyle() then
        if ns.hideModernTrackerDisplay then ns.hideModernTrackerDisplay() end
    else
        if ns.hideClassicTrackerDisplay then ns.hideClassicTrackerDisplay() end
    end
end

--- Toggle the appropriate floating tracker (classic or modern).
function ns.toggleTrackerDisplay()
    if ns.isModernStyle() then
        if ns.toggleModernTrackerDisplay then ns.toggleModernTrackerDisplay() end
    else
        if ns.toggleClassicTrackerDisplay then ns.toggleClassicTrackerDisplay() end
    end
end

--- Switch between classic and modern display styles.
function ns.switchDisplayStyle()
    if ns.hideClassicTrackerDisplay then ns.hideClassicTrackerDisplay() end
    if ns.hideModernTrackerDisplay then ns.hideModernTrackerDisplay() end
    ns.showTrackerDisplay()
end

-- Mode-aware display routing ------------------------------------------------

refreshDisplay = function()
    if not db then return end
    if not db.trackerEnabled then return end
    if db.displayMode == "anchored" and not IsInRaid() then
        if ns.frameDisplay_RefreshAll then ns.frameDisplay_RefreshAll() end
    else
        if ns.isModernStyle() then
            if ns.refreshModernTrackerDisplay then ns.refreshModernTrackerDisplay() end
        else
            if ns.refreshClassicTrackerDisplay then ns.refreshClassicTrackerDisplay() end
        end
    end
end

showDisplay = function()
    if not db then return end
    if not db.trackerEnabled then return end
    if db.displayMode == "anchored" and not IsInRaid() then
        if ns.frameDisplay_RefreshAll then ns.frameDisplay_RefreshAll() end
    else
        ns.showTrackerDisplay()
    end
end

hideDisplay = function()
    if ns.frameDisplay_HideAll then ns.frameDisplay_HideAll() end
    if ns.hideClassicTrackerDisplay then ns.hideClassicTrackerDisplay() end
    if ns.hideModernTrackerDisplay then ns.hideModernTrackerDisplay() end
end

ns.routeRefreshDisplay = refreshDisplay
ns.routeShowDisplay = showDisplay
ns.routeHideDisplay = hideDisplay

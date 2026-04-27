-- ZaeUI_Defensives/Core/Inspector.lua
-- Resolves spec and talents for allied units.
-- Three-level cascade: LibSpecialization (primary) → tooltip lookup (sync
-- fast path) → NotifyInspect (async, rate-limited, cooperates with other addons).
-- luacheck: no self

local _, ns = ...
ns.Core = ns.Core or {}
local Util = ns.Utils and ns.Utils.Util

local Inspector = {}

-- Constants
local INSPECT_INTERVAL = 0.5
local INSPECT_TIMEOUT  = 10
local CACHE_EXPIRY     = 60 * 60 * 24 * 3 -- 3 days

-- State
local specByGUID      = {}   -- guid -> { specID, lastSeen, lastAttempt }
local talentsByName   = {}   -- playerName -> { [talentSpellID] = rank }
local priorityStack   = {}
local requestedUnit   = nil
local isOurInspect    = false
local needUpdate      = true
local inspectStarted  = nil
local callbacks       = {}

-- Lazy spec tooltip map
local tooltipSpecMap = nil

-- ------------------------------------------------------------------
-- Talent string decoding (C_Traits serialization v2)
-- ------------------------------------------------------------------

local function buildTalentToSpellMap(specID)
    if not (C_ClassTalents and C_Traits and Constants and Constants.TraitConsts) then
        return nil
    end
    local configId = Constants.TraitConsts.VIEW_TRAIT_CONFIG_ID
    C_ClassTalents.InitializeViewLoadout(specID, 100)
    C_ClassTalents.ViewLoadout({})
    local configInfo = C_Traits.GetConfigInfo(configId)
    if not configInfo then return nil end

    local m = {}
    for _, treeId in ipairs(configInfo.treeIDs) do
        for _, nodeId in ipairs(C_Traits.GetTreeNodes(treeId)) do
            local node = C_Traits.GetNodeInfo(configId, nodeId)
            if node and node.ID ~= 0 then
                for choiceIdx, entryId in ipairs(node.entryIDs) do
                    local entryInfo = C_Traits.GetEntryInfo(configId, entryId)
                    if node.type == Enum.TraitNodeType.SubTreeSelection then
                        m[node.ID .. "_" .. choiceIdx] = {
                            spellId = -1, maxRank = -1,
                            type = node.type, subTreeID = entryInfo.subTreeID,
                        }
                    end
                    if entryInfo and entryInfo.definitionID then
                        local def = C_Traits.GetDefinitionInfo(entryInfo.definitionID)
                        if def and def.spellID then
                            m[node.ID .. "_" .. choiceIdx] = {
                                spellId = def.spellID, maxRank = node.maxRanks,
                                type = node.type, subTreeID = node.subTreeID,
                            }
                        end
                    end
                end
            end
        end
    end
    return m
end

local function decodeTalent(stream)
    local function readbool(s) return s:ExtractValue(1) == 1 end
    local selected = readbool(stream)
    local rank, choiceIndex = nil, 1
    if selected then
        local purchased = readbool(stream)
        if purchased then
            local notMaxRank = readbool(stream)
            if notMaxRank then
                rank = stream:ExtractValue(6)
            end
            if readbool(stream) then
                choiceIndex = stream:ExtractValue(2) + 1
            end
        end
    end
    return selected, rank, choiceIndex
end

local function decodeTalentString(specID, talentString)
    if not (C_Traits and C_Traits.GetLoadoutSerializationVersion
            and ImportDataStreamMixin and C_ClassTalents
            and CreateAndInitFromMixin) then
        return nil
    end
    local spellMap = buildTalentToSpellMap(specID)
    if not spellMap then return nil end

    local stream = CreateAndInitFromMixin(ImportDataStreamMixin, talentString)
    local version = stream:ExtractValue(8)
    local encodedSpec = stream:ExtractValue(16)
    stream:ExtractValue(128)

    if C_Traits.GetLoadoutSerializationVersion() ~= 2 or version ~= 2 then
        return nil
    end
    if encodedSpec ~= specID then return nil end

    local traitTree = C_ClassTalents.GetTraitTreeForSpec(specID)
    if not traitTree then return nil end

    local records = {}
    local heroChoice
    for _, nodeId in ipairs(C_Traits.GetTreeNodes(traitTree)) do
        local selected, rank, choiceIdx = decodeTalent(stream)
        local spell = spellMap[nodeId .. "_" .. choiceIdx]
        local rec = {
            spellId = spell and spell.spellId or -1,
            selected = selected, rank = rank,
            maxRank = spell and spell.maxRank or nil,
            subTreeId = spell and spell.subTreeID or nil,
            type = spell and spell.type or nil,
        }
        records[#records + 1] = rec
        if rec.type == Enum.TraitNodeType.SubTreeSelection then
            heroChoice = spell and spell.subTreeID
        end
    end

    local talents = {}
    for _, rec in ipairs(records) do
        if rec.subTreeId == nil or rec.subTreeId == heroChoice then
            talents[rec.spellId] = not rec.selected and 0
                or rec.rank or rec.maxRank
        end
    end
    return talents
end

local function Now() return GetTime and GetTime() or 0 end

-- reason is "spec" for an authoritative spec change (Brain must purge stale
-- state) or "talents" for a talents-only respec (Brain only re-seeds).
local function fireSpecChanged(unit, reason)
    for i = 1, #callbacks do
        if Util and Util.SafeCall then
            Util.SafeCall(callbacks[i], unit, reason)
        else
            callbacks[i](unit, reason)
        end
    end
end

local function getFriendlyUnits()
    local units = { "player" }
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    local inRaid = IsInRaid and IsInRaid()
    for i = 1, n do
        units[#units + 1] = inRaid and ("raid" .. i) or ("party" .. i)
    end
    return units
end

local function buildTooltipSpecMap()
    if tooltipSpecMap then return tooltipSpecMap end
    tooltipSpecMap = {}
    if not (GetNumClasses and GetClassInfo and GetNumSpecializationsForClassID
            and GetSpecializationInfoForClassID) then
        return tooltipSpecMap
    end
    for classIdx = 1, GetNumClasses() do
        local className, _, classID = GetClassInfo(classIdx)
        if className and classID then
            for specIdx = 1, GetNumSpecializationsForClassID(classID) do
                local specID, specName = GetSpecializationInfoForClassID(classID, specIdx)
                if specID and specName then
                    tooltipSpecMap[specName .. " " .. className] = specID
                end
            end
        end
    end
    return tooltipSpecMap
end

local function specFromTooltip(unit)
    if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then return nil end
    local data = C_TooltipInfo.GetUnit(unit)
    if not data then return nil end
    local map = buildTooltipSpecMap()
    for _, line in ipairs(data.lines or {}) do
        if line and line.leftText and Util and not Util.IsSecret(line.leftText) then
            local id = map[line.leftText]
            if id then return id end
        end
    end
    return nil
end

--- Returns the known spec ID for a unit, or nil if still unresolved.
function Inspector:GetSpec(unit)
    if not unit then return nil end

    if unit == "player" then
        if GetSpecialization and GetSpecializationInfo then
            local idx = GetSpecialization()
            if idx then return GetSpecializationInfo(idx) end
        end
        return nil
    end

    local guid = Util and Util.SafeGUID(unit) or nil
    if not guid then return nil end

    local entry = specByGUID[guid]
    if entry and entry.specID then return entry.specID end

    -- Sync fast path via tooltip
    local fromTooltip = specFromTooltip(unit)
    if fromTooltip then
        specByGUID[guid] = { specID = fromTooltip, lastSeen = Now() }
        return fromTooltip
    end

    -- Queue for async inspect
    if not entry then
        priorityStack[#priorityStack + 1] = unit
        needUpdate = true
    end
    return nil
end

function Inspector:GetRoleHint(unit)
    if not unit then return "UNKNOWN" end
    local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
    if role and role ~= "NONE" then
        return role
    end
    return "UNKNOWN"
end

function Inspector:GetTalents(playerName)
    if not playerName then return {} end
    return talentsByName[playerName] or {}
end

function Inspector:RegisterCallback(fn)
    if not fn then return end
    callbacks[#callbacks + 1] = fn
end

--- Re-decodes the local player's talent loadout, invalidates the
--- TalentResolver cache, and notifies listeners with unit "player".
--- Brain re-seeds the player on this notification, picking up freshly
--- toggled requiresTalent / excludeIfTalent gates and the
--- chargeModifiers-derived maxCharges. Triggered by TRAIT_CONFIG_UPDATED.
function Inspector:RebuildPlayerTalents()
    local playerName = Util and Util.SafeNameUnmodified("player")
    if playerName and C_ClassTalents and C_Traits
       and C_ClassTalents.GetActiveConfigID
       and C_Traits.GenerateImportString then
        local configId = C_ClassTalents.GetActiveConfigID()
        if configId then
            local exportStr = C_Traits.GenerateImportString(configId)
            if exportStr then
                local specIdx = GetSpecialization and GetSpecialization()
                local specID = specIdx and GetSpecializationInfo
                    and GetSpecializationInfo(specIdx)
                if specID then
                    local decoded = decodeTalentString(specID, exportStr)
                    if decoded then
                        talentsByName[playerName] = decoded
                    end
                end
            end
        end
    end
    local tr = ns.Core and ns.Core.TalentResolver
    if tr and tr.InvalidateCache then
        tr:InvalidateCache()
    end
    fireSpecChanged("player", "talents")
end

function Inspector:ClearCache()
    for k in pairs(specByGUID) do specByGUID[k] = nil end
    for k in pairs(talentsByName) do talentsByName[k] = nil end
    if ZaeUI_SharedDB then
        if ZaeUI_SharedDB.DefensivesInspectorCache then
            for k in pairs(ZaeUI_SharedDB.DefensivesInspectorCache) do
                ZaeUI_SharedDB.DefensivesInspectorCache[k] = nil
            end
        end
        if ZaeUI_SharedDB.DefensivesTalentCache then
            for k in pairs(ZaeUI_SharedDB.DefensivesTalentCache) do
                ZaeUI_SharedDB.DefensivesTalentCache[k] = nil
            end
        end
    end
end

-- ------------------------------------------------------------------
-- Cooperation with other addons: yield inspects initiated by them.
-- ------------------------------------------------------------------

local function onNotifyInspect(unit)
    -- Called AFTER another addon (or us) invoked NotifyInspect.
    -- If the call didn't come from us, record the unit and don't launch our own.
    if isOurInspect then return end
    requestedUnit = unit
    inspectStarted = Now()
end

local function onClearInspectPlayer()
    -- Slot released — we can take over on next tick.
    requestedUnit = nil
    isOurInspect = false
end

-- ------------------------------------------------------------------
-- Inspect loop
-- ------------------------------------------------------------------

local function ensureEntry(guid)
    -- entries without specID are in-flight and will be re-queued when the
    -- next run loop tick runs; TTL purge at init will clean leftovers.
    local e = specByGUID[guid]
    if not e then
        e = {}
        specByGUID[guid] = e
    end
    return e
end

local function getNextTarget()
    while #priorityStack > 0 do
        local u = priorityStack[#priorityStack]
        priorityStack[#priorityStack] = nil
        if UnitExists and UnitExists(u) then return u end
    end
    local now = Now()
    local units = getFriendlyUnits()
    -- Pass 1: no cache entry yet
    for _, u in ipairs(units) do
        if UnitIsUnit and not UnitIsUnit(u, "player") then
            local guid = Util and Util.SafeGUID(u)
            if guid and not specByGUID[guid]
               and CanInspect and CanInspect(u)
               and UnitIsConnected and UnitIsConnected(u)
               and UnitIsFriend and UnitIsFriend(u, "player") then
                return u
            end
        end
    end
    -- Pass 2: stale entries
    for _, u in ipairs(units) do
        if UnitIsUnit and not UnitIsUnit(u, "player") then
            local guid = Util and Util.SafeGUID(u)
            if guid then
                local e = specByGUID[guid]
                if e and not e.specID
                   and CanInspect and CanInspect(u)
                   and UnitIsConnected and UnitIsConnected(u)
                   and UnitIsFriend and UnitIsFriend(u, "player")
                   and (not e.lastAttempt or (now - e.lastAttempt) > 60) then
                    return u
                end
            end
        end
    end
    return nil
end

local function runLoop()
    C_Timer.After(INSPECT_INTERVAL, runLoop)

    -- Respect in-combat lockdown: no inspects in combat
    if InCombatLockdown and InCombatLockdown() then return end

    local now = Now()
    if requestedUnit and inspectStarted and (now - inspectStarted) < INSPECT_TIMEOUT then
        return
    end
    if requestedUnit then
        -- Timeout
        if isOurInspect and ClearInspectPlayer then ClearInspectPlayer() end
        requestedUnit = nil
        isOurInspect = false
    end
    if not needUpdate then return end

    local unit = getNextTarget()
    if not unit then
        needUpdate = false
        return
    end

    local guid = Util and Util.SafeGUID(unit)
    if not guid then return end
    local e = ensureEntry(guid)
    e.lastAttempt = now

    if ClearInspectPlayer then ClearInspectPlayer() end
    isOurInspect = true
    if NotifyInspect then NotifyInspect(unit) end
    inspectStarted = now
    requestedUnit = unit
end

-- ------------------------------------------------------------------
-- Init
-- ------------------------------------------------------------------

function Inspector:Init()
    if not (CanInspect and NotifyInspect and ClearInspectPlayer and GetInspectSpecialization) then
        return
    end

    -- Persist spec cache in the shared DB (initialized by ZaeUI_Shared)
    if ZaeUI_SharedDB and ZaeUI_SharedDB.DefensivesInspectorCache then
        specByGUID = ZaeUI_SharedDB.DefensivesInspectorCache
        -- Purge expired entries
        local now = Now()
        for guid, entry in pairs(specByGUID) do
            if not entry or type(entry) ~= "table" or not entry.lastSeen
               or (now - entry.lastSeen) > CACHE_EXPIRY then
                specByGUID[guid] = nil
            end
        end
    end
    if ZaeUI_SharedDB and ZaeUI_SharedDB.DefensivesTalentCache then
        talentsByName = ZaeUI_SharedDB.DefensivesTalentCache
    end

    -- Cooperate with other addons' inspects
    if hooksecurefunc then
        hooksecurefunc("NotifyInspect", onNotifyInspect)
        hooksecurefunc("ClearInspectPlayer", onClearInspectPlayer)
    end

    -- LibSpecialization: primary source of allied specs + talents
    local libSpec = LibStub and LibStub("LibSpecialization", true)
    if libSpec and libSpec.RegisterGroup then
        libSpec.RegisterGroup(Inspector, function(specID, _, _, playerName, talentString)
            if not (specID and playerName) then return end
            -- Resolve guid from the current roster (match by name)
            for _, u in ipairs(getFriendlyUnits()) do
                local n = Util and Util.SafeNameUnmodified(u)
                if n == playerName then
                    local g = Util and Util.SafeGUID(u)
                    if g then
                        specByGUID[g] = { specID = specID, lastSeen = Now() }
                        fireSpecChanged(u, "spec")
                    end
                    break
                end
            end
            if talentString and specID then
                local decoded = decodeTalentString(specID, talentString)
                if decoded then
                    talentsByName[playerName] = decoded
                end
            end
            -- Cross-module invalidation: TalentResolver must drop cached
            -- resolutions derived from the previous talent set.
            local tr = ns.Core and ns.Core.TalentResolver
            if tr and tr.InvalidateCache then
                tr:InvalidateCache()
            end
        end)
    end

    -- React to INSPECT_READY and related events
    local events = CreateFrame("Frame")
    events:SetScript("OnEvent", function(_, event, arg1)
        if event == "INSPECT_READY" then
            if requestedUnit then
                local specID = GetInspectSpecialization and GetInspectSpecialization(requestedUnit)
                if specID and specID > 0 then
                    local guid = Util and Util.SafeGUID(requestedUnit)
                    if guid then
                        local e = ensureEntry(guid)
                        local before = e.specID
                        e.specID = specID
                        e.lastSeen = Now()
                        if before ~= specID then fireSpecChanged(requestedUnit, "spec") end
                    end
                end
                if isOurInspect and ClearInspectPlayer then ClearInspectPlayer() end
                requestedUnit = nil
                isOurInspect = false
            end
        elseif event == "GROUP_ROSTER_UPDATE" then
            needUpdate = true
        elseif event == "PLAYER_ENTERING_WORLD" then
            for k in pairs(priorityStack) do priorityStack[k] = nil end
            needUpdate = true
        elseif event == "PLAYER_SPECIALIZATION_CHANGED" and arg1 then
            local guid = Util and Util.SafeGUID(arg1)
            if guid then
                specByGUID[guid] = nil
                needUpdate = true
                local tr = ns.Core and ns.Core.TalentResolver
                if tr and tr.InvalidateCache then
                    tr:InvalidateCache()
                end
                fireSpecChanged(arg1, "spec")
            end
        elseif event == "TRAIT_CONFIG_UPDATED" then
            Inspector:RebuildPlayerTalents()
        end
    end)
    events:RegisterEvent("INSPECT_READY")
    events:RegisterEvent("GROUP_ROSTER_UPDATE")
    events:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("TRAIT_CONFIG_UPDATED")

    runLoop()
end

ns.Core.Inspector = Inspector
return Inspector

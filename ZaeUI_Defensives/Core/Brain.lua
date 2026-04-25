-- ZaeUI_Defensives/Core/Brain.lua
-- Detects defensive cooldown usage and pushes entries into CooldownStore.
--
-- Detection paths:
--   1. Local cast (UNIT_SPELLCAST_SUCCEEDED on "player") — instant, reliable.
--   2. Aura tracking + evidence — records buff start time on any party unit,
--      collects concurrent evidence (UnitFlags, Shield, Debuff), then on
--      removal matches against SpellData using duration + evidence to identify
--      the spell and compute remaining cooldown.
--   3. Deferred backfill — 0.15s after aura add, re-collects evidence for
--      events that arrived slightly after UNIT_AURA.
--
-- Pure functions (MatchAuraToSpell) are covered by hors-WoW tests.
-- luacheck: no self

local _, ns = ...
ns.Core = ns.Core or {}
local Util = ns.Utils and ns.Utils.Util

local Brain = {}

local Store, TR, Inspector, AuraWatcher

local function debugPrint(...)
    if ZaeUI_DefensivesDB and ZaeUI_DefensivesDB.debug then
        print("|cff88ccff[ZaeDef:Brain]|r", ...)
    end
end

local DEBOUNCE_WINDOW = 0.1
local lastDetection = {}

local function isDebounced(guid, spellID, now)
    local byGUID = lastDetection[guid]
    if byGUID and byGUID[spellID] and (now - byGUID[spellID]) < DEBOUNCE_WINDOW then
        return true
    end
    return false
end

local function markDetected(guid, spellID, now)
    local byGUID = lastDetection[guid]
    if not byGUID then
        byGUID = {}
        lastDetection[guid] = byGUID
    end
    byGUID[spellID] = now
end

-- Tracked aura instances: unit -> { [auraInstanceID] = { startTime, spellID?, auraType?, evidence? } }
local trackedAuras = {}

-- Duration matching tolerance (seconds).
local DURATION_TOLERANCE = 0.5

-- Evidence collection window (seconds).
local EVIDENCE_WINDOW = 0.15

-- Reverse lookup: spell name -> list of spellIDs. Built once at Init.
local spellsByName = {}

-- ------------------------------------------------------------------
-- Evidence system
-- ------------------------------------------------------------------

local lastUnitFlagsTime = {}
local lastFeignDeathTime = {}
local lastFeignDeathState = {}
local lastShieldTime = {}
local lastDebuffTime = {}
local lastCastTime = {}
local unitCanFeign = {}

local function buildEvidenceSet(unit, detectionTime)
    local ev = nil
    if lastDebuffTime[unit] and math.abs(lastDebuffTime[unit] - detectionTime) <= EVIDENCE_WINDOW then
        ev = ev or {}
        ev.Debuff = true
    end
    if lastShieldTime[unit] and math.abs(lastShieldTime[unit] - detectionTime) <= EVIDENCE_WINDOW then
        ev = ev or {}
        ev.Shield = true
    end
    if lastFeignDeathTime[unit] and math.abs(lastFeignDeathTime[unit] - detectionTime) <= EVIDENCE_WINDOW then
        ev = ev or {}
        ev.FeignDeath = true
    elseif lastUnitFlagsTime[unit] and math.abs(lastUnitFlagsTime[unit] - detectionTime) <= EVIDENCE_WINDOW then
        ev = ev or {}
        ev.UnitFlags = true
    end
    if lastCastTime[unit] and math.abs(lastCastTime[unit] - detectionTime) <= EVIDENCE_WINDOW then
        ev = ev or {}
        ev.Cast = true
    end
    return ev
end

local function evidenceMatchesReq(req, evidence)
    if req == nil then return true end
    if req == false then return true end
    if not evidence then return false end
    if type(req) == "string" then return evidence[req] == true end
    if type(req) == "table" then
        for _, key in ipairs(req) do
            if not evidence[key] then return false end
        end
        return true
    end
    return true
end

-- Filter-based aura classification (secret-safe, works in M+).
local DEFENSIVE_FILTERS = {
    { filter = "HELPFUL|EXTERNAL_DEFENSIVE", category = "External" },
    { filter = "HELPFUL|BIG_DEFENSIVE",      category = "Personal" },
    { filter = "HELPFUL|IMPORTANT",          category = "Personal" },
}

local function classifyAura(unit, auraInstanceID)
    if not (Util and Util.AuraMatchesFilter) then return nil end
    for _, entry in ipairs(DEFENSIVE_FILTERS) do
        if Util.AuraMatchesFilter(unit, auraInstanceID, entry.filter) then
            return entry.category
        end
    end
    return nil
end

-- ------------------------------------------------------------------
-- Pure functions (tested hors-WoW)
-- ------------------------------------------------------------------

function Brain.MatchAuraToSpell(spellID, unitClass, unitSpec, _unitRace, matchMode)
    local info = ns.SpellData and ns.SpellData[spellID]
    if not info then return false, "no spelldata" end
    if not info.class then return false, "no class" end

    if matchMode == "target" then
        return true, "target"
    end

    if unitClass ~= info.class then return false, "class mismatch" end

    if info.specs then
        if unitSpec == nil then
            return false, "spec unknown (conservative skip)"
        end
        local found = false
        for _, s in ipairs(info.specs) do
            if s == unitSpec then found = true; break end
        end
        if not found then return false, "spec not in allowed list" end
    end

    return true, "match"
end

-- ------------------------------------------------------------------
-- Cooldown commit helper
-- ------------------------------------------------------------------

local function commitCooldown(casterGUID, casterUnit, spellID, info, startedAt, buffDuration)
    if not casterGUID then return end
    local now = GetTime and GetTime() or 0
    if isDebounced(casterGUID, spellID, now) then return end
    markDetected(casterGUID, spellID, now)

    local cd, maxCharges, effID
    if TR then cd, maxCharges, effID = TR:Resolve(casterUnit or "player", spellID) end
    if not cd or cd == 0 then cd = info.cooldown or 0 end
    if not maxCharges then maxCharges = info.charges or 1 end
    if not effID then effID = spellID end

    local casterName = Util and Util.SafeNameUnmodified(casterUnit or "player") or nil
    local _, classToken = UnitClass(casterUnit or "player")
    local spec = Inspector and Inspector:GetSpec(casterUnit or "player") or nil
    local role = Inspector and Inspector:GetRoleHint(casterUnit or "player") or "UNKNOWN"

    debugPrint("CD start:", info.name, "caster=", casterName,
               "class=", classToken, "cd=", cd, "buffDur=", buffDuration)

    if Store then
        Store:StartCooldown(casterGUID, effID, {
            name = casterName, class = classToken, spec = spec,
            role = role,
            startedAt = startedAt, duration = cd,
            maxCharges = maxCharges,
            buffStartedAt = startedAt,
            buffDuration = buffDuration,
            buffActive = buffDuration > 0,
            effectiveID = effID,
            source = "aura",
        })
    end
end

-- ------------------------------------------------------------------
-- Local cast path (UNIT_SPELLCAST_SUCCEEDED on "player")
-- ------------------------------------------------------------------

local function onLocalCast(spellID)
    if not spellID then return end
    local info = ns.SpellData and ns.SpellData[spellID]
    if not info then return end
    local now = GetTime and GetTime() or 0
    debugPrint("Local cast:", info.name, "(", spellID, ")")

    lastCastTime["player"] = now

    local playerGUID = Util and Util.SafeGUID("player") or nil
    commitCooldown(playerGUID, "player", spellID, info, now, info.duration or 0)
end

-- ------------------------------------------------------------------
-- Aura tracking path (remote detection)
-- ------------------------------------------------------------------

local function isExternalSpell(info)
    return info.category == "External"
end

local function findSpellByNameAndClass(auraName, unitClass)
    local candidates = spellsByName[auraName]
    if not candidates then return nil, nil end
    for _, spellID in ipairs(candidates) do
        local info = ns.SpellData[spellID]
        if info then
            if isExternalSpell(info) then
                return spellID, info
            end
            if info.class == unitClass then
                return spellID, info
            end
        end
    end
    return nil, nil
end

local function durationMatches(measuredDuration, info)
    local expected = info.duration or 0
    if expected <= 0 then return false end
    if info.minDuration then
        return measuredDuration >= expected - DURATION_TOLERANCE
    end
    if info.canCancelEarly then
        return measuredDuration <= expected + DURATION_TOLERANCE
    end
    return math.abs(measuredDuration - expected) <= DURATION_TOLERANCE
end

local function matchByDuration(measuredDuration, unitClass, unitSpec, category, evidence)
    local bestSpellID, bestInfo, bestDelta
    for spellID, info in pairs(ns.SpellData or {}) do
        if info.class == unitClass then
            local skip
            if category then
                skip = info.category ~= category
            else
                skip = isExternalSpell(info)
            end
            if not skip and info.specs and unitSpec then
                skip = true
                for _, s in ipairs(info.specs) do
                    if s == unitSpec then skip = false; break end
                end
            end
            if not skip and not evidenceMatchesReq(info.requiresEvidence, evidence) then
                skip = true
            end
            if not skip and durationMatches(measuredDuration, info) then
                local expected = info.duration or 0
                local delta = math.abs(measuredDuration - expected)
                if not bestDelta or delta < bestDelta then
                    bestSpellID, bestInfo, bestDelta = spellID, info, delta
                end
            end
        end
    end
    return bestSpellID, bestInfo
end

-- ------------------------------------------------------------------
-- External attribution: find the caster among group candidates
-- ------------------------------------------------------------------

local function tryAttributeExternal(targetUnit, spellID, info, startedAt, measuredDuration)
    local units = {}
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    local inRaid = IsInRaid and IsInRaid()
    units[#units + 1] = "player"
    if inRaid then
        for i = 1, n do
            units[#units + 1] = "raid" .. i
        end
    else
        for i = 1, n - 1 do
            units[#units + 1] = "party" .. i
        end
    end

    local bestUnit, bestGUID
    for _, u in ipairs(units) do
        if u ~= targetUnit then
            local _, classToken = UnitClass(u)
            if classToken and info.class == classToken then
                local spec = Inspector and Inspector:GetSpec(u) or nil
                if Brain.MatchAuraToSpell(spellID, classToken, spec, nil, "caster") then
                    local guid = Util and Util.SafeGUID(u) or nil
                    if guid then
                        if not bestGUID then
                            bestUnit, bestGUID = u, guid
                        else
                            bestUnit, bestGUID = nil, nil
                            break
                        end
                    end
                end
            end
        end
    end
    if bestGUID then
        debugPrint("External attribution:", info.name, "→", bestUnit)
        commitCooldown(bestGUID, bestUnit, spellID, info, startedAt, measuredDuration)
    end
end

-- ------------------------------------------------------------------
-- Aura add / remove handlers
-- ------------------------------------------------------------------

local function onAuraAdded(unit, aura)
    local auraInstanceID = Util and Util.SafeAuraField(aura, "auraInstanceID") or nil
    if not auraInstanceID then return end

    local now = GetTime and GetTime() or 0
    local spellID = Util and Util.SafeAuraField(aura, "spellId") or nil
    local auraName = Util and Util.SafeAuraField(aura, "name") or nil

    local isKnown = spellID and ns.SpellData and ns.SpellData[spellID]
    if not isKnown and auraName then
        local _, classToken = UnitClass(unit)
        local candidate = findSpellByNameAndClass(auraName, classToken)
        if candidate then
            spellID = candidate
            isKnown = true
        end
    end

    local auraType = classifyAura(unit, auraInstanceID)

    if not isKnown and not auraType then return end

    debugPrint("Track aura:", auraInstanceID, "on", unit,
               "spell=", tostring(spellID), "name=", tostring(auraName),
               "type=", tostring(auraType))

    trackedAuras[unit] = trackedAuras[unit] or {}
    trackedAuras[unit][auraInstanceID] = {
        startTime = now,
        spellID = spellID,
        auraName = auraName,
        auraType = auraType,
        evidence = buildEvidenceSet(unit, now),
    }
end

local function recordDebuffEvidence(unit, updateInfo)
    if not updateInfo or updateInfo.isFullUpdate then return end
    if not updateInfo.addedAuras then return end
    for _, aura in ipairs(updateInfo.addedAuras) do
        local aid = Util and Util.SafeAuraField(aura, "auraInstanceID") or nil
        if aid then
            local isHarmful = Util and Util.AuraMatchesFilter
                and Util.AuraMatchesFilter(unit, aid, "HARMFUL")
            if isHarmful then
                lastDebuffTime[unit] = GetTime and GetTime() or 0
                return
            end
        end
    end
end

local function onAuraRemoved(unit, auraInstanceID)
    local unitAuras = trackedAuras[unit]
    if not unitAuras then return end
    local tracked = unitAuras[auraInstanceID]
    if not tracked then return end
    unitAuras[auraInstanceID] = nil

    local now = GetTime and GetTime() or 0
    local measuredDuration = now - tracked.startTime
    local _, classToken = UnitClass(unit)
    local spec = Inspector and Inspector:GetSpec(unit) or nil
    local guid = Util and Util.SafeGUID(unit) or nil
    if not guid then return end

    local evidence = tracked.evidence or buildEvidenceSet(unit, tracked.startTime)

    local spellID = tracked.spellID
    local info = spellID and ns.SpellData and ns.SpellData[spellID] or nil

    if info and not evidenceMatchesReq(info.requiresEvidence, evidence) then
        info = nil
        spellID = nil
    end

    if not info and classToken then
        spellID, info = matchByDuration(measuredDuration, classToken, spec, tracked.auraType, evidence)
        if spellID then
            debugPrint("Duration match:", info.name, "measured=", format("%.1f", measuredDuration),
                       "expected=", info.duration, "type=", tostring(tracked.auraType), "on", unit)
        end
    end
    if not info then return end

    if isExternalSpell(info) then
        tryAttributeExternal(unit, spellID, info, tracked.startTime, measuredDuration)
        return
    end

    commitCooldown(guid, unit, spellID, info, tracked.startTime, measuredDuration)
    if Store then Store:EndBuff(guid, spellID) end
end

local function onAuraChanged(unit, updateInfo)
    if not updateInfo then return end

    recordDebuffEvidence(unit, updateInfo)

    local hasAdded = updateInfo.addedAuras and #updateInfo.addedAuras > 0
    local hasRemoved = updateInfo.removedAuraInstanceIDs
                       and #updateInfo.removedAuraInstanceIDs > 0

    if updateInfo.isFullUpdate or hasAdded or hasRemoved then
        debugPrint("UNIT_AURA:", unit,
                   "full=", tostring(updateInfo.isFullUpdate),
                   "added=", hasAdded and #updateInfo.addedAuras or 0,
                   "removed=", hasRemoved and #updateInfo.removedAuraInstanceIDs or 0)
    end

    if updateInfo.isFullUpdate then
        if AuraUtil and AuraUtil.ForEachAura then
            AuraUtil.ForEachAura(unit, "HELPFUL", nil, function(auraData)
                onAuraAdded(unit, auraData)
                return false
            end, true)
        end
        return
    end

    if updateInfo.addedAuras then
        for _, aura in ipairs(updateInfo.addedAuras) do
            onAuraAdded(unit, aura)
        end
    end
    if updateInfo.removedAuraInstanceIDs then
        for _, aid in ipairs(updateInfo.removedAuraInstanceIDs) do
            onAuraRemoved(unit, aid)
        end
    end
end

-- ------------------------------------------------------------------
-- Aura-added fast path: if spellID is readable, start CD immediately
-- ------------------------------------------------------------------

local function tryImmediateDetection(unit, aura)
    local spellID = Util and Util.SafeAuraField(aura, "spellId") or nil

    if spellID then
        local info = ns.SpellData and ns.SpellData[spellID]
        if not info then return end

        local guid = Util and Util.SafeGUID(unit) or nil
        if not guid then return end

        if not isExternalSpell(info) then
            local _, classToken = UnitClass(unit)
            local spec = Inspector and Inspector:GetSpec(unit) or nil
            if Brain.MatchAuraToSpell(spellID, classToken, spec, nil, "caster") then
                local now = GetTime and GetTime() or 0
                commitCooldown(guid, unit, spellID, info, now, info.duration or 0)
            end
            return
        end

        local sourceUnit = Util and Util.SafeAuraField(aura, "sourceUnit") or nil
        if sourceUnit then
            local sourceGUID = Util and Util.SafeGUID(sourceUnit) or nil
            if sourceGUID then
                local now = GetTime and GetTime() or 0
                commitCooldown(sourceGUID, sourceUnit, spellID, info, now, info.duration or 0)
            end
        end
        return
    end

    -- spellID is secret: classify via filter API, try unique candidate match
    local auraInstanceID = Util and Util.SafeAuraField(aura, "auraInstanceID") or nil
    if not auraInstanceID then return end
    local auraType = classifyAura(unit, auraInstanceID)
    if auraType ~= "Personal" then return end

    local guid = Util and Util.SafeGUID(unit) or nil
    if not guid then return end
    local _, classToken = UnitClass(unit)
    local spec = Inspector and Inspector:GetSpec(unit) or nil
    local evidence = buildEvidenceSet(unit, GetTime and GetTime() or 0)

    local matchID, matchInfo
    local count = 0
    for sid, sinfo in pairs(ns.SpellData or {}) do
        if sinfo.category == "Personal" and sinfo.class == classToken
           and (sinfo.duration or 0) > 0
           and evidenceMatchesReq(sinfo.requiresEvidence, evidence) then
            local specOk = true
            if sinfo.specs and spec then
                specOk = false
                for _, s in ipairs(sinfo.specs) do
                    if s == spec then specOk = true; break end
                end
            end
            if specOk then
                count = count + 1
                matchID, matchInfo = sid, sinfo
            end
        end
    end

    if count == 1 then
        local now = GetTime and GetTime() or 0
        debugPrint("Unique classify match:", matchInfo.name, "on", unit)
        commitCooldown(guid, unit, matchID, matchInfo, now, matchInfo.duration or 0)
    end
end

-- ------------------------------------------------------------------
-- Deferred backfill: re-collect evidence after a short delay
-- ------------------------------------------------------------------

local function deferredBackfill(unit, auraInstanceID)
    local unitAuras = trackedAuras[unit]
    if not unitAuras then return end
    local tracked = unitAuras[auraInstanceID]
    if not tracked then return end
    local freshEvidence = buildEvidenceSet(unit, tracked.startTime)
    if freshEvidence then
        tracked.evidence = tracked.evidence or {}
        for k, v in pairs(freshEvidence) do
            tracked.evidence[k] = v
        end
    end
end

-- ------------------------------------------------------------------
-- Evidence callbacks
-- ------------------------------------------------------------------

local function attachEvidenceToRecentAuras(unit, key, now)
    local unitAuras = trackedAuras[unit]
    if not unitAuras then return end
    for _, tracked in pairs(unitAuras) do
        if math.abs(tracked.startTime - now) <= EVIDENCE_WINDOW then
            tracked.evidence = tracked.evidence or {}
            tracked.evidence[key] = true
        end
    end
end

local function onUnitFlags(unit)
    local now = GetTime and GetTime() or 0
    local canFeign = unitCanFeign[unit]
    if canFeign == nil then
        local _, classToken = UnitClass(unit)
        canFeign = classToken == "HUNTER"
        unitCanFeign[unit] = canFeign
    end
    local isFeign = canFeign and UnitIsFeignDeath and UnitIsFeignDeath(unit) or false
    if isFeign and not lastFeignDeathState[unit] then
        lastFeignDeathTime[unit] = now
        attachEvidenceToRecentAuras(unit, "FeignDeath", now)
    end
    lastFeignDeathState[unit] = isFeign
    if not isFeign then
        lastUnitFlagsTime[unit] = now
        attachEvidenceToRecentAuras(unit, "UnitFlags", now)
    end
end

local function onFeignDeath(_unit)
    -- Handled in onUnitFlags via the feign death state machine.
end

local function onShieldChanged(unit)
    local now = GetTime and GetTime() or 0
    lastShieldTime[unit] = now
    attachEvidenceToRecentAuras(unit, "Shield", now)
end

-- ------------------------------------------------------------------
-- Init
-- ------------------------------------------------------------------

function Brain:Init()
    Store       = ns.Core.CooldownStore
    TR          = ns.Core.TalentResolver
    Inspector   = ns.Core.Inspector
    AuraWatcher = ns.Core.AuraWatcher

    if TR and TR.SetSpecResolver and Inspector and Inspector.GetSpec then
        TR:SetSpecResolver(function(unit) return Inspector:GetSpec(unit) end)
    end
    if TR and TR.SetTalentSource and Inspector and Inspector.GetTalents then
        TR:SetTalentSource(function(unit)
            local name = Util and Util.SafeNameUnmodified(unit) or nil
            return name and Inspector:GetTalents(name) or {}
        end)
    end

    -- Build name → spellID reverse index
    for spellID, info in pairs(ns.SpellData or {}) do
        local name = info.name
        if name then
            spellsByName[name] = spellsByName[name] or {}
            local list = spellsByName[name]
            list[#list + 1] = spellID
        end
    end

    if AuraWatcher and AuraWatcher.RegisterCallback then
        AuraWatcher:RegisterCallback("OnAuraChanged", function(unit, updateInfo)
            onAuraChanged(unit, updateInfo)
            if updateInfo and not updateInfo.isFullUpdate and updateInfo.addedAuras then
                for _, aura in ipairs(updateInfo.addedAuras) do
                    tryImmediateDetection(unit, aura)
                    -- Deferred backfill: re-collect evidence after 0.15s
                    local aid = Util and Util.SafeAuraField(aura, "auraInstanceID") or nil
                    if aid and C_Timer and C_Timer.After then
                        C_Timer.After(EVIDENCE_WINDOW, function()
                            deferredBackfill(unit, aid)
                        end)
                    end
                end
            end
        end)
        AuraWatcher:RegisterCallback("OnLocalCast",      onLocalCast)
        AuraWatcher:RegisterCallback("OnUnitFlags",      onUnitFlags)
        AuraWatcher:RegisterCallback("OnFeignDeath",     onFeignDeath)
        AuraWatcher:RegisterCallback("OnShieldChanged",  onShieldChanged)
    end

    local function seedForUnit(unit)
        local guid = Util and Util.SafeGUID(unit) or nil
        local name = Util and Util.SafeNameUnmodified(unit) or nil
        if not (guid and name) then return end
        local _, classToken = UnitClass(unit)
        if not classToken then return end
        local spec = Inspector and Inspector:GetSpec(unit) or nil
        local race = select(2, UnitRace(unit))

        if Store and Store.RegisterPlayer then
            Store:RegisterPlayer(guid, {
                name = name, class = classToken, spec = spec,
                role = Inspector and Inspector:GetRoleHint(unit) or "UNKNOWN",
            })
        end

        local isLocal = UnitIsUnit and UnitIsUnit(unit, "player")
        local talents = Inspector and Inspector:GetTalents(name) or {}
        local hasTalentData = not isLocal and next(talents) ~= nil

        local eligible = {}
        for spellID, _ in pairs(ns.SpellData or {}) do
            if Brain.MatchAuraToSpell(spellID, classToken, spec, race, "seed") then
                if isLocal then
                    if IsPlayerSpell and IsPlayerSpell(spellID) then
                        eligible[#eligible + 1] = spellID
                    end
                elseif not hasTalentData or talents[spellID] then
                    eligible[#eligible + 1] = spellID
                end
            end
        end
        if Store and Store.SeedKnownSpells then
            Store:SeedKnownSpells(guid, eligible)
        end
    end

    local function seedRoster()
        if C_Timer and C_Timer.After then
            C_Timer.After(0.2, function()
                seedForUnit("player")
                local n = GetNumGroupMembers and GetNumGroupMembers() or 0
                if n <= 1 then return end
                local inRaid = IsInRaid and IsInRaid()
                if inRaid then
                    for i = 1, n do
                        seedForUnit("raid" .. i)
                    end
                else
                    for i = 1, n - 1 do
                        seedForUnit("party" .. i)
                    end
                end
            end)
        end
    end

    local seedFrame = CreateFrame("Frame")
    seedFrame:SetScript("OnEvent", function() seedRoster() end)
    seedFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    seedFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

    if Inspector and Inspector.RegisterCallback then
        Inspector:RegisterCallback(function(unit) seedForUnit(unit) end)
    end
end

ns.Core.Brain = Brain
return Brain

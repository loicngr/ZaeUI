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

local GetTime = GetTime
local UnitClass = UnitClass
local mathAbs = math.abs

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

-- Reverse lookup: castSpellId -> SpellData key. Built once at Init.
local castSpellIdIndex = {}

-- Reverse lookup: class+category -> list of spellIDs. Built once at Init.
local spellsByClassCategory = {}

-- Reverse talent gate indexes. Built once at Init.
local spellsRequiringTalent = {}
local spellsExcludedByTalent = {}

-- Reusable buffer for seedForUnit (avoids per-call allocation).
local seedBuf = {}

-- Snapshot of the last observed roster: unit token -> guid. Used to diff
-- on GROUP_ROSTER_UPDATE so we can purge per-unit and per-guid state when
-- a member leaves or a slot is reassigned to a different player.
local rosterSnapshot = {}

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
    if lastDebuffTime[unit] and mathAbs(lastDebuffTime[unit] - detectionTime) <= EVIDENCE_WINDOW then
        ev = ev or {}
        ev.Debuff = true
    end
    if lastShieldTime[unit] and mathAbs(lastShieldTime[unit] - detectionTime) <= EVIDENCE_WINDOW then
        ev = ev or {}
        ev.Shield = true
    end
    if lastFeignDeathTime[unit] and mathAbs(lastFeignDeathTime[unit] - detectionTime) <= EVIDENCE_WINDOW then
        ev = ev or {}
        ev.FeignDeath = true
    elseif lastUnitFlagsTime[unit] and mathAbs(lastUnitFlagsTime[unit] - detectionTime) <= EVIDENCE_WINDOW then
        ev = ev or {}
        ev.UnitFlags = true
    end
    if lastCastTime[unit] and mathAbs(lastCastTime[unit] - detectionTime) <= EVIDENCE_WINDOW then
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
-- `category` drives the display bucket (External vs Personal). `auraFilter`
-- carries Blizzard's narrower classification (BigDefensive / Important /
-- External) and is used to break duration-match ties when several spells
-- of the same class share the same display category — e.g. on a Vengeance
-- DH, Fiery Brand (BigDefensive 12s) and Metamorphosis (Important 15s)
-- both land in `Personal` but only one filter ever applies to a given aura.
local DEFENSIVE_FILTERS = {
    { filter = "HELPFUL|EXTERNAL_DEFENSIVE", category = "External", auraFilter = "External" },
    { filter = "HELPFUL|BIG_DEFENSIVE",      category = "Personal", auraFilter = "BigDefensive" },
    { filter = "HELPFUL|IMPORTANT",          category = "Personal", auraFilter = "Important" },
}

--- Returns (displayCategory, auraFilter) or nil when no Blizzard filter
--- claims the aura.
local function classifyAura(unit, auraInstanceID)
    if not (Util and Util.AuraMatchesFilter) then return nil end
    for _, entry in ipairs(DEFENSIVE_FILTERS) do
        if Util.AuraMatchesFilter(unit, auraInstanceID, entry.filter) then
            return entry.category, entry.auraFilter
        end
    end
    return nil
end

--- True when a spell's `auraFilter` declaration accepts the aura's actual
--- Blizzard filter. Accepts a string (single filter) or an array of strings
--- so a spell that legitimately surfaces under multiple filters (e.g. some
--- Paladin defensives appearing as both BigDefensive and Important) can be
--- declared with `auraFilter = { "BigDefensive", "Important" }`.
--- A nil declaration on either side disables the gate.
--- @param spellFilter string|table|nil
--- @param auraFilter string|nil
--- @return boolean
local function auraFilterAccepts(spellFilter, auraFilter)
    if not spellFilter or not auraFilter then return true end
    local t = type(spellFilter)
    if t == "string" then
        return spellFilter == auraFilter
    end
    if t == "table" then
        for i = 1, #spellFilter do
            if spellFilter[i] == auraFilter then return true end
        end
        return false
    end
    return true
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
-- Talent gate helpers
-- ------------------------------------------------------------------

local function hasTalent(talentID, talents, defaults)
    if talents and talents[talentID] then return true end
    if defaults and defaults[talentID] then return true end
    return false
end

local function passesTalentGates(info, talents, defaults)
    if info.excludeIfTalent then
        if hasTalent(info.excludeIfTalent, talents, defaults) then
            return false
        end
    end
    if info.requiresTalent then
        if not hasTalent(info.requiresTalent, talents, defaults) then
            return false
        end
    end
    return true
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
        if info.excludeIfTalent and Store.RemoveSpell then
            local list = spellsRequiringTalent[info.excludeIfTalent]
            if list then
                for i = 1, #list do Store:RemoveSpell(casterGUID, list[i]) end
            end
        end
        if info.requiresTalent and Store.RemoveSpell then
            local list = spellsExcludedByTalent[info.requiresTalent]
            if list then
                for i = 1, #list do Store:RemoveSpell(casterGUID, list[i]) end
            end
        end
    end
end

-- ------------------------------------------------------------------
-- Local cast path (UNIT_SPELLCAST_SUCCEEDED on "player")
-- ------------------------------------------------------------------

local function onLocalCast(spellID)
    if not spellID then return end
    local mapped = castSpellIdIndex[spellID]
    if mapped then spellID = mapped end
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
    return mathAbs(measuredDuration - expected) <= DURATION_TOLERANCE
end

local function matchByDuration(measuredDuration, unitClass, unitSpec, category, evidence, talents, defaults, auraFilter)
    local cat = category or "Personal"
    -- For Externals the buff lives on a target whose class doesn't constrain
    -- the caster (a Pal's BoS lands on a Druid, etc.) so we must walk every
    -- class' External list. Personals and Raidwides stay class-scoped.
    local listOfLists = {}
    if cat == "External" then
        for _, byClass in pairs(spellsByClassCategory) do
            if byClass[cat] then listOfLists[#listOfLists + 1] = byClass[cat] end
        end
    else
        local byClass = spellsByClassCategory[unitClass]
        if not byClass then return nil, nil end
        local list = byClass[cat]
        if not list then return nil, nil end
        listOfLists[1] = list
    end

    local bestSpellID, bestInfo, bestDelta, bestHasEvidenceReq
    for _, list in ipairs(listOfLists) do
        for i = 1, #list do
            local spellID = list[i]
            local info = ns.SpellData[spellID]
            if not info then break end
            local skip = false
            -- Talent / spec gates only meaningful for Personals: those are
            -- evaluated against the buffed unit (the caster). For Externals
            -- the caster is unknown at this stage; tryAttributeExternal
            -- enforces the class match in a later pass.
            if cat ~= "External" then
                if not passesTalentGates(info, talents, defaults) then
                    skip = true
                end
                if not skip and info.specs and unitSpec then
                    skip = true
                    for _, s in ipairs(info.specs) do
                        if s == unitSpec then skip = false; break end
                    end
                end
            end
            if not skip and not evidenceMatchesReq(info.requiresEvidence, evidence) then
                skip = true
            end
            -- Aura-filter gate: prevents BigDefensive/Important collisions when
            -- two spells of the same class share a display category but each
            -- only ever applies under one Blizzard filter (e.g. Vengeance DH
            -- Fiery Brand vs Metamorphosis on long Charred Flesh extensions).
            if not skip and not auraFilterAccepts(info.auraFilter, auraFilter) then
                skip = true
            end
            if not skip and durationMatches(measuredDuration, info) then
                local expected = info.duration or 0
                local delta = mathAbs(measuredDuration - expected)
                -- Tie-break: when several class spells share the same duration
                -- (e.g. Pal Prot's Divine Shield, Ardent Defender, GoAK all 8s),
                -- prefer the candidate whose explicit requiresEvidence gate is
                -- satisfied. A spell that demands UnitFlags / Shield / Debuff
                -- and got it is a stronger signal than one with no requirement.
                local hasEvidenceReq = info.requiresEvidence and info.requiresEvidence ~= false
                local replace = false
                if not bestDelta then
                    replace = true
                elseif delta < bestDelta then
                    replace = true
                elseif delta == bestDelta and hasEvidenceReq and not bestHasEvidenceReq then
                    replace = true
                end
                if replace then
                    bestSpellID, bestInfo, bestDelta, bestHasEvidenceReq =
                        spellID, info, delta, hasEvidenceReq
                end
            end
        end
    end
    return bestSpellID, bestInfo
end

-- ------------------------------------------------------------------
-- External attribution: find the caster among group candidates
-- ------------------------------------------------------------------

-- Reused on every external buff: filling the same 21-slot array beats
-- allocating a fresh roster table for every Ironbark / BoP that lands.
local rosterBuf = {}

local function tryAttributeExternal(targetUnit, spellID, info, startedAt, measuredDuration)
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    local inRaid = IsInRaid and IsInRaid()
    local count = 1
    rosterBuf[1] = "player"
    if inRaid then
        for i = 1, n do
            count = count + 1
            rosterBuf[count] = "raid" .. i
        end
    else
        for i = 1, n - 1 do
            count = count + 1
            rosterBuf[count] = "party" .. i
        end
    end
    -- Trim leftover entries from a previously larger roster.
    for i = count + 1, #rosterBuf do rosterBuf[i] = nil end

    -- Pass 1: prefer the candidate whose UNIT_SPELLCAST_SUCCEEDED fired
    -- within the evidence window of this aura's start time. With multiple
    -- Paladins in group, Blessing of Sacrifice / Spellwarding would tie
    -- otherwise — cast evidence breaks the tie when only one candidate
    -- actually cast something near the aura.
    local evidenceUnit, evidenceGUID
    local evidenceCount = 0
    for i = 1, count do
        local u = rosterBuf[i]
        if u ~= targetUnit and lastCastTime[u]
           and mathAbs(lastCastTime[u] - startedAt) <= EVIDENCE_WINDOW then
            local _, classToken = UnitClass(u)
            if classToken and info.class == classToken then
                local spec = Inspector and Inspector:GetSpec(u) or nil
                if Brain.MatchAuraToSpell(spellID, classToken, spec, nil, "caster") then
                    local guid = Util and Util.SafeGUID(u) or nil
                    if guid then
                        evidenceCount = evidenceCount + 1
                        evidenceUnit, evidenceGUID = u, guid
                    end
                end
            end
        end
    end
    if evidenceCount == 1 then
        debugPrint("External attribution (cast evidence):", info.name, "→", evidenceUnit)
        commitCooldown(evidenceGUID, evidenceUnit, spellID, info, startedAt, measuredDuration)
        return
    end

    -- Pass 2: fall back to "single class candidate" attribution.
    local bestUnit, bestGUID
    for i = 1, count do
        local u = rosterBuf[i]
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

    local auraType, auraFilter = classifyAura(unit, auraInstanceID)

    if not isKnown and not auraType then return end

    debugPrint("Track aura:", auraInstanceID, "on", unit,
               "spell=", tostring(spellID), "name=", tostring(auraName),
               "type=", tostring(auraType),
               "filter=", tostring(auraFilter))

    trackedAuras[unit] = trackedAuras[unit] or {}
    trackedAuras[unit][auraInstanceID] = {
        startTime = now,
        spellID = spellID,
        auraName = auraName,
        auraType = auraType,
        auraFilter = auraFilter,
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
        local name = Util and Util.SafeNameUnmodified(unit) or nil
        local talents = name and Inspector and Inspector:GetTalents(name) or nil
        local defaults = spec and ns.DefaultTalents and ns.DefaultTalents[spec] or nil
        spellID, info = matchByDuration(measuredDuration, classToken, spec, tracked.auraType, evidence, talents, defaults, tracked.auraFilter)
        if spellID then
            debugPrint("Duration match:", info.name, "measured=", format("%.1f", measuredDuration),
                       "expected=", info.duration, "type=", tostring(tracked.auraType), "on", unit)
        else
            debugPrint("No duration match: aid=", auraInstanceID,
                       "measured=", format("%.1f", measuredDuration),
                       "type=", tostring(tracked.auraType),
                       "class=", tostring(classToken), "spec=", tostring(spec),
                       "on", unit)
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
        -- Talent overrides: an aura whose spellId is the cast id (e.g. Ice
        -- Cold's button id) must be remapped to its catalog entry. Without
        -- this, the SpellData lookup fails and detection is missed.
        local mapped = castSpellIdIndex[spellID]
        if mapped then spellID = mapped end
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
    local auraType, auraFilter = classifyAura(unit, auraInstanceID)
    if auraType ~= "Personal" then return end

    local guid = Util and Util.SafeGUID(unit) or nil
    if not guid then return end
    local _, classToken = UnitClass(unit)
    local spec = Inspector and Inspector:GetSpec(unit) or nil
    local evidence = buildEvidenceSet(unit, GetTime and GetTime() or 0)
    local unitName = Util and Util.SafeNameUnmodified(unit) or nil
    local talents = unitName and Inspector and Inspector:GetTalents(unitName) or nil
    local defaults = spec and ns.DefaultTalents and ns.DefaultTalents[spec] or nil

    local byClass = spellsByClassCategory[classToken]
    local list = byClass and byClass["Personal"]
    if not list then return end

    -- Two-bucket count: candidates that pass everything (`ready`) vs those
    -- gated only by an unmet requiresEvidence (`pending`). When any pending
    -- candidate exists we hold off on a unique-match commit — its evidence
    -- might still arrive within the deferred-backfill window and would
    -- change which spell wins the comparison. Letting matchByDuration
    -- decide at aura removal (with full evidence) avoids false attributions
    -- like "Holy Pal cast Divine Shield, addon flagged Divine Protection".
    local matchID, matchInfo
    local readyCount, pendingCount = 0, 0
    for i = 1, #list do
        local sid = list[i]
        local sinfo = ns.SpellData[sid]
        -- excludeFromPrediction: spells whose Blizzard filter overlaps with
        -- another that we don't catalog (e.g. Sub Rogue's Shadow Blades is
        -- Important like Shadow Dance) cannot be inferred safely from the
        -- filter alone. Duration-match at removal still resolves them.
        if (sinfo.duration or 0) > 0
           and not sinfo.excludeFromPrediction
           and passesTalentGates(sinfo, talents, defaults)
           and auraFilterAccepts(sinfo.auraFilter, auraFilter) then
            local specOk = true
            if sinfo.specs and spec then
                specOk = false
                for _, s in ipairs(sinfo.specs) do
                    if s == spec then specOk = true; break end
                end
            end
            if specOk then
                if evidenceMatchesReq(sinfo.requiresEvidence, evidence) then
                    readyCount = readyCount + 1
                    matchID, matchInfo = sid, sinfo
                else
                    pendingCount = pendingCount + 1
                end
            end
        end
    end

    if readyCount == 1 and pendingCount == 0 then
        local now = GetTime and GetTime() or 0
        debugPrint("Unique classify match:", matchInfo.name, "on", unit, "filter=", tostring(auraFilter))
        commitCooldown(guid, unit, matchID, matchInfo, now, matchInfo.duration or 0)
    elseif pendingCount > 0 then
        debugPrint("Unique classify deferred (pending evidence): unit=", unit,
                   "filter=", tostring(auraFilter),
                   "ready=", readyCount, "pending=", pendingCount)
    end
end

-- ------------------------------------------------------------------
-- Deferred backfill: re-collect evidence after a short delay
--
-- Scheduling one C_Timer.After per added aura allocates a closure and a
-- timer entry on every UNIT_AURA fire, which adds up sharply on raid pulls.
-- Instead we keep a FIFO queue and a single in-flight timer that drains
-- ready entries and re-schedules itself only when work remains.
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

-- FIFO queue with explicit head/tail indices. Plain `#queue + 1` would be
-- unsafe here: after a partial drain (head > 1) the array has holes at the
-- low end, and the length operator on sparse arrays is undefined in Lua 5.1.
local backfillQueue = {}
local backfillHead = 1
local backfillTail = 0
local backfillScheduled = false

-- Pool of entry tables. Reused so a raid-pull burst of UNIT_AURA fires does
-- not allocate one fresh table per aura. Capacity grows naturally with the
-- worst-case queue depth observed across the session and never shrinks.
local backfillEntryPool = {}

local function acquireEntry(unit, aid, fireAt)
    local n = #backfillEntryPool
    if n > 0 then
        local e = backfillEntryPool[n]
        backfillEntryPool[n] = nil
        e.unit, e.aid, e.fireAt = unit, aid, fireAt
        return e
    end
    return { unit = unit, aid = aid, fireAt = fireAt }
end

local function releaseEntry(e)
    e.unit, e.aid, e.fireAt = nil, nil, 0
    backfillEntryPool[#backfillEntryPool + 1] = e
end

local processBackfillQueue
processBackfillQueue = function()
    backfillScheduled = false
    local now = GetTime and GetTime() or 0
    while backfillHead <= backfillTail and backfillQueue[backfillHead].fireAt <= now do
        local entry = backfillQueue[backfillHead]
        backfillQueue[backfillHead] = nil
        backfillHead = backfillHead + 1
        deferredBackfill(entry.unit, entry.aid)
        releaseEntry(entry)
    end
    -- Empty: reset to keep the array dense (avoids unbounded growth of the
    -- head index over a long session).
    if backfillHead > backfillTail then
        backfillHead, backfillTail = 1, 0
        return
    end
    if C_Timer and C_Timer.After then
        backfillScheduled = true
        local delay = backfillQueue[backfillHead].fireAt - now
        if delay < 0 then delay = 0 end
        C_Timer.After(delay, processBackfillQueue)
    end
end

local function enqueueBackfill(unit, aid)
    if not (C_Timer and C_Timer.After) then return end
    local now = GetTime and GetTime() or 0
    backfillTail = backfillTail + 1
    backfillQueue[backfillTail] = acquireEntry(unit, aid, now + EVIDENCE_WINDOW)
    if not backfillScheduled then
        backfillScheduled = true
        C_Timer.After(EVIDENCE_WINDOW, processBackfillQueue)
    end
end

local function purgeBackfillQueue()
    for i = backfillHead, backfillTail do
        local e = backfillQueue[i]
        if e then
            backfillQueue[i] = nil
            releaseEntry(e)
        end
    end
    backfillHead, backfillTail = 1, 0
    -- Leave backfillScheduled as-is: a stale timer in flight will fire,
    -- find the queue empty, and silently exit.
end

Brain._enqueueBackfill = enqueueBackfill
Brain._backfillQueueLen = function() return backfillTail - backfillHead + 1 end
Brain._purgeBackfillQueue = purgeBackfillQueue

-- ------------------------------------------------------------------
-- Evidence callbacks
-- ------------------------------------------------------------------

local function attachEvidenceToRecentAuras(unit, key, now)
    local unitAuras = trackedAuras[unit]
    if not unitAuras then return end
    for _, tracked in pairs(unitAuras) do
        if mathAbs(tracked.startTime - now) <= EVIDENCE_WINDOW then
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
            local talents = name and Inspector:GetTalents(name) or nil
            if talents and next(talents) then return talents end
            local spec = Inspector and Inspector:GetSpec(unit) or nil
            return spec and ns.DefaultTalents and ns.DefaultTalents[spec] or {}
        end)
    end

    -- Build all reverse indexes from SpellData (once at init)
    for spellID, info in pairs(ns.SpellData) do
        local name = info.name
        if name then
            spellsByName[name] = spellsByName[name] or {}
            local list = spellsByName[name]
            list[#list + 1] = spellID
        end
        if info.castSpellId then
            if type(info.castSpellId) == "table" then
                for _, cid in ipairs(info.castSpellId) do
                    castSpellIdIndex[cid] = spellID
                end
            else
                castSpellIdIndex[info.castSpellId] = spellID
            end
        end
        if info.class and info.category then
            spellsByClassCategory[info.class] = spellsByClassCategory[info.class] or {}
            local byClass = spellsByClassCategory[info.class]
            byClass[info.category] = byClass[info.category] or {}
            local list = byClass[info.category]
            list[#list + 1] = spellID
        end
        if info.requiresTalent then
            spellsRequiringTalent[info.requiresTalent] = spellsRequiringTalent[info.requiresTalent] or {}
            local list = spellsRequiringTalent[info.requiresTalent]
            list[#list + 1] = spellID
        end
        if info.excludeIfTalent then
            spellsExcludedByTalent[info.excludeIfTalent] = spellsExcludedByTalent[info.excludeIfTalent] or {}
            local list = spellsExcludedByTalent[info.excludeIfTalent]
            list[#list + 1] = spellID
        end
    end

    if AuraWatcher and AuraWatcher.RegisterCallback then
        AuraWatcher:RegisterCallback("OnAuraChanged", function(unit, updateInfo)
            onAuraChanged(unit, updateInfo)
            if updateInfo and not updateInfo.isFullUpdate and updateInfo.addedAuras then
                for _, aura in ipairs(updateInfo.addedAuras) do
                    tryImmediateDetection(unit, aura)
                    local aid = Util and Util.SafeAuraField(aura, "auraInstanceID") or nil
                    if aid then enqueueBackfill(unit, aid) end
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
        local defaults = spec and ns.DefaultTalents and ns.DefaultTalents[spec] or nil

        local eligibleN = 0
        local eligibleSet = {}
        for spellID, info in pairs(ns.SpellData) do
            if Brain.MatchAuraToSpell(spellID, classToken, spec, race, "seed") then
                if isLocal then
                    if IsPlayerSpell and IsPlayerSpell(spellID) then
                        eligibleN = eligibleN + 1
                        seedBuf[eligibleN] = spellID
                        eligibleSet[spellID] = true
                    end
                elseif hasTalentData then
                    if talents[spellID] and passesTalentGates(info, talents, nil) then
                        eligibleN = eligibleN + 1
                        seedBuf[eligibleN] = spellID
                        eligibleSet[spellID] = true
                    end
                else
                    if passesTalentGates(info, nil, defaults) then
                        eligibleN = eligibleN + 1
                        seedBuf[eligibleN] = spellID
                        eligibleSet[spellID] = true
                    end
                end
            end
        end
        for i = eligibleN + 1, #seedBuf do seedBuf[i] = nil end
        if Store then
            if Store.SeedKnownSpells then
                Store:SeedKnownSpells(guid, seedBuf)
            end
            if Store.RemoveSpell then
                local toRemove
                for sid in Store:IterateKnownSpells(guid) do
                    if not eligibleSet[sid] then
                        local cd = Store:Get(guid, sid)
                        if cd and cd.source == "seed" then
                            toRemove = toRemove or {}
                            toRemove[#toRemove + 1] = sid
                        end
                    end
                end
                if toRemove then
                    for _, sid in ipairs(toRemove) do
                        Store:RemoveSpell(guid, sid)
                    end
                end
            end
        end
    end

    local function clearUnitState(u)
        trackedAuras[u]       = nil
        lastUnitFlagsTime[u]  = nil
        lastFeignDeathTime[u] = nil
        lastFeignDeathState[u] = nil
        lastShieldTime[u]     = nil
        lastDebuffTime[u]     = nil
        lastCastTime[u]       = nil
        unitCanFeign[u]       = nil
    end

    local function resetState()
        for k in pairs(trackedAuras)       do trackedAuras[k] = nil end
        for k in pairs(lastDetection)      do lastDetection[k] = nil end
        for k in pairs(lastUnitFlagsTime)  do lastUnitFlagsTime[k] = nil end
        for k in pairs(lastFeignDeathTime) do lastFeignDeathTime[k] = nil end
        for k in pairs(lastFeignDeathState) do lastFeignDeathState[k] = nil end
        for k in pairs(lastShieldTime)     do lastShieldTime[k] = nil end
        for k in pairs(lastDebuffTime)     do lastDebuffTime[k] = nil end
        for k in pairs(lastCastTime)       do lastCastTime[k] = nil end
        for k in pairs(unitCanFeign)       do unitCanFeign[k] = nil end
        for k in pairs(rosterSnapshot)     do rosterSnapshot[k] = nil end
        purgeBackfillQueue()
        if Store and Store.Reset then Store:Reset() end
    end

    -- Reusable scratch tables: one diff per GROUP_ROSTER_UPDATE.
    local nextSnapshot = {}
    local guidSeen = {}

    local function onRosterChanged()
        for k in pairs(nextSnapshot) do nextSnapshot[k] = nil end
        for k in pairs(guidSeen)     do guidSeen[k] = nil end

        local function note(u)
            local g = Util and Util.SafeGUID(u) or nil
            if g then
                nextSnapshot[u] = g
                guidSeen[g] = true
            end
        end

        note("player")
        local n = GetNumGroupMembers and GetNumGroupMembers() or 0
        local inRaid = IsInRaid and IsInRaid()
        if inRaid then
            for i = 1, n do note("raid" .. i) end
        elseif n > 1 then
            for i = 1, n - 1 do note("party" .. i) end
        end

        -- Per-unit purge: token vanished, or slot now holds a different GUID.
        for u, prevGuid in pairs(rosterSnapshot) do
            if nextSnapshot[u] ~= prevGuid then
                clearUnitState(u)
            end
        end

        -- Per-GUID purge: player no longer in any roster slot.
        for _, prevGuid in pairs(rosterSnapshot) do
            if not guidSeen[prevGuid] then
                lastDetection[prevGuid] = nil
                if Store and Store.ResetPlayer then Store:ResetPlayer(prevGuid) end
            end
        end

        for k in pairs(rosterSnapshot) do rosterSnapshot[k] = nil end
        for u, g in pairs(nextSnapshot) do rosterSnapshot[u] = g end
    end

    -- Exposed for tests.
    Brain._onRosterChanged = onRosterChanged
    Brain._clearUnitState = clearUnitState
    Brain._rosterSnapshot = rosterSnapshot

    -- GROUP_ROSTER_UPDATE can fire many times within a few hundred ms (every
    -- pet up/down, every group buff). Coalesce all calls within the debounce
    -- window into a single full-roster seed.
    local seedPending = false
    local function seedRoster()
        if seedPending then return end
        if not (C_Timer and C_Timer.After) then return end
        seedPending = true
        C_Timer.After(0.2, function()
            seedPending = false
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
    Brain._seedRoster = seedRoster
    Brain._isSeedPending = function() return seedPending end

    local seedFrame = CreateFrame("Frame")
    seedFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_ENTERING_WORLD" then
            resetState()
        end
        onRosterChanged()
        seedRoster()
    end)
    seedFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    seedFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    seedFrame:RegisterEvent("GROUP_LEFT")

    if Inspector and Inspector.RegisterCallback then
        Inspector:RegisterCallback(function(unit) seedForUnit(unit) end)
    end
end

-- Exposed for tests.
Brain._auraFilterAccepts = auraFilterAccepts
Brain._lastCastTime = lastCastTime

ns.Core.Brain = Brain
return Brain

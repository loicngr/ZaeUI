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

-- Reverse lookup: race -> list of spellIDs (racial defensives). Built once
-- at Init. Racials are not class-bound so they bypass spellsByClassCategory.
local spellsByRace = {}

-- Reverse talent gate indexes. Built once at Init.
local spellsRequiringTalent = {}
local spellsExcludedByTalent = {}

-- Reusable map for seedForUnit (avoids per-call allocation).
-- Shape: { [spellID] = maxCharges } — passed to Store:SeedKnownSpells.
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
-- Two-table cast tracking: lastCastTimeAny[unit] = scalar timestamp drives
-- the boolean "did anything cast in window" used by buildEvidenceSet and
-- caster attribution. lastCastSpellIds["player"] = list of recent { spellID,
-- time } entries powers a negative-signal check on the local player only —
-- under 12.0.5+ remote casts have secret spellIDs, so only the player ever
-- populates the list in production.
local lastCastTimeAny = {}
local lastCastSpellIds = {}
local CAST_SNAPSHOT_WINDOW = 0.5
local MAX_CAST_SNAPSHOT = 8
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
    if lastCastTimeAny[unit] and mathAbs(lastCastTimeAny[unit] - detectionTime) <= EVIDENCE_WINDOW then
        ev = ev or {}
        ev.Cast = true
    end
    return ev
end

local function pruneCastSnapshot(unit, now)
    local list = lastCastSpellIds[unit]
    if not list then return nil end
    local n = #list
    -- Drop entries older than the snapshot window. List is time-ordered
    -- (insertion order), so we can stop at the first in-window entry.
    local firstKeep = n + 1
    for i = 1, n do
        if (now - list[i].time) <= CAST_SNAPSHOT_WINDOW then
            firstKeep = i
            break
        end
    end
    if firstKeep > 1 then
        local w = 0
        for i = firstKeep, n do
            w = w + 1
            list[w] = list[i]
        end
        for i = w + 1, n do list[i] = nil end
    end
    return list
end

-- Negative signal for the local player: returns true when the snapshot has
-- entries in the cast window AND none of them match the aura we're trying
-- to attribute. An empty (or out-of-window) snapshot returns false — the
-- caller falls back to existing logic without rejecting the candidate.
local function castSnapshotRejects(unit, auraSpellID, detectionTime)
    if not auraSpellID then return false end
    local list = lastCastSpellIds[unit]
    if not list or #list == 0 then return false end
    local sawInWindow = false
    for i = 1, #list do
        local entry = list[i]
        if mathAbs(entry.time - detectionTime) <= CAST_SNAPSHOT_WINDOW then
            sawInWindow = true
            local sid = entry.spellID
            if sid == auraSpellID then return false end
            if castSpellIdIndex[sid] == auraSpellID then return false end
        end
    end
    return sawInWindow
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

function Brain.MatchAuraToSpell(spellID, unitClass, unitSpec, unitRace, matchMode)
    local info = ns.SpellData and ns.SpellData[spellID]
    if not info then return false, "no spelldata" end

    if matchMode == "target" then
        return true, "target"
    end

    if info.class then
        if unitClass ~= info.class then return false, "class mismatch" end
    elseif info.race then
        local r = info.race
        if type(r) == "string" then
            if unitRace ~= r then return false, "race mismatch" end
        elseif type(r) == "table" then
            local hit = false
            for i = 1, #r do
                if r[i] == unitRace then hit = true; break end
            end
            if not hit then return false, "race mismatch" end
        else
            return false, "invalid race field"
        end
    else
        return false, "no class or race"
    end

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

    local cd, maxCharges, effID, resolvedDuration
    if TR then cd, maxCharges, effID, resolvedDuration = TR:Resolve(casterUnit or "player", spellID) end
    if not cd or cd == 0 then cd = info.cooldown or 0 end
    if not maxCharges then maxCharges = info.charges or 1 end
    if not effID then effID = spellID end

    -- Prefer TR-resolved duration (it accounts for talented durationModifiers).
    -- Fall back to the caller-supplied buffDuration when TR has nothing useful
    -- (test harnesses without TR, secret-id paths, etc.); finally to info.duration.
    local effectiveBuffDuration
    if type(resolvedDuration) == "number" and resolvedDuration > 0 then
        effectiveBuffDuration = resolvedDuration
    elseif type(buffDuration) == "number" and buffDuration > 0 then
        effectiveBuffDuration = buffDuration
    else
        effectiveBuffDuration = info.duration or 0
    end

    local casterName = Util and Util.SafeNameUnmodified(casterUnit or "player") or nil
    local _, classToken = UnitClass(casterUnit or "player")
    local spec = Inspector and Inspector:GetSpec(casterUnit or "player") or nil
    local role = Inspector and Inspector:GetRoleHint(casterUnit or "player") or "UNKNOWN"

    debugPrint("CD start:", info.name, "caster=", casterName,
               "class=", classToken, "cd=", cd, "buffDur=", effectiveBuffDuration)

    if Store then
        Store:StartCooldown(casterGUID, effID, {
            name = casterName, class = classToken, spec = spec,
            role = role,
            startedAt = startedAt, duration = cd,
            maxCharges = maxCharges,
            buffStartedAt = startedAt,
            buffDuration = effectiveBuffDuration,
            buffActive = effectiveBuffDuration > 0,
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

    lastCastTimeAny["player"] = now

    local list = lastCastSpellIds["player"]
    if not list then
        list = {}
        lastCastSpellIds["player"] = list
    end
    pruneCastSnapshot("player", now)
    list[#list + 1] = { spellID = spellID, time = now }
    -- Cap the list defensively: a broken event flow must not let it grow
    -- without bound. The cap is well above the worst-case pruned size.
    while #list > MAX_CAST_SNAPSHOT do
        table.remove(list, 1)
    end

    local playerGUID = Util and Util.SafeGUID("player") or nil
    commitCooldown(playerGUID, "player", spellID, info, now, info.duration or 0)
end

-- ------------------------------------------------------------------
-- Aura tracking path (remote detection)
-- ------------------------------------------------------------------

local function isExternalSpell(info)
    return info.category == "External"
end

local function findSpellByNameAndClass(auraName, unitClass, unitRace)
    local candidates = spellsByName[auraName]
    if not candidates then return nil, nil end
    for _, spellID in ipairs(candidates) do
        local info = ns.SpellData[spellID]
        if info then
            if isExternalSpell(info) then
                return spellID, info
            end
            if info.class and info.class == unitClass then
                return spellID, info
            end
            if info.race and unitRace then
                local r = info.race
                if type(r) == "string" then
                    if r == unitRace then return spellID, info end
                elseif type(r) == "table" then
                    for i = 1, #r do
                        if r[i] == unitRace then return spellID, info end
                    end
                end
            end
        end
    end
    return nil, nil
end

local function durationMatches(measuredDuration, expected, info)
    expected = expected or 0
    if expected <= 0 then return false end
    if info.minDuration then
        if measuredDuration < expected - DURATION_TOLERANCE then return false end
        local upper = info.duration or expected
        if info.durationModifiers then
            for i = 1, #info.durationModifiers do
                local m = info.durationModifiers[i]
                if m and m.bonus and m.bonus > 0 then upper = upper + m.bonus end
            end
        end
        if upper < expected then upper = expected end
        return measuredDuration <= upper + DURATION_TOLERANCE
    end
    if info.canCancelEarly then
        return measuredDuration <= expected + DURATION_TOLERANCE
    end
    return mathAbs(measuredDuration - expected) <= DURATION_TOLERANCE
end

-- Module-level parallel buffers for the External caster scaffolding. Filled
-- by buildCasterCandidates and consumed in the same call frame; never read
-- after the calling function returns. Sized for raid (≤40 entries).
local candUnitBuf = {}
local candHasCastBuf = {}

-- Fills candUnitBuf/candHasCastBuf with non-target roster members and a
-- per-unit hasCastEvidence flag (lastCastTimeAny[unit] within
-- EVIDENCE_WINDOW of startedAt). When `negSignalSpellID` is non-nil, the
-- player slot is dropped upfront if the cast snapshot proves they cast
-- something else (negative signal). When nil, callers handle the per-spell
-- negative-signal check inside their own loop. GUID resolution is deferred
-- — callers fetch GUIDs lazily, only after a candidate survives their
-- ranking pass, so a roster scan with zero matching spells costs zero
-- SafeGUID calls.
local function buildCasterCandidates(targetUnit, negSignalSpellID, startedAt)
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    local inRaid = IsInRaid and IsInRaid()
    local count = 0
    local function pushIfEligible(u)
        if u == targetUnit then return end
        if negSignalSpellID and u == "player"
                and castSnapshotRejects("player", negSignalSpellID, startedAt) then
            return
        end
        local hasCast = startedAt and lastCastTimeAny[u]
            and mathAbs(lastCastTimeAny[u] - startedAt) <= EVIDENCE_WINDOW
            or false
        count = count + 1
        candUnitBuf[count] = u
        candHasCastBuf[count] = hasCast
    end
    pushIfEligible("player")
    if inRaid then
        for i = 1, n do pushIfEligible("raid" .. i) end
    else
        for i = 1, n - 1 do pushIfEligible("party" .. i) end
    end
    -- Trim leftover entries from a previously larger roster.
    for i = count + 1, #candUnitBuf do
        candUnitBuf[i] = nil
        candHasCastBuf[i] = nil
    end
    return count
end

local function matchByDuration(measuredDuration, unit, unitClass, unitSpec, category, evidence, talents, defaults, auraFilter, startedAt)
    local cat = category or "Personal"

    -- Bearer-as-caster path. Considers, in order:
    --   1. byClass[unitClass][cat]               — Personal / Raidwide of bearer's class
    --   2. byClass[unitClass].Raidwide           — when cat="Personal" the bearer
    --                                              may also be the caster of a
    --                                              raidwide buff (e.g. Warrior
    --                                              casting Rallying Cry)
    --   3. spellsByRace[unitRace]                — racials are race-keyed and
    --                                              never indexed by class
    -- Then, if no bearer-cast spell matched, walks the roster and tests every
    -- caster's Raidwide list — needed when the bearer is NOT the caster.
    if cat ~= "External" then
        local bestSpellID, bestInfo, bestDelta, bestHasEvidenceReq

        local function tryBearerList(list)
            if not list then return end
            for i = 1, #list do
                local spellID = list[i]
                local info = ns.SpellData[spellID]
                if not info then break end
                local skip = false
                if not passesTalentGates(info, talents, defaults) then skip = true end
                if not skip and info.specs and unitSpec then
                    skip = true
                    for _, s in ipairs(info.specs) do
                        if s == unitSpec then skip = false; break end
                    end
                end
                if not skip and not evidenceMatchesReq(info.requiresEvidence, evidence) then
                    skip = true
                end
                if not skip and not auraFilterAccepts(info.auraFilter, auraFilter) then
                    skip = true
                end
                if not skip then
                    local expected
                    if TR and TR.Resolve then
                        local _, _, _, resolved = TR:Resolve(unit or "player", spellID)
                        if type(resolved) == "number" and resolved > 0 then
                            expected = resolved
                        end
                    end
                    if not expected then expected = info.duration or 0 end
                    if durationMatches(measuredDuration, expected, info) then
                        local delta = mathAbs(measuredDuration - expected)
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
        end

        local byClass = spellsByClassCategory[unitClass]
        if byClass then
            tryBearerList(byClass[cat])
            if cat ~= "Raidwide" then tryBearerList(byClass.Raidwide) end
        end
        local _, unitRace = UnitRace(unit)
        if unitRace and spellsByRace then
            tryBearerList(spellsByRace[unitRace])
        end

        if bestSpellID then return bestSpellID, bestInfo, nil, nil end

        -- Roster Raidwide: bearer is not the caster. Walk every roster
        -- candidate (the bearer is already excluded by buildCasterCandidates)
        -- and score their Raidwide list. Same-class candidates of a
        -- different spec still need this pass — e.g. Holy Pal casting Aura
        -- Mastery while a Prot Pal bears the buff. Cast evidence breaks
        -- ties the same way it does on the External path.
        local rosterCount = buildCasterCandidates(unit, nil, startedAt)
        local bestUnit, bestHasCastEvidence
        for i = 1, rosterCount do
            local u = candUnitBuf[i]
            local hasCast = candHasCastBuf[i]
            local _, casterClass = UnitClass(u)
            if casterClass then
                local byClassU = spellsByClassCategory[casterClass]
                local list = byClassU and byClassU.Raidwide
                if list then
                    for j = 1, #list do
                        local spellID = list[j]
                        local info = ns.SpellData[spellID]
                        if not info then break end
                        local skip = false
                        if not evidenceMatchesReq(info.requiresEvidence, evidence) then
                            skip = true
                        end
                        if not skip and not auraFilterAccepts(info.auraFilter, auraFilter) then
                            skip = true
                        end
                        if not skip and u == "player"
                                and castSnapshotRejects("player", spellID, startedAt) then
                            skip = true
                        end
                        if not skip then
                            local expected
                            if TR and TR.Resolve then
                                local _, _, _, resolved = TR:Resolve(u, spellID)
                                if type(resolved) == "number" and resolved > 0 then
                                    expected = resolved
                                end
                            end
                            if not expected then expected = info.duration or 0 end
                            if durationMatches(measuredDuration, expected, info) then
                                local delta = mathAbs(measuredDuration - expected)
                                local hasEvidenceReq = info.requiresEvidence
                                    and info.requiresEvidence ~= false
                                local replace = false
                                if not bestDelta then
                                    replace = true
                                elseif hasCast and not bestHasCastEvidence then
                                    replace = true
                                elseif hasCast == bestHasCastEvidence then
                                    if delta < bestDelta then
                                        replace = true
                                    elseif delta == bestDelta and hasEvidenceReq
                                            and not bestHasEvidenceReq then
                                        replace = true
                                    end
                                end
                                if replace then
                                    bestSpellID, bestInfo = spellID, info
                                    bestUnit = u
                                    bestDelta = delta
                                    bestHasEvidenceReq = hasEvidenceReq
                                    bestHasCastEvidence = hasCast
                                end
                            end
                        end
                    end
                end
            end
        end

        local bestGUID
        if bestUnit then
            bestGUID = Util and Util.SafeGUID(bestUnit) or nil
            if not bestGUID then
                -- Caster left between scan and commit; drop the cross-unit
                -- pick rather than misattribute on a stale unit token.
                bestSpellID, bestInfo, bestUnit = nil, nil, nil
            end
        end
        return bestSpellID, bestInfo, bestUnit, bestGUID
    end

    -- External path: walk roster, group candidate casters by class, and
    -- resolve duration on the CASTER (talents that extend the buff live on
    -- the caster, not the target). Picks the best (caster, spell) pair via
    -- a stable tie-break: cast evidence > smaller delta > evidence-req.
    -- GUID lookup is deferred until a winner is selected — a 40-man scan
    -- with zero matching Externals costs zero SafeGUID calls.
    local rosterCount = buildCasterCandidates(unit, nil, startedAt)

    local bestSpellID, bestInfo, bestUnit
    local bestDelta, bestHasEvidenceReq, bestHasCastEvidence

    for i = 1, rosterCount do
        local u = candUnitBuf[i]
        local hasCast = candHasCastBuf[i]
        local _, classToken = UnitClass(u)
        if classToken then
            local byClass = spellsByClassCategory[classToken]
            local list = byClass and byClass.External
            if list then
                for j = 1, #list do
                    local spellID = list[j]
                    local info = ns.SpellData[spellID]
                    if not info then break end
                    local skip = false
                    if not evidenceMatchesReq(info.requiresEvidence, evidence) then
                        skip = true
                    end
                    if not skip and not auraFilterAccepts(info.auraFilter, auraFilter) then
                        skip = true
                    end
                    -- Negative signal for the local player: snapshot has
                    -- entries in the cast window but none of them match
                    -- this candidate spellID. The player demonstrably
                    -- cast something else, so they cannot be its caster.
                    if not skip and u == "player"
                            and castSnapshotRejects("player", spellID, startedAt) then
                        skip = true
                    end
                    if not skip then
                        local expected
                        if TR and TR.Resolve then
                            local _, _, _, resolved = TR:Resolve(u, spellID)
                            if type(resolved) == "number" and resolved > 0 then
                                expected = resolved
                            end
                        end
                        if not expected then expected = info.duration or 0 end
                        if durationMatches(measuredDuration, expected, info) then
                            local delta = mathAbs(measuredDuration - expected)
                            local hasEvidenceReq = info.requiresEvidence
                                and info.requiresEvidence ~= false
                            local replace = false
                            if not bestDelta then
                                replace = true
                            elseif hasCast and not bestHasCastEvidence then
                                replace = true
                            elseif hasCast == bestHasCastEvidence then
                                if delta < bestDelta then
                                    replace = true
                                elseif delta == bestDelta and hasEvidenceReq
                                        and not bestHasEvidenceReq then
                                    replace = true
                                end
                            end
                            if replace then
                                bestSpellID, bestInfo = spellID, info
                                bestUnit = u
                                bestDelta = delta
                                bestHasEvidenceReq = hasEvidenceReq
                                bestHasCastEvidence = hasCast
                            end
                        end
                    end
                end
            end
        end
    end

    local bestGUID
    if bestUnit then
        bestGUID = Util and Util.SafeGUID(bestUnit) or nil
        if not bestGUID then
            -- Lost the GUID race (unit left between scan and commit). Drop
            -- the cross-unit pick; self-cast fallback below will reconsider.
            bestSpellID, bestInfo, bestUnit = nil, nil, nil
            bestDelta = nil
        end
    end

    -- Self-cast last-resort fallback: this branch fires when onAuraRemoved
    -- routes through matchByDuration (no spellID known at aura-add time).
    -- Cross-unit casters yielded nothing, but the buffed unit's own class
    -- matches `info.class` (e.g. Disc Priest self-Pain-Suppression,
    -- Mistweaver self-Life-Cocoon). Resolve duration on the target itself
    -- and accept if it matches. Counterpart in tryAttributeExternal Pass 3
    -- covers the path where spellID was already known at aura-add.
    if not bestSpellID then
        local _, targetClass = UnitClass(unit)
        if targetClass then
            local byClass = spellsByClassCategory[targetClass]
            local selfList = byClass and byClass.External
            if selfList then
                local selfGUID = Util and Util.SafeGUID(unit) or nil
                if selfGUID then
                    for j = 1, #selfList do
                        local spellID = selfList[j]
                        local info = ns.SpellData[spellID]
                        if not info then break end
                        local skip = false
                        if not evidenceMatchesReq(info.requiresEvidence, evidence) then
                            skip = true
                        end
                        if not skip and not auraFilterAccepts(info.auraFilter, auraFilter) then
                            skip = true
                        end
                        if not skip then
                            local expected
                            if TR and TR.Resolve then
                                local _, _, _, resolved = TR:Resolve(unit, spellID)
                                if type(resolved) == "number" and resolved > 0 then
                                    expected = resolved
                                end
                            end
                            if not expected then expected = info.duration or 0 end
                            if durationMatches(measuredDuration, expected, info) then
                                local delta = mathAbs(measuredDuration - expected)
                                if not bestDelta or delta < bestDelta then
                                    bestSpellID, bestInfo = spellID, info
                                    bestUnit, bestGUID = unit, selfGUID
                                    bestDelta = delta
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return bestSpellID, bestInfo, bestUnit, bestGUID
end

-- ------------------------------------------------------------------
-- External attribution: find the caster among group candidates
-- ------------------------------------------------------------------

local function tryAttributeExternal(targetUnit, spellID, info, startedAt, measuredDuration)
    local count = buildCasterCandidates(targetUnit, spellID, startedAt)

    -- Pass 1: prefer the candidate whose UNIT_SPELLCAST_SUCCEEDED fired
    -- within the evidence window of this aura's start time. With multiple
    -- Paladins in group, Blessing of Sacrifice / Spellwarding would tie
    -- otherwise — cast evidence breaks the tie when only one candidate
    -- actually cast something near the aura. GUID lookup is deferred to
    -- the single survivor.
    local evidenceUnit
    local evidenceCount = 0
    for i = 1, count do
        if candHasCastBuf[i] then
            local u = candUnitBuf[i]
            local _, classToken = UnitClass(u)
            if classToken and info.class == classToken then
                local spec = Inspector and Inspector:GetSpec(u) or nil
                if Brain.MatchAuraToSpell(spellID, classToken, spec, nil, "caster") then
                    evidenceCount = evidenceCount + 1
                    evidenceUnit = u
                end
            end
        end
    end
    if evidenceCount == 1 then
        local evidenceGUID = Util and Util.SafeGUID(evidenceUnit) or nil
        if evidenceGUID then
            debugPrint("External attribution (cast evidence):", info.name, "→", evidenceUnit)
            commitCooldown(evidenceGUID, evidenceUnit, spellID, info, startedAt, measuredDuration)
            return
        end
    end

    -- Pass 2: fall back to "single class candidate" attribution.
    local bestUnit
    local bestCount = 0
    for i = 1, count do
        local u = candUnitBuf[i]
        local _, classToken = UnitClass(u)
        if classToken and info.class == classToken then
            local spec = Inspector and Inspector:GetSpec(u) or nil
            if Brain.MatchAuraToSpell(spellID, classToken, spec, nil, "caster") then
                bestCount = bestCount + 1
                if bestCount > 1 then
                    bestUnit = nil
                    break
                end
                bestUnit = u
            end
        end
    end
    if bestUnit then
        local bestGUID = Util and Util.SafeGUID(bestUnit) or nil
        if bestGUID then
            debugPrint("External attribution:", info.name, "→", bestUnit)
            commitCooldown(bestGUID, bestUnit, spellID, info, startedAt, measuredDuration)
            return
        end
    end

    -- Pass 3: self-cast last-resort fallback. Fires when onAuraRemoved
    -- already knew tracked.spellID at aura-add and reached
    -- tryAttributeExternal directly (no matchByDuration call). The buffed
    -- unit's class matches `info.class`, so they may have cast the
    -- External on themselves (Disc Priest self-Pain-Suppression, Mistweaver
    -- self-Life-Cocoon, Ret Pal self-BoP). Pass 1 and Pass 2 excluded the
    -- target; here we revisit it once everything else has failed.
    -- Counterpart in matchByDuration External tail covers the path where
    -- spellID was unknown at aura-add and matchByDuration drives matching.
    local _, targetClass = UnitClass(targetUnit)
    if targetClass and info.class == targetClass then
        local targetSpec = Inspector and Inspector:GetSpec(targetUnit) or nil
        if Brain.MatchAuraToSpell(spellID, targetClass, targetSpec, nil, "caster") then
            local selfGUID = Util and Util.SafeGUID(targetUnit) or nil
            if selfGUID then
                debugPrint("External self-cast attribution:", info.name, "→", targetUnit)
                commitCooldown(selfGUID, targetUnit, spellID, info, startedAt, measuredDuration)
            end
        end
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
        local _, unitRace = UnitRace(unit)
        local candidate = findSpellByNameAndClass(auraName, classToken, unitRace)
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

    -- A Raidwide entry whose class does not match the bearer is meant for
    -- a cross-unit caster. Drop the readable-spellID shortcut so the
    -- matchByDuration cross-class path attributes to the right caster
    -- instead of stamping the buff on the bearer.
    if info and info.category == "Raidwide" and info.class
       and classToken and info.class ~= classToken then
        info = nil
        spellID = nil
    end

    local matchedCasterUnit, matchedCasterGUID
    if not info and classToken then
        local name = Util and Util.SafeNameUnmodified(unit) or nil
        local talents = name and Inspector and Inspector:GetTalents(name) or nil
        local defaults = spec and ns.DefaultTalents and ns.DefaultTalents[spec] or nil
        spellID, info, matchedCasterUnit, matchedCasterGUID = matchByDuration(
            measuredDuration, unit, classToken, spec, tracked.auraType,
            evidence, talents, defaults, tracked.auraFilter, tracked.startTime)
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

    -- matchByDuration returns a non-nil caster when it picked a cross-unit
    -- match (External or cross-class Raidwide). Always honor that — it has
    -- already resolved the caster via cast evidence + class match.
    if matchedCasterGUID and matchedCasterUnit then
        commitCooldown(matchedCasterGUID, matchedCasterUnit, spellID, info,
                       tracked.startTime, measuredDuration)
        return
    end

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
            local race = select(2, UnitRace(unit))
            if Brain.MatchAuraToSpell(spellID, classToken, spec, race, "caster") then
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
    -- Two-bucket count: candidates that pass everything (`ready`) vs those
    -- gated only by an unmet requiresEvidence (`pending`). When any pending
    -- candidate exists we hold off on a unique-match commit — its evidence
    -- might still arrive within the deferred-backfill window and would
    -- change which spell wins the comparison. Letting matchByDuration
    -- decide at aura removal (with full evidence) avoids false attributions
    -- like "Holy Pal cast Divine Shield, addon flagged Divine Protection".
    local matchID, matchInfo
    local readyCount, pendingCount = 0, 0
    local function consider(list)
        if not list then return end
        for i = 1, #list do
            local sid = list[i]
            local sinfo = ns.SpellData[sid]
            -- excludeFromPrediction: spells whose Blizzard filter overlaps
            -- with another that we don't catalog (e.g. Sub Rogue's Shadow
            -- Blades is Important like Shadow Dance) cannot be inferred
            -- safely from the filter alone. Duration-match at removal still
            -- resolves them.
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
    end

    if byClass then
        consider(byClass["Personal"])
        consider(byClass.Raidwide)
    end
    local _, unitRace = UnitRace(unit)
    if unitRace and spellsByRace then
        consider(spellsByRace[unitRace])
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
        -- Race-keyed index for racial defensives. info.race is a string for
        -- single-race spells (Stoneform → "Dwarf") or a table when several
        -- races share the same spell. matchByDuration's bearer-cast path
        -- iterates spellsByRace[bearer's race] alongside the per-class lists.
        if info.race then
            local races = info.race
            if type(races) == "string" then
                spellsByRace[races] = spellsByRace[races] or {}
                local raceList = spellsByRace[races]
                raceList[#raceList + 1] = spellID
            elseif type(races) == "table" then
                for k = 1, #races do
                    local r = races[k]
                    spellsByRace[r] = spellsByRace[r] or {}
                    local raceList = spellsByRace[r]
                    raceList[#raceList + 1] = spellID
                end
            end
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

        for k in pairs(seedBuf) do seedBuf[k] = nil end
        local eligibleSet = {}
        local function include(spellID, info, talentsForResolve)
            -- maxCharges resolution priority:
            --   1. TalentResolver when talents are reliable (local player or
            --      remote with inspected data) — picks up chargeModifiers.
            --   2. info.charges base value otherwise (defaults / no data).
            -- A wrong base on the seed self-corrects on the first commitCooldown,
            -- which always re-resolves via TR with the full unit context.
            local mc = info.charges or 1
            if talentsForResolve and TR and TR.Resolve then
                local _, resolved = TR:Resolve(unit, spellID)
                if type(resolved) == "number" and resolved >= 1 then
                    mc = resolved
                end
            end
            seedBuf[spellID] = mc
            eligibleSet[spellID] = true
        end
        -- Returns true if the local player knows the spell. When the catalog
        -- key is the aura ID (different from the cast ID), IsPlayerSpell on
        -- the aura ID returns false, so we probe the castSpellId(s) when
        -- present. castSpellId may be a single number or a list.
        local function localKnowsSpell(info, spellID)
            if not IsPlayerSpell then return false end
            local cast = info.castSpellId
            if cast == nil then
                return IsPlayerSpell(spellID) == true
            end
            if type(cast) == "number" then
                return IsPlayerSpell(cast) == true
            end
            if type(cast) == "table" then
                for i = 1, #cast do
                    if IsPlayerSpell(cast[i]) == true then return true end
                end
            end
            return false
        end
        for spellID, info in pairs(ns.SpellData) do
            if Brain.MatchAuraToSpell(spellID, classToken, spec, race, "seed") then
                if isLocal then
                    if localKnowsSpell(info, spellID) then
                        include(spellID, info, true)
                    end
                elseif hasTalentData then
                    if talents[spellID] and passesTalentGates(info, talents, nil) then
                        include(spellID, info, talents)
                    end
                else
                    if passesTalentGates(info, nil, defaults) then
                        include(spellID, info, nil)
                    end
                end
            end
        end
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
        lastCastTimeAny[u]    = nil
        lastCastSpellIds[u]   = nil
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
        for k in pairs(lastCastTimeAny)    do lastCastTimeAny[k] = nil end
        for k in pairs(lastCastSpellIds)   do lastCastSpellIds[k] = nil end
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

    -- reason "spec" = authoritative spec change: wipe per-unit evidence and
    -- the Store record so source=aura/cast entries from the previous spec do
    -- not survive into the new spec's seed. reason "talents" (or nil for
    -- back-compat 1-arg callers) keeps active CDs and just re-seeds.
    local function onSpecChanged(unit, reason)
        if reason == "spec" then
            clearUnitState(unit)
            local guid = Util and Util.SafeGUID(unit) or nil
            if guid and Store and Store.ResetPlayer then
                Store:ResetPlayer(guid)
            end
        end
        seedForUnit(unit)
    end
    Brain._onSpecChanged = onSpecChanged

    if Inspector and Inspector.RegisterCallback then
        Inspector:RegisterCallback(onSpecChanged)
    end
end

-- Exposed for tests.
Brain._auraFilterAccepts = auraFilterAccepts
Brain._lastCastTime = lastCastTimeAny
Brain._lastCastSpellIds = lastCastSpellIds
Brain._durationMatches = durationMatches
Brain._matchByDuration = matchByDuration

ns.Core.Brain = Brain
return Brain

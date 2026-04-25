-- ZaeUI_Defensives/Core/TalentResolver.lua
-- Resolves (cooldown, maxCharges, effectiveSpellID) per unit per spell,
-- applying talent modifiers, cooldownBySpec, charge modifiers, and override
-- swaps. Cache keyed by {guid, specID, talentsKey}; invalidated by callers.
-- luacheck: no self

local _, ns = ...
ns.Core = ns.Core or {}
local Util = ns.Utils and ns.Utils.Util

local Resolver = {}

-- Injectable sources. In tests, ns.Core.__testTalentSource is wired before
-- module load; in production, Chunk 3 calls SetTalentSource / SetSpecResolver
-- during init to bridge Inspector → Resolver.
local talentSource = ns.Core.__testTalentSource
local specResolver = nil

-- Nested cache: cache[guid][specID][spellID] = { cd, charges, effID, talents }
-- where `talents` is a direct reference to the talent set used to produce the
-- entry. On hit we check `talents` identity: if the Inspector has replaced
-- the player's talent table (e.g. via a LibSpec update — which always assigns
-- a fresh table, see Inspector.lua), identity comparison fails and we
-- recompute. Avoids rebuilding a composite string key per call.
local cache = {}

local function getOrCreateCacheSlot(guid, specID, spellID)
    local byGUID = cache[guid]
    if not byGUID then byGUID = {}; cache[guid] = byGUID end
    local bySpec = byGUID[specID]
    if not bySpec then bySpec = {}; byGUID[specID] = bySpec end
    return bySpec, bySpec[spellID]
end

local function getSpecForUnit(unit)
    if unit == "player" then
        local idx = GetSpecialization and GetSpecialization()
        if idx and GetSpecializationInfo then
            return GetSpecializationInfo(idx)
        end
        return nil
    end
    -- Non-player units resolve via the injected specResolver (wired to
    -- Inspector:GetSpec in Chunk 3). Returns nil if unresolved.
    if specResolver then return specResolver(unit) end
    return nil
end

local function isTalentActive(unit, talentID, talents)
    -- Injected talents (from LibSpec or test source) are authoritative when
    -- provided. IsPlayerSpell is consulted only as fallback for "player"
    -- when the talent source didn't yield the id.
    if talents and talents[talentID] then return true end
    if unit == "player" and IsPlayerSpell then
        return IsPlayerSpell(talentID) == true
    end
    return false
end

--- Resolves the effective cooldown/charges/ID for (unit, spellID).
--- @param unit string
--- @param spellID number
--- @return number cooldown, number maxCharges, number effectiveSpellID
function Resolver:Resolve(unit, spellID)
    local spellData = ns.SpellData
    if not spellData then return 0, 1, spellID end
    local info = spellData[spellID]
    if not info then return 0, 1, spellID end

    -- Avoid string concat for the cache key: use a 2D table indexed by
    -- (guid, specID, spellID). Talent identity is checked via table
    -- reference — Inspector always installs a fresh table on update, so
    -- we don't need to hash its content.
    local guid = (Util and Util.SafeGUID and Util.SafeGUID(unit)) or ("_" .. tostring(unit))
    local specID = getSpecForUnit(unit)
    local talents = talentSource and talentSource(unit) or nil

    local bySpec, cached = getOrCreateCacheSlot(guid, specID or 0, spellID)
    if cached and cached.talents == talents then
        return cached.cd, cached.charges, cached.effID
    end
    -- Use a local `talents` table for isTalentActive — pass nil-safe empty.
    talents = talents or {}

    local cd = info.cooldown or 0
    if info.cooldownBySpec and specID and info.cooldownBySpec[specID] then
        cd = info.cooldownBySpec[specID]
    end

    if info.cdModifiers then
        for _, mod in ipairs(info.cdModifiers) do
            if mod.ranks then
                -- Multi-rank: the FIRST active rank wins. By convention
                -- (enforced by SpellData authors), ranks are ordered
                -- strongest-first so this yields the strongest active reduction.
                for r = 1, #mod.ranks do
                    local rank = mod.ranks[r]
                    if isTalentActive(unit, rank.talent, talents) then
                        cd = cd - rank.reduction
                        break
                    end
                end
            elseif mod.talent and isTalentActive(unit, mod.talent, talents) then
                local reduction = mod.reduction
                if specID and mod.reductionBySpec and mod.reductionBySpec[specID] then
                    reduction = mod.reductionBySpec[specID]
                end
                cd = cd - (reduction or 0)
            end
        end
    end

    local charges = info.charges or 1
    if info.chargeModifiers then
        for _, mod in ipairs(info.chargeModifiers) do
            if mod.talent and isTalentActive(unit, mod.talent, talents) then
                charges = charges + (mod.bonus or 0)
            end
        end
    end

    local effID = spellID
    if info.overrides and FindSpellOverrideByID then
        local override = FindSpellOverrideByID(spellID)
        if override and override ~= spellID then
            for _, allowed in ipairs(info.overrides) do
                if allowed == override then
                    effID = override
                    break
                end
            end
        end
    end

    -- Reuse the existing slot table when possible to avoid allocating on
    -- every miss (the slot may already be present with a stale talents ref).
    local entry = bySpec[spellID]
    if entry then
        entry.cd, entry.charges, entry.effID, entry.talents = cd, charges, effID, talents
    else
        bySpec[spellID] = { cd = cd, charges = charges, effID = effID, talents = talents }
    end
    return cd, charges, effID
end

function Resolver:InvalidateCache()
    for guid in pairs(cache) do cache[guid] = nil end
end

function Resolver:SetTalentSource(fn)
    talentSource = fn
end

function Resolver:SetSpecResolver(fn)
    specResolver = fn
end

ns.Core.TalentResolver = Resolver
return Resolver

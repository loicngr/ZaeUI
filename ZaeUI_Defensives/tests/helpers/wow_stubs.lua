-- Stubs pour APIs WoW manquantes hors jeu. À charger AVANT tout code addon.
local S = {}

-- Clock mockable
S.currentTime = 0
function S.setTime(t) S.currentTime = t end

_G.GetTime = function() return S.currentTime end

-- issecretvalue : retourne false par défaut, test peut forcer via S.secretValues[v]=true
S.secretValues = {}
_G.issecretvalue = function(v) return S.secretValues[v] == true end

-- C_Timer mock : enqueue les callbacks, flushTimers les exécute
S.pendingTimers = {}
_G.C_Timer = {
    After = function(delay, fn)
        S.pendingTimers[#S.pendingTimers + 1] = {
            deadline = S.currentTime + delay,
            fn = fn,
        }
    end,
}

function S.flushTimers(upToTime)
    upToTime = upToTime or S.currentTime
    local ran = 0
    -- Drain loop: re-sort after every execution because callbacks can enqueue
    -- fresh timers via C_Timer.After; they must be picked up within the same
    -- flush if their deadline also falls within upToTime.
    while true do
        table.sort(S.pendingTimers, function(a, b) return a.deadline < b.deadline end)
        local nextT = S.pendingTimers[1]
        if not nextT or nextT.deadline > upToTime then break end
        table.remove(S.pendingTimers, 1)
        local ok, err = pcall(nextT.fn)
        if not ok then
            io.write("timer callback error: " .. tostring(err) .. "\n")
        end
        ran = ran + 1
    end
    return ran
end

-- Roster mock : S.roster[unit] = { guid, name, class, race, spec, role, isFeign }
S.roster = {}
_G.UnitGUID = function(unit)
    return S.roster[unit] and S.roster[unit].guid or nil
end
_G.UnitName = function(unit)
    return S.roster[unit] and S.roster[unit].name or nil
end
_G.UnitNameUnmodified = function(unit)
    return S.roster[unit] and S.roster[unit].name or nil
end
_G.UnitClass = function(unit)
    -- WoW API returns (localizedClass, englishClass, classID)
    local r = S.roster[unit]
    if not r then return nil end
    return r.className or r.class, r.class, r.classID
end
_G.UnitRace = function(unit)
    local r = S.roster[unit]
    if not r then return nil end
    return r.raceName or r.race, r.race
end
_G.UnitIsFeignDeath = function(unit)
    return S.roster[unit] and S.roster[unit].isFeign == true or false
end
_G.UnitGroupRolesAssigned = function(unit)
    return S.roster[unit] and S.roster[unit].role or "NONE"
end
_G.UnitIsUnit = function(a, b) return a == b end

-- Spells mock : S.playerKnownSpells[spellID] = true
S.playerKnownSpells = {}
_G.IsPlayerSpell = function(id) return S.playerKnownSpells[id] == true end
_G.IsSpellKnown = function(id) return S.playerKnownSpells[id] == true end

-- FindSpellOverrideByID mock : S.spellOverrides[base] = variant
S.spellOverrides = {}
_G.FindSpellOverrideByID = function(id) return S.spellOverrides[id] end

-- C_Spell mock pour GetSpellIcon
_G.C_Spell = {
    GetSpellInfo = function(id)
        return S.spells and S.spells[id] and { originalIconID = S.spells[id].icon } or nil
    end,
    GetSpellTexture = function(id)
        return S.spells and S.spells[id] and S.spells[id].icon or nil
    end,
}

-- Spec/class API mocks (pour TalentResolver tests)
_G.GetSpecialization = function() return S.playerSpecIdx or 1 end
_G.GetSpecializationInfo = function(_idx) return S.playerSpecID or 65 end

-- C_UnitAuras mock: S.auraFilters[unit][auraInstanceID] = { "HELPFUL|BIG_DEFENSIVE", ... }
S.auraFilters = {}
_G.C_UnitAuras = {
    IsAuraFilteredOutByInstanceID = function(unit, auraInstanceID, filter)
        local unitFilters = S.auraFilters[unit]
        if not unitFilters then return true end
        local auraTypes = unitFilters[auraInstanceID]
        if not auraTypes then return true end
        for _, t in ipairs(auraTypes) do
            if t == filter then return false end
        end
        return true
    end,
}

function S.reset()
    S.currentTime = 0
    S.secretValues = {}
    S.pendingTimers = {}
    S.roster = {}
    S.playerKnownSpells = {}
    S.spellOverrides = {}
    S.spells = nil
    S.playerSpecIdx = nil
    S.playerSpecID = nil
    S.auraFilters = {}
end

return S

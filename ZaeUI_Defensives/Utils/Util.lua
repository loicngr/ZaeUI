-- ZaeUI_Defensives/Utils/Util.lua
-- Shared helpers for the Defensives addon. All helpers here must be taint-safe
-- and work under WoW's Lua 5.1 runtime.

local _, ns = ...
ns.Utils = ns.Utils or {}

local Util = {}

--- Returns true when v is a tainted (secret) value.
--- @param v any
--- @return boolean
function Util.IsSecret(v)
    return v ~= nil and issecretvalue(v) == true
end

--- Reads an aura field safely. Returns nil when the field is secret or
--- when the aura is nil.
--- @param aura table?
--- @param field string
--- @return any|nil
function Util.SafeAuraField(aura, field)
    if not aura then return nil end
    local v = aura[field]
    if Util.IsSecret(v) then return nil end
    return v
end

--- Probes aura membership using the Blizzard filter API. Returns true when
--- the aura matches the filter mask ("HARMFUL", "HELPFUL|EXTERNAL_DEFENSIVE",
--- etc.). Avoids reading tainted fields.
--- @param unit string
--- @param auraInstanceID number
--- @param filter string
--- @return boolean
function Util.AuraMatchesFilter(unit, auraInstanceID, filter)
    if not (C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID) then
        return false
    end
    return not C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, auraInstanceID, filter)
end

--- Safe GUID lookup. Returns nil when the unit's GUID is unavailable or
--- tainted.
--- @param unit string
--- @return string|nil
function Util.SafeGUID(unit)
    if not unit then return nil end
    local g = UnitGUID and UnitGUID(unit)
    if g == nil or Util.IsSecret(g) then return nil end
    return g
end

--- Safe name lookup. Prefers UnitNameUnmodified (no realm suffix, stable
--- cross-realm) when available.
--- @param unit string
--- @return string|nil
function Util.SafeNameUnmodified(unit)
    if not unit then return nil end
    local name = (UnitNameUnmodified and UnitNameUnmodified(unit))
                 or (UnitName and UnitName(unit))
    if name == nil or Util.IsSecret(name) then return nil end
    return name
end

--- Returns the canonical (non-overridden) icon for a spell. C_Spell.GetSpellTexture
--- follows local player spell overrides, so querying a spell that the local
--- player overrides returns the override's icon instead of the original. We
--- prefer C_Spell.GetSpellInfo().originalIconID which stays canonical.
--- @param spellID number
--- @return number|nil
function Util.GetSpellIcon(spellID)
    if not spellID then return nil end
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
    if info and info.originalIconID then
        return info.originalIconID
    end
    if C_Spell and C_Spell.GetSpellTexture then
        return C_Spell.GetSpellTexture(spellID)
    end
    return nil
end

--- Protected call that supports varargs. Lua 5.1's `pcall` natively forwards
--- varargs to the callee (unlike stdlib `xpcall` which only accepts
--- `(f, handler)` in 5.1), so we use it directly — zero allocations per
--- call (no closure, no args-capture table). Critical hot-path function
--- called from every event fire() in AuraWatcher / CooldownStore / Inspector.
---
--- Errors are swallowed; they are logged to the chat frame only when
--- `ZaeUI_DefensivesDB.debug == true`. Silent by default — callers must never
--- rely on SafeCall output for diagnostics.
--- @param fn function
--- @param ... any
--- @return boolean ok
function Util.SafeCall(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and ZaeUI_DefensivesDB and ZaeUI_DefensivesDB.debug then
        print("|cffff4444[ZaeDef]|r " .. tostring(err))
    end
    return ok
end

ns.Utils.Util = Util
return Util

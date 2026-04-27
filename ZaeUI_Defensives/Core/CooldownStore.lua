-- ZaeUI_Defensives/Core/CooldownStore.lua
-- Single source of truth for defensive cooldown state.
-- Keyed by GUID. Maintains a name→GUID index for UI convenience lookups.
-- luacheck: no self
-- Public API uses the `Store:Method(...)` colon idiom for consistency; some
-- methods don't reference self internally, which luacheck would otherwise flag.

local _, ns = ...
ns.Core = ns.Core or {}
local Util = ns.Utils and ns.Utils.Util

local Store = {}

local store = {}        -- guid -> record
local nameIndex = {}    -- name -> guid
local callbacks = {     -- event -> list of fns
    CooldownStart = {}, CooldownEnd = {},
    BuffStart = {}, BuffEnd = {},
    PlayerAdded = {}, PlayerRemoved = {},
    KnownSpellsChanged = {},
}

-- Forward declaration for recursive recharge scheduling. Lua 5.1 requires
-- the local binding to exist before StartCooldown references it; the
-- assignment below attaches the function body to this local.
local scheduleRecharge

local function fire(event, ...)
    local list = callbacks[event]
    if not list then return end
    for i = 1, #list do
        if Util and Util.SafeCall then
            Util.SafeCall(list[i], ...)
        else
            list[i](...)
        end
    end
end

local function ensurePlayer(guid, payload)
    local rec = store[guid]
    if not rec then
        rec = {
            guid = guid,
            name = payload.name,
            class = payload.class,
            spec = payload.spec,
            role = payload.role or "UNKNOWN",
            cooldowns = {},
        }
        store[guid] = rec
        if payload.name then nameIndex[payload.name] = guid end
        fire("PlayerAdded", guid, rec)
    else
        -- Update metadata in case spec/role changed
        if payload.name and payload.name ~= rec.name then
            if rec.name then nameIndex[rec.name] = nil end
            rec.name = payload.name
            nameIndex[payload.name] = guid
        end
        if payload.spec then rec.spec = payload.spec end
        if payload.role then rec.role = payload.role end
        if payload.class then rec.class = payload.class end
    end
    return rec
end

--- Start or refresh a cooldown for (guid, spellID).
--- Handles the charge-consumption model: on each call, currentCharges
--- decrement (down to 0). Recharge is scheduled via a generation-tagged timer.
function Store:StartCooldown(guid, spellID, payload)
    local rec = ensurePlayer(guid, payload)
    local cd = rec.cooldowns[spellID]

    local maxCharges = payload.maxCharges or 1
    local nowCharges
    if cd then
        -- Existing entry: consume another charge from the current count
        nowCharges = math.max(0, (cd.currentCharges or maxCharges) - 1)
    else
        -- First observation: assume one charge was just consumed
        nowCharges = math.max(0, maxCharges - 1)
    end

    local newCD = {
        spellID        = spellID,
        effectiveID    = payload.effectiveID or spellID,
        startedAt      = payload.startedAt,
        duration       = payload.duration,
        currentCharges = nowCharges,
        maxCharges     = maxCharges,
        buffStartedAt  = payload.buffStartedAt,
        buffDuration   = payload.buffDuration,
        buffActive     = payload.buffActive == true,
        source         = payload.source or "aura",
        _gen           = ((cd and cd._gen) or 0) + 1,
    }
    rec.cooldowns[spellID] = newCD

    fire("CooldownStart", guid, spellID, newCD)
    if newCD.buffActive then
        fire("BuffStart", guid, spellID, newCD)
        if newCD.buffDuration and newCD.buffDuration > 0 then
            local gen = newCD._gen
            C_Timer.After(newCD.buffDuration + 0.5, function()
                local r = store[guid]
                if not r then return end
                local c = r.cooldowns[spellID]
                if not c or c._gen ~= gen then return end
                if c.buffActive then
                    c.buffActive = false
                    fire("BuffEnd", guid, spellID, c)
                end
            end)
        end
    end

    -- Schedule the recharge chain. scheduleRecharge handles any maxCharges >= 1
    -- by re-scheduling itself until the spell is fully recharged.
    scheduleRecharge(guid, spellID)
end

scheduleRecharge = function(guid, spellID)
    local rec = store[guid]
    if not rec then return end
    local cd = rec.cooldowns[spellID]
    if not cd then return end
    if cd.currentCharges >= cd.maxCharges then
        fire("CooldownEnd", guid, spellID, cd)
        return
    end
    local gen = cd._gen
    C_Timer.After(cd.duration, function()
        local r = store[guid]
        if not r then return end
        local c = r.cooldowns[spellID]
        if not c or c._gen ~= gen then return end  -- stale timer, skip
        c.currentCharges = c.currentCharges + 1
        if c.currentCharges < c.maxCharges then
            -- More charges still recharging: restart the swipe window and
            -- notify displays so the icon picks up the new (start, duration)
            -- pair. Without the CooldownStart fire, the previous swipe ends
            -- and no event refreshes the icon for the next charge.
            c.startedAt = (GetTime and GetTime()) or (c.startedAt + c.duration)
            c._gen = c._gen + 1
            fire("CooldownStart", guid, spellID, c)
            scheduleRecharge(guid, spellID)
        else
            fire("CooldownEnd", guid, spellID, c)
        end
    end)
end

--- End the aura buff without clearing the cooldown.
--- The glow UI stops; the swipe continues until the CD expires.
function Store:EndBuff(guid, spellID)
    local rec = store[guid]
    if not rec then return end
    local cd = rec.cooldowns[spellID]
    if not cd or not cd.buffActive then return end
    cd.buffActive = false
    fire("BuffEnd", guid, spellID, cd)
end

function Store:Get(guid, spellID)
    local rec = store[guid]
    return rec and rec.cooldowns[spellID] or nil
end

--- O(1) lookup of a player's metadata record by GUID. Read-only contract —
--- callers must NOT mutate the returned table. Used in hot paths where a
--- full IteratePlayers() copy would allocate unnecessarily.
--- @param guid string
--- @return table|nil record { guid, name, class, spec, role, cooldowns }
function Store:GetPlayerRec(guid)
    return store[guid]
end

function Store:GetByName(name, spellID)
    local guid = nameIndex[name]
    if not guid then return nil end
    return self:Get(guid, spellID)
end

function Store:Iterate(guid)
    local rec = store[guid]
    if not rec then return function() return nil end end
    return pairs(rec.cooldowns)
end

function Store:IteratePlayers()
    return pairs(store)
end

--- Returns the internal `{ [guid] = record }` table directly for read-only
--- access. Avoids the cost of copying into a fresh roster on every
--- UNIT_AURA event in the Brain pipeline. Callers must NOT mutate.
--- @return table
function Store:GetAllPlayers()
    return store
end

function Store:ResetPlayer(guid)
    local rec = store[guid]
    if not rec then return end
    if rec.name then nameIndex[rec.name] = nil end
    store[guid] = nil
    fire("PlayerRemoved", guid)
end

function Store:Reset()
    -- Capture the GUIDs we are about to drop so display modules can release
    -- per-player state (icons, anchored containers, glow handles) without
    -- N² re-renders: their PlayerRemoved handlers full-refresh the display,
    -- so we wipe first then notify once per departed GUID against an empty
    -- store.
    local removed
    for guid in pairs(store) do
        removed = removed or {}
        removed[#removed + 1] = guid
    end
    for k in pairs(store) do store[k] = nil end
    for k in pairs(nameIndex) do nameIndex[k] = nil end
    if removed then
        for i = 1, #removed do
            fire("PlayerRemoved", removed[i])
        end
    end
end

function Store:RegisterCallback(event, fn)
    local list = callbacks[event]
    if not list then
        error("Unknown CooldownStore event: " .. tostring(event))
    end
    list[#list + 1] = fn
end

--- Registers or refreshes a player record without consuming a charge.
--- Useful to create an entry ahead of any cast so that SeedKnownSpells
--- can populate cooldowns in a "ready" state.
--- @param guid string
--- @param payload table name/class/spec/role
function Store:RegisterPlayer(guid, payload)
    ensurePlayer(guid, payload)
end

--- Seeds a player's cooldowns table with "ready" entries for spells
--- they are known to have (based on class+spec resolved by the Brain).
--- Existing entries are left untouched — only new spells are added.
--- Fires KnownSpellsChanged exactly once if at least one new spell was added.
---
--- spellMap is a hash table `{ [spellID] = maxCharges }`. maxCharges must be
--- a number ≥ 1; non-numeric / missing values fall back to 1. Initial state
--- is currentCharges = maxCharges so the first StartCooldown consumes the
--- correct amount on multi-charge spells (Ice Block + Glacial Bulwark, etc.).
--- @param guid string
--- @param spellMap table<number, number>
function Store:SeedKnownSpells(guid, spellMap)
    local rec = store[guid]
    if not rec then return end
    local changed = false
    for spellID, maxCharges in pairs(spellMap) do
        if not rec.cooldowns[spellID] then
            local mc = (type(maxCharges) == "number" and maxCharges >= 1)
                       and maxCharges or 1
            rec.cooldowns[spellID] = {
                spellID = spellID, effectiveID = spellID,
                startedAt = 0, duration = 0,
                currentCharges = mc, maxCharges = mc,
                buffActive = false,
                source = "seed",
                _gen = 0,
            }
            changed = true
        end
    end
    if changed then
        fire("KnownSpellsChanged", guid, rec)
    end
end

--- Removes a single spell entry from a player's cooldowns table.
--- Used when a talent variant is detected, to remove the base spell's seed.
--- @param guid string
--- @param spellID number
function Store:RemoveSpell(guid, spellID)
    local rec = store[guid]
    if not rec then return end
    if not rec.cooldowns[spellID] then return end
    rec.cooldowns[spellID] = nil
    fire("KnownSpellsChanged", guid, rec)
end

--- Iterates all cooldowns (ready + on-cooldown) for a player.
--- Returns a pairs() iterator over rec.cooldowns, empty iterator if unknown.
--- @param guid string
--- @return fun(): number?, table?
function Store:IterateKnownSpells(guid)
    local rec = store[guid]
    if not rec then return function() return nil end end
    return pairs(rec.cooldowns)
end

ns.Core.CooldownStore = Store
return Store

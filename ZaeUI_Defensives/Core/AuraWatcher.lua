-- ZaeUI_Defensives/Core/AuraWatcher.lua
-- Per-unit watcher that emits high-level events for the Brain pipeline.
-- One invisible frame per allied unit (player + party1..4 or raid1..N),
-- reused via a pool. Events produced:
--   OnAuraChanged(unit, updateInfo)
--   OnLocalCast(spellID)             -- only for unit == "player"
--   OnUnitFlags(unit)
--   OnFeignDeath(unit)               -- Hunters only, derived from UNIT_FLAGS
-- luacheck: no self

local _, ns = ...
ns.Core = ns.Core or {}
local Util = ns.Utils and ns.Utils.Util

local Watcher = {}

local watchers    = {}  -- unit -> { frame, lastFeignDeath }
local framePool   = {}
local guidToUnit  = {}  -- guid -> unit token, refreshed on roster events.
                        -- Exposed via Watcher:GetUnitForGUID for Brain so it
                        -- doesn't rebuild a roster list on every UNIT_AURA.
local callbacks   = {
    OnAuraChanged    = {},
    OnLocalCast      = {},
    OnUnitFlags      = {},
    OnFeignDeath     = {},
    OnShieldChanged  = {},
}

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

local function acquireFrame()
    local n = #framePool
    if n > 0 then
        local f = framePool[n]
        framePool[n] = nil
        f:Show()
        return f
    end
    return CreateFrame("Frame")
end

local function releaseFrame(frame)
    if not frame then return end
    frame:UnregisterAllEvents()
    frame:SetScript("OnEvent", nil)
    frame:Hide()
    framePool[#framePool + 1] = frame
end

local function currentRoster()
    local t = { "player" }
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    if n <= 1 then return t end
    local inRaid = IsInRaid and IsInRaid()
    if inRaid then
        for i = 1, n do
            t[#t + 1] = "raid" .. i
        end
    else
        -- party tokens are party1..(n-1): the player is implicit
        for i = 1, n - 1 do
            t[#t + 1] = "party" .. i
        end
    end
    return t
end

local function watchUnit(unit)
    if watchers[unit] then return end
    local state = { frame = acquireFrame(), lastFeignDeath = false }
    state.frame:SetScript("OnEvent", function(_, event, _, arg2, arg3)
        -- WoW 10.x+ event signatures:
        --   UNIT_AURA(unitTarget, updateInfo)                       -> arg1=unit, arg2=updateInfo
        --   UNIT_SPELLCAST_SUCCEEDED(unitTarget, castGUID, spellID) -> arg3=spellID
        --   UNIT_FLAGS(unitTarget)                                  -> arg1=unit
        --   UNIT_ABSORB_AMOUNT_CHANGED(unitTarget)                  -> arg1=unit
        if event == "UNIT_AURA" then
            fire("OnAuraChanged", unit, arg2)
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            if unit == "player" then
                fire("OnLocalCast", arg3)
            end
        elseif event == "UNIT_FLAGS" then
            fire("OnUnitFlags", unit)
            local classToken
            if UnitClass then
                classToken = select(2, UnitClass(unit))
            end
            if classToken == "HUNTER" and UnitIsFeignDeath then
                local now = UnitIsFeignDeath(unit)
                if now and not state.lastFeignDeath then
                    fire("OnFeignDeath", unit)
                end
                state.lastFeignDeath = now
            end
        elseif event == "UNIT_ABSORB_AMOUNT_CHANGED" then
            fire("OnShieldChanged", unit)
        end
    end)
    state.frame:RegisterUnitEvent("UNIT_AURA", unit)
    state.frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", unit)
    state.frame:RegisterUnitEvent("UNIT_FLAGS", unit)
    state.frame:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED", unit)
    watchers[unit] = state
end

local function unwatchUnit(unit)
    local state = watchers[unit]
    if not state then return end
    releaseFrame(state.frame)
    watchers[unit] = nil
end

function Watcher:RewatchRoster()
    local wanted = {}
    for _, u in ipairs(currentRoster()) do wanted[u] = true end
    -- Remove obsolete watchers
    for u in pairs(watchers) do
        if not wanted[u] then unwatchUnit(u) end
    end
    -- Add missing watchers
    for u in pairs(wanted) do
        if not watchers[u] then watchUnit(u) end
    end
    -- Rebuild guid→unit cache (one pass over current roster)
    for g in pairs(guidToUnit) do guidToUnit[g] = nil end
    for u in pairs(wanted) do
        local g = Util and Util.SafeGUID(u) or nil
        if g then guidToUnit[g] = u end
    end
end

function Watcher:RegisterCallback(event, fn)
    local list = callbacks[event]
    if not list then
        error("Unknown AuraWatcher event: " .. tostring(event))
    end
    list[#list + 1] = fn
end

--- O(1) reverse lookup from a player GUID back to a unit token. Returns
--- nil if the GUID is not in the current roster. Refreshed on every
--- RewatchRoster (i.e. GROUP_ROSTER_UPDATE / PLAYER_ENTERING_WORLD).
--- @param guid string
--- @return string|nil unitToken
function Watcher:GetUnitForGUID(guid)
    return guidToUnit[guid]
end

function Watcher:Init()
    local events = CreateFrame("Frame")
    events:SetScript("OnEvent", function(_, event)
        if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
            Watcher:RewatchRoster()
        end
    end)
    events:RegisterEvent("GROUP_ROSTER_UPDATE")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    Watcher:RewatchRoster()
end

ns.Core.AuraWatcher = Watcher
return Watcher

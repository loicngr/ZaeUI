-- ZaeUI_Defensives/Modules/TestMode.lua
-- Spawns fake players in the CooldownStore for UI tuning without a real group.
-- All injection goes through the public store API so display modules can't
-- tell the difference between test and real data.
-- luacheck: no self

local _, ns = ...
ns.Modules = ns.Modules or {}

local T = {}
local Store = nil

local active = false
local forced = false              -- ignore combat auto-stop when true
local scenarioTimer = nil
local activeRoster = nil          -- current roster in use (PARTY or RAID)
local pendingEndBuffTimers = {}   -- cancelable C_Timer.NewTimer handles

local PARTY_ROSTER = {
    { guid = "Test-Pal-H",    name = "TestPaladin", class = "PALADIN",  spec = 65,  role = "HEALER" },
    { guid = "Test-War-T",    name = "TestWarrior", class = "WARRIOR",  spec = 73,  role = "TANK" },
    { guid = "Test-Mage-DPS", name = "TestMage",    class = "MAGE",     spec = 64,  role = "DAMAGER" },
    { guid = "Test-Hunter-D", name = "TestHunter",  class = "HUNTER",   spec = 254, role = "DAMAGER" },
}

-- Spells selected from the catalog that will be known by these fake players.
-- All IDs verified against SpellData.lua: 1022, 31821, 633, 97462, 871,
-- 45438, 186265, 264735.
local SAMPLE_SPELLS = {
    ["Test-Pal-H"]    = { 1022, 31821, 633 },
    ["Test-War-T"]    = { 97462, 871 },
    ["Test-Mage-DPS"] = { 45438 },
    ["Test-Hunter-D"] = { 186265, 264735 },
}

local RAID_ROSTER  -- built lazily

local function buildRaidRoster()
    if RAID_ROSTER then return end
    RAID_ROSTER = {}
    for i, p in ipairs(PARTY_ROSTER) do RAID_ROSTER[i] = p end
    -- Extend to 20 fake raiders by cycling the 4 templates
    for i = 5, 20 do
        local template = PARTY_ROSTER[((i - 1) % #PARTY_ROSTER) + 1]
        local rid = "Test-Raid-" .. i
        RAID_ROSTER[#RAID_ROSTER + 1] = {
            guid = rid,
            name = "TestRaider" .. i,
            class = template.class,
            spec = template.spec,
            role = template.role,
        }
        SAMPLE_SPELLS[rid] = SAMPLE_SPELLS[template.guid]
    end
end

local function seedRoster(roster)
    for _, p in ipairs(roster) do
        if Store.RegisterPlayer then
            Store:RegisterPlayer(p.guid, {
                name = p.name, class = p.class, spec = p.spec, role = p.role,
            })
        end
        if Store.SeedKnownSpells then
            Store:SeedKnownSpells(p.guid, SAMPLE_SPELLS[p.guid] or {})
        end
    end
end

local function isOnCooldown(guid, spellID)
    if not (Store and Store.Get) then return false end
    local cd = Store:Get(guid, spellID)
    if not cd then return false end
    local now = GetTime and GetTime() or 0
    return cd.startedAt and cd.startedAt > 0 and (now - cd.startedAt) < (cd.duration or 0)
end

local function scheduleNextCast()
    if not (C_Timer and C_Timer.NewTimer) then return end
    scenarioTimer = C_Timer.NewTimer(math.random(3, 8), function()
        if not active then return end
        if not activeRoster then return end
        local p = activeRoster[math.random(#activeRoster)]
        local spells = SAMPLE_SPELLS[p.guid]
        if spells and #spells > 0 then
            -- Filter to spells not currently on cooldown (avoid overlap)
            local available = {}
            for _, id in ipairs(spells) do
                if not isOnCooldown(p.guid, id) then
                    available[#available + 1] = id
                end
            end
            if #available > 0 then
                local spellID = available[math.random(#available)]
                local info = ns.SpellData and ns.SpellData[spellID]
                if info then
                    Store:StartCooldown(p.guid, spellID, {
                        name = p.name, class = p.class, spec = p.spec, role = p.role,
                        startedAt = GetTime(), duration = info.cooldown,
                        maxCharges = info.charges or 1,
                        buffStartedAt = GetTime(),
                        buffDuration = info.duration,
                        buffActive = (info.duration or 0) > 0,
                        effectiveID = spellID,
                        source = "test",
                    })
                    if (info.duration or 0) > 0 then
                        local t = C_Timer.NewTimer(info.duration, function()
                            if active then Store:EndBuff(p.guid, spellID) end
                        end)
                        pendingEndBuffTimers[#pendingEndBuffTimers + 1] = t
                    end
                end
            end
        end
        scheduleNextCast()
    end)
end

function T:IsActive() return active end

function T:Start(raid, force)
    if active then return end
    Store = ns.Core and ns.Core.CooldownStore
    if not Store then return end
    if raid then buildRaidRoster() end
    active = true
    forced = force == true
    activeRoster = raid and RAID_ROSTER or PARTY_ROSTER
    seedRoster(activeRoster)
    scheduleNextCast()

    if not forced then
        local combatFrame = CreateFrame("Frame")
        combatFrame:SetScript("OnEvent", function() T:Stop() end)
        combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        T._combatFrame = combatFrame
    end
end

function T:StartRaid(force)
    buildRaidRoster()
    T:Start(true, force)
end

function T:Stop()
    if not active then return end
    active = false
    forced = false
    if scenarioTimer then scenarioTimer:Cancel(); scenarioTimer = nil end
    for _, t in ipairs(pendingEndBuffTimers) do
        if t and t.Cancel then t:Cancel() end
    end
    pendingEndBuffTimers = {}
    if T._combatFrame then
        T._combatFrame:UnregisterAllEvents()
        T._combatFrame = nil
    end
    if Store then
        for _, p in ipairs(PARTY_ROSTER) do Store:ResetPlayer(p.guid) end
        if RAID_ROSTER then
            for _, p in ipairs(RAID_ROSTER) do Store:ResetPlayer(p.guid) end
        end
    end
    activeRoster = nil
end

function T:Init()
    Store = ns.Core and ns.Core.CooldownStore
    -- Init is passive — Start/StartRaid/Stop are called by slash commands.
end

ns.Modules.TestMode = T
return T

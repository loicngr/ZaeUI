-- ZaeUI_Defensives/Modules/FrameDisplay.lua
-- Anchored display: attaches a grid of icons under each Blizzard Compact
-- unit frame (party/raid). Falls back silently to FloatingDisplay when a
-- custom unit-frame framework is detected via well-known globals.
-- luacheck: no self

local _, ns = ...
ns.Modules = ns.Modules or {}
local Util = ns.Utils and ns.Utils.Util
local Store = nil

local D = {}

-- Per-unitFrame state: { container, icons = { [spellID] = iconFrame }, unit, guid }
local containers = {}
-- Secondary index guid → state for O(1) fast-path on BuffStart/End.
local containersByGUID = {}
local customFrameworkDetected = nil

-- Resolved at Init time (Core.IconWidget loads before this module via TOC).
local IconWidget

local function db() return ZaeUI_DefensivesDB end

-- ------------------------------------------------------------------
-- Custom framework detection (one-shot at init)
-- ------------------------------------------------------------------

local function detectCustomFrameworks()
    local frameworks = { "ElvUF", "Grid2", "VuhDo", "CellDB", "Plexus" }
    for _, name in ipairs(frameworks) do
        if _G[name] then return name end
    end
    return nil
end

local function shouldAnchor()
    if customFrameworkDetected then return false end
    if not (db() and db().displayMode == "anchored") then return false end
    -- Context opt-out: user disabled the addon in raid / M+.
    if ns.isEnabledInCurrentContext and not ns.isEnabledInCurrentContext() then
        return false
    end
    -- Raid (>5 players) always uses the list/floating view: the Blizzard
    -- compact raid frames are too cramped for a per-unit icon grid.
    if IsInRaid() then return false end
    if not db().trackerEnabled then return false end
    return true
end

-- ------------------------------------------------------------------
-- Filter (delegates to Util.ShouldDisplayCooldown)
-- ------------------------------------------------------------------

local function shouldDisplay(cd, info, rec)
    return Util and Util.ShouldDisplayCooldown
        and Util.ShouldDisplayCooldown(cd, info, rec, db())
end

-- ------------------------------------------------------------------
-- Icon helpers (delegate to Core.IconWidget)
-- ------------------------------------------------------------------

local ICON_OPTS = {
    countFont = "NumberFontNormalSmall",
    countAnchor = "BOTTOMRIGHT",
    countOffsetX = -1,
    countOffsetY = 1,
    -- Anchored icons run larger than the floating tracker (default 28px),
    -- so we bump the timer font from the global 7px default to 9px.
    timerSize = 9,
}

local function acquireIcon(parent, size)
    return IconWidget.Acquire(parent, size, ICON_OPTS)
end

local function releaseIcon(f)
    IconWidget.Release(f)
end

-- ------------------------------------------------------------------
-- Container management
-- ------------------------------------------------------------------

local function releaseContainer(state)
    if not state then return end
    if state.guid then containersByGUID[state.guid] = nil end
    if state.container then state.container:Hide() end
    for _, icon in pairs(state.icons) do releaseIcon(icon) end
    state.icons = {}
    state.guid = nil
end

local function detachAll()
    for uf, state in pairs(containers) do
        releaseContainer(state)
        containers[uf] = nil
    end
    for g in pairs(containersByGUID) do containersByGUID[g] = nil end
end

local function getContainerFor(unitFrame, unit, guid)
    local state = containers[unitFrame]
    if not state then
        local container = CreateFrame("Frame", nil, unitFrame)
        local ok, lvl = pcall(unitFrame.GetFrameLevel, unitFrame)
        container:SetFrameLevel(((ok and lvl) or 1) + 5)
        state = { container = container, icons = {}, unit = unit, guid = guid, unitFrame = unitFrame }
        containers[unitFrame] = state
    else
        -- Unit frame may have been reassigned to a different player; re-index.
        if state.guid and state.guid ~= guid then
            containersByGUID[state.guid] = nil
        end
        state.unit = unit
        state.guid = guid
    end
    if guid then containersByGUID[guid] = state end
    return state
end

local function attachToUnitFrame(unitFrame, unit)
    if not (unitFrame and unit) then return end
    if type(unit) == "string" and unit:sub(1, 9) == "nameplate" then return end
    if not shouldAnchor() then return end
    if not (Store and Util) then return end

    local guid = Util.SafeGUID(unit)
    if not guid then return end
    local rec = Store.GetPlayerRec and Store:GetPlayerRec(guid) or nil
    if not rec then return end

    if not db().anchoredShowPlayer then
        if UnitIsUnit and UnitIsUnit(unit, "player") then
            -- Don't anchor on player's own frame when the option is off
            local st = containers[unitFrame]
            if st then releaseContainer(st); containers[unitFrame] = nil end
            return
        end
    end

    local state = getContainerFor(unitFrame, unit, guid)
    local d = db()
    local size     = d.anchoredIconSize   or 20
    local spacing  = d.anchoredSpacing    or 2
    local perRow   = d.anchoredIconsPerRow or 4
    local side     = d.anchoredSide       or "RIGHT"
    local offX     = d.anchoredOffsetX    or 0
    local offY     = d.anchoredOffsetY    or 0

    -- Position the container relative to the unit frame
    state.container:ClearAllPoints()
    if side == "LEFT" then
        state.container:SetPoint("TOPRIGHT", unitFrame, "TOPLEFT", -offX, offY)
    elseif side == "TOP" then
        state.container:SetPoint("BOTTOMLEFT", unitFrame, "TOPLEFT", offX, offY)
    elseif side == "BOTTOM" then
        state.container:SetPoint("TOPLEFT", unitFrame, "BOTTOMLEFT", offX, offY)
    else -- RIGHT default
        state.container:SetPoint("TOPLEFT", unitFrame, "TOPRIGHT", offX, offY)
    end
    state.container:Show()

    -- Collect displayable cooldowns
    local visible = {}
    for spellID, cd in Store:IterateKnownSpells(guid) do
        local info = ns.SpellData and ns.SpellData[spellID]
        if info and shouldDisplay(cd, info, rec) then
            visible[#visible + 1] = { spellID = spellID, cd = cd, info = info }
        end
    end

    -- Release icons no longer visible
    for spellID, icon in pairs(state.icons) do
        local stillVisible = false
        for _, v in ipairs(visible) do
            if v.spellID == spellID then stillVisible = true; break end
        end
        if not stillVisible then
            releaseIcon(icon)
            state.icons[spellID] = nil
        end
    end

    -- Layout + update
    for idx, entry in ipairs(visible) do
        local icon = state.icons[entry.spellID]
        if not icon then
            icon = acquireIcon(state.container, size)
            state.icons[entry.spellID] = icon
        end
        icon:SetSize(size, size)
        local col = ((idx - 1) % perRow)
        local row = math.floor((idx - 1) / perRow)
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", state.container, "TOPLEFT",
                      col * (size + spacing), -(row * (size + spacing)))
        IconWidget.Apply(icon, entry.cd, entry.info)
    end

    -- Resize container to fit the grid
    local cols = math.min(#visible, perRow)
    local rows = math.ceil(#visible / perRow)
    state.container:SetSize(
        math.max(1, cols * size + math.max(0, cols - 1) * spacing),
        math.max(1, rows * size + math.max(0, rows - 1) * spacing))
end

-- ------------------------------------------------------------------
-- Full refresh: iterate current roster + Blizzard CompactUnitFrames
-- ------------------------------------------------------------------

local function isFriendlyCuf(frame)
    if not frame then return false end
    if frame.IsForbidden and frame:IsForbidden() then return false end
    local name = frame.GetName and frame:GetName()
    if not name then return false end
    if name:find("CompactParty") or name:find("CompactRaid") then return true end
    return false
end

-- Walk a parent's children via varargs instead of `{ parent:GetChildren() }`.
-- Capturing the call once into a function's `...` lets `select(i, ...)` index
-- without re-invoking GetChildren and without allocating a temporary table.
local function visitDirectChildren(fn, ...)
    local count = select("#", ...)
    for i = 1, count do
        local child = (select(i, ...))
        if isFriendlyCuf(child) and child.unit then
            fn(child, child.unit)
        end
    end
end

local function visitTwoLevels(fn, ...)
    local count = select("#", ...)
    for i = 1, count do
        local child = (select(i, ...))
        if isFriendlyCuf(child) and child.unit then
            fn(child, child.unit)
        end
        if child and child.GetChildren then
            visitDirectChildren(fn, child:GetChildren())
        end
    end
end

local function iterateCompactUnitFrames(fn)
    if CompactRaidFrameContainer then
        visitTwoLevels(fn, CompactRaidFrameContainer:GetChildren())
    end
    if CompactPartyFrame and CompactPartyFrame:IsShown() then
        visitDirectChildren(fn, CompactPartyFrame:GetChildren())
    end
end

local function refreshAll()
    if not shouldAnchor() then
        detachAll()
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        for unitFrame, state in pairs(containers) do
            if state.unit then
                attachToUnitFrame(unitFrame, state.unit)
            end
        end
    else
        iterateCompactUnitFrames(attachToUnitFrame)
    end
end

-- ------------------------------------------------------------------
-- Public API
-- ------------------------------------------------------------------

function D:ApplyMode()
    if shouldAnchor() then
        refreshAll()
    else
        detachAll()
    end
end

function D:Refresh() refreshAll() end
function D:HideAll() detachAll() end

function D:Init()
    Store = ns.Core and ns.Core.CooldownStore
    IconWidget = ns.Core and ns.Core.IconWidget
    if not Store or not IconWidget then return end

    customFrameworkDetected = detectCustomFrameworks()
    if customFrameworkDetected and db() and not db().frameDisplayCustomWarningShown then
        db().frameDisplayCustomWarningShown = true
        print("|cff3bb5ff[ZaeUI_Defensives]|r Custom unit-frame addon detected ("
              .. customFrameworkDetected .. "). Anchored mode is disabled; "
              .. "Floating mode will be used instead.")
    end

    -- Subscribe to Store events. Fast-paths use containersByGUID for O(1)
    -- lookup instead of iterating every anchored frame on each event.
    local function fastUpdateIcon(guid, spellID)
        local state = containersByGUID[guid]
        if not state then return nil end
        return state.icons and state.icons[spellID]
    end

    Store:RegisterCallback("CooldownStart", function(guid, spellID, cd)
        local icon = fastUpdateIcon(guid, spellID)
        if icon then
            IconWidget.Apply(icon, cd, ns.SpellData and ns.SpellData[cd.spellID])
        else
            local state = containersByGUID[guid]
            if state and state.unitFrame and state.unit then
                attachToUnitFrame(state.unitFrame, state.unit)
            else
                refreshAll()
            end
        end
    end)
    Store:RegisterCallback("CooldownEnd", function(guid, spellID, cd)
        local icon = fastUpdateIcon(guid, spellID)
        if icon then
            IconWidget.Apply(icon, cd, ns.SpellData and ns.SpellData[cd.spellID])
        end
    end)
    Store:RegisterCallback("BuffStart", function(guid, spellID, cd)
        local icon = fastUpdateIcon(guid, spellID)
        if icon then
            IconWidget.StartGlow(icon, ns.SpellData and ns.SpellData[cd.spellID])
        end
    end)
    Store:RegisterCallback("BuffEnd", function(guid, spellID)
        local icon = fastUpdateIcon(guid, spellID)
        IconWidget.StopGlow(icon)
    end)
    Store:RegisterCallback("KnownSpellsChanged", function() refreshAll() end)
    Store:RegisterCallback("PlayerAdded",        function() refreshAll() end)
    Store:RegisterCallback("PlayerRemoved",      function() refreshAll() end)

    -- Hook Blizzard compact frame lifecycle.
    -- CompactUnitFrame_SetUnit receives the unit as argument — no need to
    -- read frame.unit which may be tainted. IsForbidden() filters nameplates.
    if hooksecurefunc then
        if _G.CompactUnitFrame_SetUnit then
            hooksecurefunc("CompactUnitFrame_SetUnit", function(frame, unit)
                if not isFriendlyCuf(frame) then return end
                if not shouldAnchor() then return end
                if unit then
                    attachToUnitFrame(frame, unit)
                else
                    local st = containers[frame]
                    if st then releaseContainer(st); containers[frame] = nil end
                end
            end)
        end
        if _G.CompactUnitFrame_UpdateVisible then
            hooksecurefunc("CompactUnitFrame_UpdateVisible", function(frame)
                if not isFriendlyCuf(frame) then return end
                if not shouldAnchor() then return end
                local st = containers[frame]
                if st and st.container then
                    st.container:SetShown(frame:IsVisible())
                end
            end)
        end
    end

    -- React to zone transitions (IsInRaid may change)
    local zoneFrame = CreateFrame("Frame")
    zoneFrame:SetScript("OnEvent", function() D:ApplyMode() end)
    zoneFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    zoneFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    zoneFrame:RegisterEvent("GROUP_ROSTER_UPDATE")

    D:ApplyMode()
end

ns.Modules.FrameDisplay = D
return D

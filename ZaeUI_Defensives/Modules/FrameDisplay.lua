-- ZaeUI_Defensives/Modules/FrameDisplay.lua
-- Anchored display: attaches a grid of icons under each Blizzard Compact
-- unit frame (party/raid). Falls back silently to FloatingDisplay when a
-- custom unit-frame framework is detected via well-known globals.
-- luacheck: no self

local _, ns = ...
ns.Modules = ns.Modules or {}
local Util = ns.Utils and ns.Utils.Util
local Store = nil
local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)

local D = {}

-- Per-unitFrame state: { container, icons = { [spellID] = iconFrame }, unit, guid }
local containers = {}
-- Secondary index guid → state for O(1) fast-path on BuffStart/End.
local containersByGUID = {}
local iconPool   = {}
local customFrameworkDetected = nil

-- Glow colors (same palette as FloatingDisplay)
local GLOW_COLORS = {
    External = { 1.00, 0.82, 0.20, 1.0 },
    Personal = { 0.23, 0.71, 1.00, 1.0 },
    Raidwide = { 0.30, 1.00, 0.30, 1.0 },
}

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
-- Filter (same logic as FloatingDisplay)
-- ------------------------------------------------------------------

local function shouldDisplay(cd, info, rec)
    if not db() then return false end
    local d = db()
    if rec.role == "TANK"    and d.trackerShowTankCooldowns   == false then return false end
    if rec.role == "HEALER"  and d.trackerShowHealerCooldowns == false then return false end
    if rec.role == "DAMAGER" and d.trackerShowDpsCooldowns    == false then return false end
    if info.category == "External" and d.trackerShowExternal  == false then return false end
    if info.category == "Personal" and d.trackerShowPersonal  == false then return false end
    if info.category == "Raidwide" and d.trackerShowRaidwide  == false then return false end
    if d.trackerHideOwnExternals and info.category == "External" then
        local playerName = Util and Util.SafeNameUnmodified("player") or nil
        if rec.name == playerName then return false end
    end
    local _ = cd
    return true
end

-- ------------------------------------------------------------------
-- Icon pool
-- ------------------------------------------------------------------

local function onIconEnter(self)
    if not self._spellID then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetSpellByID(self._spellID)
    GameTooltip:Show()
end

local function onIconLeave()
    GameTooltip:Hide()
end

local function acquireIcon(parent, size)
    local n = #iconPool
    if n > 0 then
        local f = iconPool[n]
        iconPool[n] = nil
        f:SetParent(parent)
        f:SetSize(size, size)
        f:Show()
        return f
    end
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    f:EnableMouse(true)
    f:SetScript("OnEnter", onIconEnter)
    f:SetScript("OnLeave", onIconLeave)
    f.Texture = f:CreateTexture(nil, "ARTWORK")
    f.Texture:SetAllPoints()
    f.Texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.Cooldown = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.Cooldown:SetAllPoints()
    f.Cooldown:EnableMouse(false)
    f.Cooldown:SetHideCountdownNumbers(true)
    f.TextOverlay = CreateFrame("Frame", nil, f)
    f.TextOverlay:SetAllPoints()
    f.TextOverlay:SetFrameLevel(f.Cooldown:GetFrameLevel() + 2)
    f.Text = f.TextOverlay:CreateFontString(nil, "OVERLAY")
    f.Text:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
    f.Text:SetPoint("CENTER", 0, 0)
    f.Count = f:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    f.Count:SetPoint("BOTTOMRIGHT", -1, 1)
    f.Count:Hide()
    return f
end

local function iconTimerOnUpdate(self, elapsed)
    self._timerAcc = (self._timerAcc or 0) + elapsed
    if self._timerAcc < 0.1 then return end
    self._timerAcc = 0
    local now = GetTime and GetTime() or 0
    local remaining = (self._cdStart or 0) + (self._cdDur or 0) - now
    if remaining <= 0 then
        self.Text:SetText("")
        self._lastTimerText = nil
        self:SetScript("OnUpdate", nil)
        return
    end
    local seconds = math.floor(remaining + 0.5)
    if seconds ~= self._lastTimerText then
        local txt
        if seconds >= 60 then
            local m = math.floor(seconds / 60)
            local s = seconds - m * 60
            txt = m .. ":" .. (s < 10 and "0" or "") .. s
        else
            txt = tostring(seconds)
        end
        self.Text:SetText(txt)
        self._lastTimerText = seconds
    end
end

local function releaseIcon(f)
    if not f then return end
    f:Hide()
    f:SetScript("OnUpdate", nil)
    if f.Cooldown then f.Cooldown:Clear() end
    if f.Text then f.Text:SetText("") end
    if f.Count then f.Count:Hide() end
    if LCG and f._glowing then
        LCG.PixelGlow_Stop(f)
        f._glowing = false
    end
    f._cdStart, f._cdDur = nil, nil
    f._lastTimerText = nil
    f._spellID = nil
    iconPool[#iconPool + 1] = f
end

local function setIconState(icon, cd, info)
    icon._spellID = cd.effectiveID or cd.spellID
    icon.Texture:SetTexture(Util and Util.GetSpellIcon(cd.effectiveID or cd.spellID) or nil)
    local onCooldown = cd.startedAt and cd.startedAt > 0
                       and cd.duration and cd.duration > 0
    if onCooldown then
        if icon._cdStart ~= cd.startedAt or icon._cdDur ~= cd.duration then
            icon.Cooldown:SetCooldown(cd.startedAt, cd.duration)
            icon._cdStart = cd.startedAt
            icon._cdDur = cd.duration
            icon._lastTimerText = nil
        end
        icon._timerAcc = 0
        icon:SetScript("OnUpdate", iconTimerOnUpdate)
    else
        icon.Cooldown:Clear()
        if icon.Text then icon.Text:SetText("") end
        icon:SetScript("OnUpdate", nil)
        icon._cdStart, icon._cdDur = nil, nil
        icon._lastTimerText = nil
    end
    if icon.Count then
        if cd.maxCharges and cd.maxCharges > 1 then
            icon.Count:SetText(tostring(cd.currentCharges or 0))
            icon.Count:Show()
        else
            icon.Count:Hide()
        end
    end
    if LCG and cd.buffActive and info then
        local color = GLOW_COLORS[info.category] or { 1, 1, 1, 1 }
        LCG.PixelGlow_Start(icon, color, 8, 0.25, 10, 1)
        icon._glowing = true
    elseif LCG and icon._glowing and not cd.buffActive then
        LCG.PixelGlow_Stop(icon)
        icon._glowing = false
    end
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
        setIconState(icon, entry.cd, entry.info)
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

local function iterateCompactUnitFrames(fn)
    if CompactRaidFrameContainer then
        for _, child in ipairs({ CompactRaidFrameContainer:GetChildren() }) do
            if isFriendlyCuf(child) and child.unit then fn(child, child.unit) end
            for _, sub in ipairs({ child:GetChildren() }) do
                if isFriendlyCuf(sub) and sub.unit then fn(sub, sub.unit) end
            end
        end
    end
    if CompactPartyFrame and CompactPartyFrame:IsShown() then
        for _, child in ipairs({ CompactPartyFrame:GetChildren() }) do
            if isFriendlyCuf(child) and child.unit then fn(child, child.unit) end
        end
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
    if not Store then return end

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
            setIconState(icon, cd, ns.SpellData and ns.SpellData[cd.spellID])
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
            setIconState(icon, cd, ns.SpellData and ns.SpellData[cd.spellID])
        end
    end)
    Store:RegisterCallback("BuffStart", function(guid, spellID, cd)
        local icon = fastUpdateIcon(guid, spellID)
        if icon and LCG then
            local info = ns.SpellData and ns.SpellData[cd.spellID]
            local color = info and GLOW_COLORS[info.category] or { 1, 1, 1, 1 }
            LCG.PixelGlow_Start(icon, color, 8, 0.25, 10, 1)
            icon._glowing = true
        end
    end)
    Store:RegisterCallback("BuffEnd", function(guid, spellID)
        local icon = fastUpdateIcon(guid, spellID)
        if icon and LCG and icon._glowing then
            LCG.PixelGlow_Stop(icon)
            icon._glowing = false
        end
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

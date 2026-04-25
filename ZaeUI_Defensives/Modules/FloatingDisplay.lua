-- ZaeUI_Defensives/Modules/FloatingDisplay.lua
-- Floating draggable tracker for v3 — consumes CooldownStore events.
-- Displays all known spells per player (ready and on-cooldown) with active
-- glow while the defensive buff is up.
-- luacheck: no self

local _, ns = ...
ns.Modules = ns.Modules or {}
local Util = ns.Utils and ns.Utils.Util
local Store = nil
local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)

local D = {}

-- UI state
local mainFrame
local rowPool   = {}
local iconPool  = {}
local iconIndex = {}  -- [guid][spellID] = iconFrame, maintained by refresh
local activeRows = {} -- ordered list of currently visible rows

-- Layout constants
local ROW_HEIGHT = 24
local ICON_SIZE  = 20
local ICON_GAP   = 2
local NAME_WIDTH = 96  -- reserved space for player name before icons
local PAD_X      = 4

-- Glow colors per category
local GLOW_COLORS = {
    External = { 1.00, 0.82, 0.20, 1.0 }, -- gold
    Personal = { 0.23, 0.71, 1.00, 1.0 }, -- ZaeUI cyan
    Raidwide = { 0.30, 1.00, 0.30, 1.0 }, -- green
}

local function db() return ZaeUI_DefensivesDB end

local function roleOrder(role)
    if role == "TANK" then return 1
    elseif role == "HEALER" then return 2
    else return 3 end
end

--- Compute a "rrggbb" hex string from a class token using RAID_CLASS_COLORS.
--- Falls back to white when the class is unknown.
local function classColorHex(class)
    if class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then
        local c = RAID_CLASS_COLORS[class]
        return string.format("%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
    end
    return "ffffff"
end

local function shouldDisplay(cd, info, rec)
    if not db() then return false end
    local d = db()
    -- Role filter
    if rec.role == "TANK"    and d.trackerShowTankCooldowns   == false then return false end
    if rec.role == "HEALER"  and d.trackerShowHealerCooldowns == false then return false end
    if rec.role == "DAMAGER" and d.trackerShowDpsCooldowns    == false then return false end
    -- Category filter
    if info.category == "External" and d.trackerShowExternal == false then return false end
    if info.category == "Personal" and d.trackerShowPersonal == false then return false end
    if info.category == "Raidwide" and d.trackerShowRaidwide == false then return false end
    -- Hide own externals
    if d.trackerHideOwnExternals and info.category == "External" then
        local playerName = Util and Util.SafeNameUnmodified("player") or nil
        if rec.name and playerName and rec.name == playerName then return false end
    end
    -- Silence unused-variable warning; cd may influence future filters.
    local _ = cd
    return true
end

-- ------------------------------------------------------------------
-- Pool helpers
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

local function acquireIcon(parent)
    local n = #iconPool
    if n > 0 then
        local f = iconPool[n]
        iconPool[n] = nil
        f:SetParent(parent)
        f:Show()
        return f
    end
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(ICON_SIZE, ICON_SIZE)
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
    f.Text:SetFont(STANDARD_TEXT_FONT, 8, "OUTLINE")
    f.Text:SetPoint("BOTTOM", 0, -2)
    f.Count = f:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    f.Count:SetPoint("BOTTOMRIGHT", -2, 1)
    f.Count:Hide()
    return f
end

local function releaseIcon(f)
    if not f then return end
    f:Hide()
    f:ClearAllPoints()
    f:SetScript("OnUpdate", nil)
    if f.Cooldown then f.Cooldown:Clear() end
    if f.Text then f.Text:SetText("") end
    if f.Count then f.Count:Hide() end
    if LCG and f._glowing then
        LCG.PixelGlow_Stop(f)
        f._glowing = false
    end
    f._cdStart, f._cdDur = nil, nil
    f._spellID = nil
    iconPool[#iconPool + 1] = f
end

local function acquireRow(parent)
    local n = #rowPool
    if n > 0 then
        local r = rowPool[n]
        rowPool[n] = nil
        r:SetParent(parent)
        r:Show()
        return r
    end
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(ROW_HEIGHT)
    r.Name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.Name:SetPoint("LEFT", PAD_X, 0)
    r.Name:SetWidth(NAME_WIDTH)
    r.Name:SetJustifyH("LEFT")
    r.Icons = {}
    return r
end

local function releaseRow(r)
    if not r then return end
    if r.Icons then
        for i = 1, #r.Icons do
            releaseIcon(r.Icons[i])
            r.Icons[i] = nil
        end
    end
    r:Hide()
    r:ClearAllPoints()
    rowPool[#rowPool + 1] = r
end

-- ------------------------------------------------------------------
-- Icon state update
-- ------------------------------------------------------------------

-- Shared top-level OnUpdate handler. Reads state from `self._cdStart/_cdDur`
-- set by setIconState, avoiding per-icon closures that would allocate on
-- every refresh (which is expensive in raid 20 where rebuilds are frequent).
-- Caches last displayed integer to skip the string.format allocation when
-- the visible value hasn't changed (10 Hz × N icons = N string allocs/s).
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

local function setIconState(icon, cd, info)
    icon._spellID = cd.effectiveID or cd.spellID
    local iconTexture = Util and Util.GetSpellIcon(cd.effectiveID or cd.spellID) or nil
    icon.Texture:SetTexture(iconTexture)
    -- Cooldown swipe: call SetCooldown ONLY when (startedAt, duration) changes
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
        icon.Text:SetText("")
        icon:SetScript("OnUpdate", nil)
        icon._cdStart, icon._cdDur = nil, nil
        icon._lastTimerText = nil
    end
    -- Charge counter
    if icon.Count then
        if cd.maxCharges and cd.maxCharges > 1 then
            icon.Count:SetText(tostring(cd.currentCharges or 0))
            icon.Count:Show()
        else
            icon.Count:Hide()
        end
    end
    -- Glow
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
-- Full refresh — rebuilds rows and icons
-- ------------------------------------------------------------------

local function refresh()
    if not mainFrame or not mainFrame:IsShown() then return end
    if not Store then return end

    -- Release all currently active rows back to the pool
    for i = 1, #activeRows do
        releaseRow(activeRows[i])
        activeRows[i] = nil
    end
    for g in pairs(iconIndex) do iconIndex[g] = nil end

    -- Collect players sorted by (role, name)
    local players = {}
    for _, rec in Store:IteratePlayers() do
        players[#players + 1] = rec
    end
    table.sort(players, function(a, b)
        local ra, rb = roleOrder(a.role), roleOrder(b.role)
        if ra ~= rb then return ra < rb end
        return (a.name or "") < (b.name or "")
    end)

    local y = -PAD_X
    local rowCount = 0
    for _, rec in ipairs(players) do
        -- Collect displayable cooldowns, sorted by spellID for stability
        local entries = {}
        for spellID, cd in Store:IterateKnownSpells(rec.guid) do
            local info = ns.SpellData and ns.SpellData[spellID]
            if info and shouldDisplay(cd, info, rec) then
                entries[#entries + 1] = { spellID = spellID, cd = cd, info = info }
            end
        end
        if #entries > 0 then
            table.sort(entries, function(a, b) return a.spellID < b.spellID end)
            local row = acquireRow(mainFrame)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", PAD_X, y)
            row:SetPoint("RIGHT", mainFrame, "RIGHT", -PAD_X, 0)
            local colorHex = classColorHex(rec.class)
            row.Name:SetText("|cff" .. colorHex .. (rec.name or "?") .. "|r")
            -- Position icons after the name (approximate layout)
            local ix = NAME_WIDTH + PAD_X
            for i, entry in ipairs(entries) do
                local icon = acquireIcon(row)
                icon:ClearAllPoints()
                icon:SetPoint("LEFT", row, "LEFT", ix, 0)
                setIconState(icon, entry.cd, entry.info)
                row.Icons[i] = icon
                iconIndex[rec.guid] = iconIndex[rec.guid] or {}
                iconIndex[rec.guid][entry.cd.effectiveID or entry.spellID] = icon
                ix = ix + ICON_SIZE + ICON_GAP
            end
            rowCount = rowCount + 1
            activeRows[rowCount] = row
            y = y - ROW_HEIGHT
        end
    end

    -- Auto-resize height
    local newHeight = math.max(40, math.abs(y) + PAD_X)
    mainFrame:SetHeight(newHeight)
end

-- ------------------------------------------------------------------
-- Fast path handlers (no rebuild, just update a single icon)
-- ------------------------------------------------------------------

local function onCooldownStart(guid, spellID, cd)
    if not mainFrame or not mainFrame:IsShown() then return end
    local icon = iconIndex[guid] and iconIndex[guid][spellID]
    if icon then
        local info = ns.SpellData and ns.SpellData[cd.spellID]
        setIconState(icon, cd, info)
    else
        refresh()  -- unknown icon: full rebuild
    end
end

local function onCooldownEnd(guid, spellID, cd)
    if not mainFrame or not mainFrame:IsShown() then return end
    local icon = iconIndex[guid] and iconIndex[guid][spellID]
    if icon then
        local info = ns.SpellData and ns.SpellData[cd.spellID]
        setIconState(icon, cd, info)
    end
end

local function onBuffStart(guid, spellID, cd)
    if not mainFrame or not mainFrame:IsShown() then return end
    local icon = iconIndex[guid] and iconIndex[guid][spellID]
    if icon and LCG then
        local info = ns.SpellData and ns.SpellData[cd.spellID]
        local color = (info and GLOW_COLORS[info.category]) or { 1, 1, 1, 1 }
        LCG.PixelGlow_Start(icon, color, 8, 0.25, 10, 1)
        icon._glowing = true
    end
end

local function onBuffEnd(guid, spellID)
    if not mainFrame or not mainFrame:IsShown() then return end
    local icon = iconIndex[guid] and iconIndex[guid][spellID]
    if icon and LCG and icon._glowing then
        LCG.PixelGlow_Stop(icon)
        icon._glowing = false
    end
end

-- ------------------------------------------------------------------
-- Init / ApplyMode / public API
-- ------------------------------------------------------------------

function D:ApplyMode()
    if not mainFrame then return end
    if not db() then return end
    local isAnchoredMode = db().displayMode == "anchored"
    -- Context opt-out (user disabled the addon for raid or active M+).
    if ns.isEnabledInCurrentContext and not ns.isEnabledInCurrentContext() then
        mainFrame:Hide()
        -- Keep the sibling in sync.
        if ns.Modules.FrameDisplay and ns.Modules.FrameDisplay.ApplyMode then
            ns.Modules.FrameDisplay:ApplyMode()
        end
        return
    end
    -- Raid (>5 players) always forces the list/floating view, regardless of
    -- the selected display mode. Anchored grids under the Blizzard compact
    -- raid frames are too cramped to be readable at that density.
    local fallbackInRaid = IsInRaid()
    local inAnyGroup = ZaeUI_Shared and ZaeUI_Shared.isInAnyGroup
                       and ZaeUI_Shared.isInAnyGroup()
    if db().trackerEnabled
       and (not db().trackerHideWhenSolo or inAnyGroup)
       and (not isAnchoredMode or fallbackInRaid) then
        mainFrame:Show()
        refresh()
    else
        mainFrame:Hide()
    end
    -- Sibling display handles its own visibility (wired in Chunk 4.2)
    if ns.Modules.FrameDisplay and ns.Modules.FrameDisplay.ApplyMode then
        ns.Modules.FrameDisplay:ApplyMode()
    end
end

function D:Refresh() refresh() end
function D:Show() if mainFrame then mainFrame:Show(); refresh() end end
function D:Hide() if mainFrame then mainFrame:Hide() end end

function D:Init()
    Store = ns.Core and ns.Core.CooldownStore
    if not Store then return end

    mainFrame = CreateFrame("Frame", "ZaeUIDefensivesV3Floating", UIParent, "BackdropTemplate")
    mainFrame:SetSize((db() and db().frameWidth) or 250, 100)

    -- Restore saved position, falling back to screen center.
    local point, relTo, relPoint, x, y
    local fp = db() and db().framePoint
    if fp and fp[1] then
        point, relTo, relPoint, x, y = fp[1], fp[2], fp[3], fp[4], fp[5]
    else
        point, relPoint, x, y = "CENTER", "CENTER", 0, 0
    end
    mainFrame:ClearAllPoints()
    mainFrame:SetPoint(point or "CENTER", relTo, relPoint or "CENTER", x or 0, y or 0)

    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(not (db() and db().trackerLocked))
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", function(f)
        if not (db() and db().trackerLocked) then f:StartMoving() end
    end)
    mainFrame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        local p, _, rp, px, py = f:GetPoint()
        if db() then db().framePoint = { p, nil, rp, px, py } end
    end)
    if ZaeUI_Shared and ZaeUI_Shared.applyBackdrop then
        ZaeUI_Shared.applyBackdrop(mainFrame)
    end
    mainFrame:SetAlpha(((db() and db().trackerOpacity) or 80) / 100)

    -- Subscribe to store events
    Store:RegisterCallback("CooldownStart",      onCooldownStart)
    Store:RegisterCallback("CooldownEnd",        onCooldownEnd)
    Store:RegisterCallback("BuffStart",          onBuffStart)
    Store:RegisterCallback("BuffEnd",            onBuffEnd)
    Store:RegisterCallback("KnownSpellsChanged", function() refresh() end)
    Store:RegisterCallback("PlayerAdded",        function() refresh() end)
    Store:RegisterCallback("PlayerRemoved",      function() refresh() end)

    -- React to zone transitions (IsInRaid may change)
    local zoneFrame = CreateFrame("Frame")
    zoneFrame:SetScript("OnEvent", function() D:ApplyMode() end)
    zoneFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    zoneFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

    D:ApplyMode()
end

ns.Modules.FloatingDisplay = D
return D

-- ZaeUI_Defensives/Modules/FloatingDisplay.lua
-- Floating draggable tracker for v3 — consumes CooldownStore events.
-- Displays all known spells per player (ready and on-cooldown) with active
-- glow while the defensive buff is up.
-- luacheck: no self

local _, ns = ...
ns.Modules = ns.Modules or {}
local Util = ns.Utils and ns.Utils.Util
local Store = nil

local D = {}

-- UI state
local mainFrame
local rowPool   = {}
local iconIndex = {}  -- [guid][spellID] = iconFrame, maintained by refresh
local activeRows = {} -- ordered list of currently visible rows

-- Layout constants
local ROW_HEIGHT = 24
local ICON_SIZE  = 20
local ICON_GAP   = 2
local NAME_WIDTH = 96  -- reserved space for player name before icons
local PAD_X      = 4

-- Lazily resolved at Init time, since IconWidget loads after Util but the
-- module-local upvalue resolution happens at file-load time.
local IconWidget

local function db() return ZaeUI_DefensivesDB end

local function roleOrder(role)
    return ZaeUI_Shared and ZaeUI_Shared.roleOrder and ZaeUI_Shared.roleOrder(role) or 3
end

local function classColorHex(class)
    if ZaeUI_Shared and ZaeUI_Shared.classColorHex then
        return ZaeUI_Shared.classColorHex(class)
    end
    return "ffffff"
end

local function shouldDisplay(cd, info, rec)
    return Util and Util.ShouldDisplayCooldown
        and Util.ShouldDisplayCooldown(cd, info, rec, db())
end

-- ------------------------------------------------------------------
-- Pool helpers
-- ------------------------------------------------------------------

local ICON_OPTS = {
    countFont = "NumberFontNormal",
    countAnchor = "BOTTOMRIGHT",
    countOffsetX = -2,
    countOffsetY = 1,
}

local function acquireIcon(parent)
    return IconWidget.Acquire(parent, ICON_SIZE, ICON_OPTS)
end

local function releaseIcon(f)
    IconWidget.Release(f)
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
                IconWidget.Apply(icon, entry.cd, entry.info)
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
        IconWidget.Apply(icon, cd, ns.SpellData and ns.SpellData[cd.spellID])
    else
        refresh()  -- unknown icon: full rebuild
    end
end

local function onCooldownEnd(guid, spellID, cd)
    if not mainFrame or not mainFrame:IsShown() then return end
    local icon = iconIndex[guid] and iconIndex[guid][spellID]
    if icon then
        IconWidget.Apply(icon, cd, ns.SpellData and ns.SpellData[cd.spellID])
    end
end

local function onBuffStart(guid, spellID, cd)
    if not mainFrame or not mainFrame:IsShown() then return end
    local icon = iconIndex[guid] and iconIndex[guid][spellID]
    if icon then
        IconWidget.StartGlow(icon, ns.SpellData and ns.SpellData[cd.spellID])
    end
end

local function onBuffEnd(guid, spellID)
    if not mainFrame or not mainFrame:IsShown() then return end
    local icon = iconIndex[guid] and iconIndex[guid][spellID]
    IconWidget.StopGlow(icon)
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
    IconWidget = ns.Core and ns.Core.IconWidget
    if not Store or not IconWidget then return end

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

-- ZaeUI_Defensives: Anchored unit-frame display
-- Shows cooldown icon grids attached to Blizzard party/raid unit frames

local _, ns = ...

-- Local API refs
local CreateFrame = CreateFrame
local GetTime = GetTime
local C_Spell = C_Spell
local UnitName = UnitName
local UnitIsUnit = UnitIsUnit
local UnitExists = UnitExists
local IsInRaid = IsInRaid
local GetNumGroupMembers = GetNumGroupMembers
local string_format = string.format
local math_floor = math.floor
local table_sort = table.sort
local pairs = pairs
local ipairs = ipairs

-- Constants
local UPDATE_HZ = 0.1
local TIMER_THRESHOLD_CRITICAL = 10
local TIMER_THRESHOLD_WARNING = 30
local FALLBACK_ICON = 134400
local CAT_ORDER = { external = 1, raidwide = 2, personal = 3 }

--- Comparator for sorting spells by category then spellID.
--- @param a number spellID
--- @param b number spellID
--- @return boolean
local spellData_ref
local function spellComparator(a, b)
    local infoA = spellData_ref[a]
    local infoB = spellData_ref[b]
    local ca = CAT_ORDER[infoA and infoA.category or ""] or 99
    local cb = CAT_ORDER[infoB and infoB.category or ""] or 99
    if ca ~= cb then return ca < cb end
    return a < b
end

-- Anchor config lookup
local ANCHOR_CONFIG = {
    BOTTOM      = { groupPoint = "TOP",      framePoint = "BOTTOM",      horizontal = true,  iconGrow = 1 },
    BOTTOMLEFT  = { groupPoint = "TOPLEFT",   framePoint = "BOTTOMLEFT",  horizontal = true,  iconGrow = 1 },
    BOTTOMRIGHT = { groupPoint = "TOPRIGHT",  framePoint = "BOTTOMRIGHT", horizontal = true,  iconGrow = -1 },
    TOP         = { groupPoint = "BOTTOM",    framePoint = "TOP",         horizontal = true,  iconGrow = 1 },
    LEFT        = { groupPoint = "RIGHT",     framePoint = "LEFT",        horizontal = false, iconGrow = -1 },
    RIGHT       = { groupPoint = "LEFT",      framePoint = "RIGHT",       horizontal = false, iconGrow = 1 },
}

-- State
local rows = {}            -- { unit -> rowFrame }
local activeIcons = {}     -- flat array of icons with active cooldowns
local activeIconCount = 0
local updateFrame
local spellIconCache = {}

-- Frame detection ----------------------------------------------------------

--- Check if an object is a WoW Frame (table or userdata).
--- @param obj any
--- @return boolean
local function isFrameObject(obj)
    if not obj then return false end
    local t = type(obj)
    if t ~= "table" and t ~= "userdata" then return false end
    return type(obj.GetObjectType) == "function"
        or type(obj.IsVisible) == "function"
end

--- Get the unit token from a frame (handles Blizzard's .unit and :GetAttribute).
--- @param f table Frame object
--- @return string|nil unit
local function getFrameUnit(f)
    if f.unit then return f.unit end
    if f.GetAttribute then
        local u = f:GetAttribute("unit")
        if u then return u end
    end
    return nil
end

--- Check if a frame matches a unit token.
--- @param f table Frame object
--- @param unit string Unit token
--- @return boolean
local function frameMatchesUnit(f, unit)
    local fu = getFrameUnit(f)
    if not fu then return false end
    return UnitIsUnit(fu, unit)
end

-- Pre-generated frame name lists
local compactPartyNames = {}
for i = 1, 5 do compactPartyNames[i] = "CompactPartyFrameMember" .. i end

local compactRaidNames = {}
for i = 1, 40 do compactRaidNames[i] = "CompactRaidFrame" .. i end

local compactRaidKGTNames = {}
do
    local idx = 0
    for g = 1, 8 do
        for m = 1, 5 do
            idx = idx + 1
            compactRaidKGTNames[idx] = string_format("CompactRaidGroup%dMember%d", g, m)
        end
    end
end

--- Find the Blizzard unit frame for a unit token.
--- @param unit string
--- @return table|nil frame
local function getUnitFrame(unit)
    -- 1. Compact Party
    for _, name in ipairs(compactPartyNames) do
        local f = _G[name]
        if f and isFrameObject(f) and f.IsVisible and f:IsVisible() and frameMatchesUnit(f, unit) then
            return f
        end
    end
    -- 2. Compact Raid
    for _, name in ipairs(compactRaidNames) do
        local f = _G[name]
        if f and isFrameObject(f) and f.IsVisible and f:IsVisible() and frameMatchesUnit(f, unit) then
            return f
        end
    end
    -- 3. Compact Raid KGT
    for _, name in ipairs(compactRaidKGTNames) do
        local f = _G[name]
        if f and isFrameObject(f) and f.IsVisible and f:IsVisible() and frameMatchesUnit(f, unit) then
            return f
        end
    end
    -- 4. Dynamic Party Pool (Dragonflight+)
    if PartyFrame and PartyFrame.PartyMemberFramePool then
        for pf in PartyFrame.PartyMemberFramePool:EnumerateActive() do
            if pf and isFrameObject(pf) and pf.IsVisible and pf:IsVisible() and frameMatchesUnit(pf, unit) then
                return pf
            end
        end
    end
    return nil
end

-- Icon creation ------------------------------------------------------------

--- Create a cooldown icon button.
--- @param parent table Parent row frame
--- @param spellID number
--- @return table icon
local function createIcon(parent, spellID)
    local icon = CreateFrame("Button", nil, parent)
    icon:SetSize(28, 28)

    icon.tex = icon:CreateTexture(nil, "ARTWORK")
    icon.tex:SetAllPoints()
    if spellIconCache[spellID] == nil then
        spellIconCache[spellID] = C_Spell.GetSpellTexture(spellID) or false
    end
    icon.tex:SetTexture(spellIconCache[spellID] or FALLBACK_ICON)

    icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.cooldown:SetAllPoints()
    icon.cooldown:SetDrawEdge(false)
    icon.cooldown:SetHideCountdownNumbers(true)

    icon.timerText = icon:CreateFontString(nil, "OVERLAY")
    icon.timerText:SetFont("Interface\\AddOns\\ZaeUI_Shared\\Fonts\\Roboto.ttf", 10, "OUTLINE")
    icon.timerText:SetPoint("CENTER", 0, 0)
    icon.timerText:Hide()

    icon.chargeText = icon:CreateFontString(nil, "OVERLAY")
    icon.chargeText:SetFont("Interface\\AddOns\\ZaeUI_Shared\\Fonts\\Roboto.ttf", 9, "OUTLINE")
    icon.chargeText:SetPoint("BOTTOMRIGHT", 2, -2)
    icon.chargeText:Hide()

    icon.spellID = spellID
    icon.endTime = nil
    icon.duration = nil
    icon.chargeCount = nil
    icon.chargeMax = nil

    -- Tooltip
    icon:EnableMouse(true)
    icon:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(self.spellID)
        GameTooltip:Show()
    end)
    icon:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return icon
end

--- Format seconds for display.
--- @param seconds number
--- @return string
local function formatTime(seconds)
    if seconds >= 60 then
        return string_format("%d:%02d", math_floor(seconds / 60), math_floor(seconds % 60))
    end
    return string_format("%d", math_floor(seconds))
end

--- Update a single icon's visual state.
--- @param icon table
--- @param now number Current GetTime()
local function updateIconVisual(icon, now)
    -- Charge badge
    if icon.chargeCount and icon.chargeMax and icon.chargeMax > 1 then
        icon.chargeText:SetText(tostring(icon.chargeCount))
        icon.chargeText:Show()
    else
        icon.chargeText:Hide()
    end

    if icon.endTime and icon.endTime > now then
        -- On cooldown
        local remaining = icon.endTime - now
        -- Only desaturate when no charges remain
        local hasChargesLeft = icon.chargeCount and icon.chargeCount > 0
        icon.tex:SetDesaturated(not hasChargesLeft)
        icon.timerText:Show()
        icon.timerText:SetText(formatTime(remaining))
        if remaining < TIMER_THRESHOLD_CRITICAL then
            icon.timerText:SetTextColor(1, 0.2, 0.2)
        elseif remaining < TIMER_THRESHOLD_WARNING then
            icon.timerText:SetTextColor(1, 0.6, 0)
        else
            icon.timerText:SetTextColor(1, 1, 1)
        end
    else
        -- Ready
        icon.tex:SetDesaturated(false)
        icon.timerText:Hide()
        icon.cooldown:Clear()
        icon.endTime = nil
        icon.duration = nil
    end
end

-- Row creation and layout --------------------------------------------------

--- Apply grid layout to icons in a row.
--- @param row table Row frame containing .icons array
local function applyGridLayout(row)
    local db = ns.db
    if not db then return end
    local iconSize = db.anchoredIconSize or 28
    local spacing = db.anchoredSpacing or 2
    local perRow = db.anchoredIconsPerRow or 4
    local side = db.anchoredSide or "BOTTOM"
    local config = ANCHOR_CONFIG[side] or ANCHOR_CONFIG.BOTTOM

    for i, icon in ipairs(row.icons) do
        icon:ClearAllPoints()
        icon:SetSize(iconSize, iconSize)

        local idx = i - 1 -- 0-based
        local col = idx % perRow
        local line = math_floor(idx / perRow)

        if config.horizontal then
            -- Horizontal layout: icons in rows
            local x = col * (iconSize + spacing)
            local y = -line * (iconSize + spacing)
            if side == "TOP" then y = line * (iconSize + spacing) end
            if config.iconGrow == -1 then
                -- Right-to-left: anchor from TOPRIGHT
                icon:SetPoint("TOPRIGHT", row, "TOPRIGHT", -x, y)
            else
                icon:SetPoint("TOPLEFT", row, "TOPLEFT", x, y)
            end
        else
            -- Vertical layout: icons in columns
            local y = -col * (iconSize + spacing)
            local x = line * (iconSize + spacing)
            if config.iconGrow == -1 then
                -- Left-ward columns: anchor from TOPRIGHT
                icon:SetPoint("TOPRIGHT", row, "TOPRIGHT", -x, y)
            else
                icon:SetPoint("TOPLEFT", row, "TOPLEFT", x, y)
            end
        end

        icon:Show()
    end
end

--- Create or retrieve a row for a unit.
--- @param unit string
--- @param unitFrame table Blizzard unit frame
--- @return table row
local function ensureRow(unit, unitFrame)
    if rows[unit] then
        rows[unit]:SetParent(unitFrame)
        return rows[unit]
    end

    local row = CreateFrame("Frame", nil, unitFrame)
    row:SetSize(1, 1)
    row.icons = {}
    row.iconBySpell = {}
    row.unit = unit
    rows[unit] = row
    return row
end

--- Anchor a row to its unit frame.
--- @param row table
--- @param unitFrame table
local function anchorRow(row, unitFrame)
    local db = ns.db
    if not db then return end
    local side = db.anchoredSide or "BOTTOM"
    local config = ANCHOR_CONFIG[side] or ANCHOR_CONFIG.BOTTOM
    local offsetX = db.anchoredOffsetX or 0
    local offsetY = db.anchoredOffsetY or 0

    row:ClearAllPoints()
    row:SetPoint(config.groupPoint, unitFrame, config.framePoint, offsetX, offsetY)
    row:SetFrameStrata(unitFrame:GetFrameStrata() or "MEDIUM")
    row:SetFrameLevel((unitFrame:GetFrameLevel() or 10) + 20)
end

-- Active icon tracking for OnUpdate ----------------------------------------

--- Register an icon as having an active cooldown.
--- @param icon table
local function registerActiveIcon(icon)
    -- Check if already registered
    for i = 1, activeIconCount do
        if activeIcons[i] == icon then return end
    end
    activeIconCount = activeIconCount + 1
    activeIcons[activeIconCount] = icon
end

-- Timer OnUpdate -----------------------------------------------------------

local updateElapsed = 0

local function onUpdate(_, elapsed)
    updateElapsed = updateElapsed + elapsed
    if updateElapsed < UPDATE_HZ then return end
    updateElapsed = 0

    local now = GetTime()
    local i = 1
    while i <= activeIconCount do
        local icon = activeIcons[i]
        if icon.endTime and icon.endTime > now then
            updateIconVisual(icon, now)
            i = i + 1
        else
            -- Cooldown expired
            updateIconVisual(icon, now)
            activeIcons[i] = activeIcons[activeIconCount]
            activeIcons[activeIconCount] = nil
            activeIconCount = activeIconCount - 1
        end
    end

    -- Stop timer if no active icons
    if activeIconCount == 0 then
        updateFrame:SetScript("OnUpdate", nil)
    end
end

local function startUpdateTimer()
    updateElapsed = 0
    updateFrame:SetScript("OnUpdate", onUpdate)
end

-- Public API ---------------------------------------------------------------

--- Initialize the anchored display system.
function ns.frameDisplay_Init()
    updateFrame = CreateFrame("Frame")
end

--- Hide all anchored rows and clear active icons.
function ns.frameDisplay_HideAll()
    for _, row in pairs(rows) do
        for _, icon in ipairs(row.icons) do
            icon:Hide()
        end
        row:Hide()
    end
    -- Wipe rows so they are re-created from scratch on next refresh
    for k in pairs(rows) do rows[k] = nil end
    -- Clear active icons
    for i = 1, activeIconCount do
        activeIcons[i] = nil
    end
    activeIconCount = 0
    if updateFrame then
        updateFrame:SetScript("OnUpdate", nil)
    end
end

--- Refresh all anchored rows from current groupData.
function ns.frameDisplay_RefreshAll()
    local db = ns.db
    if not db then return end
    if not db.trackerEnabled then return end
    if db.displayMode ~= "anchored" then return end

    -- Disable in raid (too many frames, use floating tracker instead)
    if IsInRaid() then return end

    -- Hide existing rows (without wiping — reuse on refresh)
    for _, row in pairs(rows) do
        for _, icon in ipairs(row.icons) do
            icon:Hide()
        end
        row:Hide()
    end
    -- Clear active icons for this refresh cycle
    for i = 1, activeIconCount do
        activeIcons[i] = nil
    end
    activeIconCount = 0
    if updateFrame then
        updateFrame:SetScript("OnUpdate", nil)
    end

    -- Must be in a group
    if not ns.isInAnyGroup() then return end

    local groupData = ns.groupData
    local spellData = ns.spellData
    if not groupData or not spellData then return end

    local now = GetTime()
    local showPlayer = db.anchoredShowPlayer
    local myName = UnitName("player")

    -- Collect units
    local units = {}
    local numMembers = GetNumGroupMembers()
    local isRaid = IsInRaid()
    local count = isRaid and numMembers or (numMembers - 1)
    for i = 1, count do
        local unit = isRaid and ("raid" .. i) or ("party" .. i)
        if UnitExists(unit) then
            if showPlayer or not UnitIsUnit(unit, "player") then
                units[#units + 1] = unit
            end
        end
    end
    if showPlayer and UnitExists("player") and not isRaid then
        -- In party, player is not in party1-4
        local found = false
        for _, u in ipairs(units) do
            if UnitIsUnit(u, "player") then found = true; break end
        end
        if not found then
            units[#units + 1] = "player"
        end
    end

    -- Process each unit
    local hasActiveCD = false
    for _, unit in ipairs(units) do
        local unitFrame = getUnitFrame(unit)
        if unitFrame then
            local playerName = UnitName(unit)
            local data = playerName and groupData[playerName]
            if data and data.spells then
                -- Collect spells to show
                local spellList = {}
                for spellID in pairs(data.spells) do
                    local info = spellData[spellID]
                    if info then
                        local cat = info.category
                        local show = (cat == "external" and db.trackerShowExternal ~= false)
                                  or (cat == "personal" and db.trackerShowPersonal ~= false)
                                  or (cat == "raidwide" and db.trackerShowRaidwide ~= false)
                        if show and not (cat == "external" and db.trackerHideOwnExternals and playerName == myName) then
                            spellList[#spellList + 1] = spellID
                        end
                    end
                end

                -- Sort spells by category order then spellID for stability
                spellData_ref = spellData
                table_sort(spellList, spellComparator)

                if #spellList > 0 then
                    local row = ensureRow(unit, unitFrame)
                    anchorRow(row, unitFrame)

                    -- Create/update icons
                    for i, spellID in ipairs(spellList) do
                        local icon = row.iconBySpell[spellID]
                        if not icon then
                            icon = createIcon(row, spellID)
                            row.iconBySpell[spellID] = icon
                        end
                        row.icons[i] = icon

                        -- Set charge data
                        local chargeData = data.charges and data.charges[spellID]
                        if chargeData then
                            icon.chargeCount = chargeData.current
                            icon.chargeMax = chargeData.max
                        else
                            icon.chargeCount = nil
                            icon.chargeMax = nil
                        end

                        -- Set cooldown state
                        local cdEnd = data.cooldowns[spellID]
                        if cdEnd and cdEnd > now then
                            local remaining = cdEnd - now
                            icon.endTime = cdEnd
                            icon.duration = remaining
                            icon.cooldown:SetCooldown(now, remaining)
                            registerActiveIcon(icon)
                            hasActiveCD = true
                        else
                            icon.endTime = nil
                            icon.duration = nil
                            icon.cooldown:Clear()
                        end
                        updateIconVisual(icon, now)
                    end

                    -- Hide extra icons
                    for i = #spellList + 1, #row.icons do
                        if row.icons[i] then
                            row.icons[i]:Hide()
                            row.icons[i] = nil
                        end
                    end

                    applyGridLayout(row)
                    row:Show()
                end
            end
        end
    end

    -- Start timer if needed
    if hasActiveCD and updateFrame then
        startUpdateTimer()
    end
end

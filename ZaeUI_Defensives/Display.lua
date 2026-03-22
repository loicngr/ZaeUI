-- ZaeUI_Defensives: Floating tracker display
-- Shows group members' defensive cooldowns in real time

local _, ns = ...

-- Local API refs
local CreateFrame = CreateFrame
local GetTime = GetTime
local C_Spell = C_Spell
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitName = UnitName
local IsInRaid = IsInRaid
local GetNumGroupMembers = GetNumGroupMembers
local math_max = math.max
local string_format = string.format
local pairs = pairs
local sort = table.sort

-- Constants
local FRAME_WIDTH = 220
local FRAME_MIN_HEIGHT = 80
local ROW_HEIGHT = 22
local ICON_SIZE = 18
local PADDING = 8
local ROLE_ORDER = { TANK = 1, HEALER = 2, DAMAGER = 3, NONE = 4 }
local CAT_ORDER = { external = 1, raidwide = 2, personal = 3 }

--- Comparator for sorting entries by role, then player name, then category.
local function entryComparator(a, b)
    local ra = ROLE_ORDER[a.role] or 4
    local rb = ROLE_ORDER[b.role] or 4
    if ra ~= rb then return ra < rb end
    if a.playerName ~= b.playerName then return a.playerName < b.playerName end
    local ca = CAT_ORDER[a.category] or 99
    local cb = CAT_ORDER[b.category] or 99
    return ca < cb
end

-- State
local trackerFrame
local rows = {}
local spellIconCache = {}
local updateFrame
local sortedEntries = {}
local roleCache = {}

--- Create the main tracker frame.
local function createTrackerFrame()
    trackerFrame = CreateFrame("Frame", "ZaeUI_DefensivesFrame", UIParent, "BackdropTemplate")
    trackerFrame:SetSize(FRAME_WIDTH, FRAME_MIN_HEIGHT)
    trackerFrame:SetPoint("CENTER")
    ns.applyBackdrop(trackerFrame)
    trackerFrame:SetFrameStrata("MEDIUM")
    trackerFrame:SetClampedToScreen(true)
    trackerFrame:SetMovable(true)
    trackerFrame:EnableMouse(true)
    trackerFrame:RegisterForDrag("LeftButton")
    trackerFrame:SetScript("OnDragStart", function(self)
        if ns.db and ns.db.trackerLocked then return end
        self:StartMoving()
    end)
    trackerFrame:SetScript("OnDragStop", function(self)
        if ns.db and ns.db.trackerLocked then return end
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        if ns.db then
            ns.db.framePoint = { point, nil, relPoint, x, y }
        end
    end)

    -- Title
    local title = trackerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", PADDING, -PADDING)
    title:SetText("|cff00ccffDefensives|r")
    trackerFrame.title = title

    -- Collapse button
    local collapseBtn = CreateFrame("Button", nil, trackerFrame)
    collapseBtn:SetSize(14, 14)
    collapseBtn:SetPoint("TOPRIGHT", -PADDING, -PADDING)
    local collapseIcon = collapseBtn:CreateTexture(nil, "ARTWORK")
    collapseIcon:SetAllPoints()
    local initCollapsed = ns.db and ns.db.collapsed
    collapseIcon:SetTexture(initCollapsed
        and "Interface\\Buttons\\UI-PlusButton-UP"
        or "Interface\\Buttons\\UI-MinusButton-UP")
    collapseIcon:SetAlpha(0.7)
    collapseBtn:SetScript("OnEnter", function() collapseIcon:SetAlpha(1) end)
    collapseBtn:SetScript("OnLeave", function() collapseIcon:SetAlpha(0.7) end)
    collapseBtn:SetScript("OnClick", function()
        local db = ns.db
        if db then db.collapsed = not db.collapsed end
        local collapsed = db and db.collapsed
        collapseIcon:SetTexture(collapsed
            and "Interface\\Buttons\\UI-PlusButton-UP"
            or "Interface\\Buttons\\UI-MinusButton-UP")
        ns.refreshTrackerDisplay()
    end)
    trackerFrame.collapseBtn = collapseBtn

    -- Content area
    trackerFrame.content = CreateFrame("Frame", nil, trackerFrame)
    trackerFrame.content:SetPoint("TOPLEFT", PADDING, -(PADDING + 14))
    trackerFrame.content:SetPoint("BOTTOMRIGHT", -PADDING, PADDING)

    return trackerFrame
end

--- Create or reuse a row in the tracker.
--- @param index number Row index
--- @param parent table Parent frame
--- @return table row The row frame
local function getRow(index, parent)
    if rows[index] then return rows[index] end

    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))
    row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON_SIZE, ICON_SIZE)
    row.icon:SetPoint("LEFT", 0, 0)

    -- Invisible overlay to capture mouse events on the icon
    row.iconHitFrame = CreateFrame("Frame", nil, row)
    row.iconHitFrame:SetAllPoints(row.icon)
    row.iconHitFrame:EnableMouse(true)
    row.iconHitFrame:SetScript("OnEnter", function(self)
        local id = self._spellID
        if not id then return end
        local info = C_Spell.GetSpellInfo(id)
        if not info then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(info.name, 1, 1, 1)
        GameTooltip:Show()
    end)
    row.iconHitFrame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Green border overlay shown when a defensive buff is active
    row.activeBorder = row:CreateTexture(nil, "OVERLAY")
    row.activeBorder:SetPoint("TOPLEFT", row.icon, "TOPLEFT", -1, 1)
    row.activeBorder:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 1, -1)
    row.activeBorder:SetColorTexture(0, 1, 0, 0.6)
    row.activeBorder:Hide()

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    row.name:SetWidth(100)
    row.name:SetJustifyH("LEFT")

    row.status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.status:SetPoint("RIGHT", row, "RIGHT", -4, 0)

    rows[index] = row
    return row
end

--- Build a role lookup table for all current group members.
--- Populates the module-level roleCache table in-place.
local function buildRoleCache()
    for k in pairs(roleCache) do roleCache[k] = nil end
    local numMembers = GetNumGroupMembers()
    local isRaid = IsInRaid()
    local count = isRaid and numMembers or (numMembers - 1)
    for i = 1, count do
        local unit = isRaid and ("raid" .. i) or ("party" .. i)
        local name = UnitName(unit)
        if name then
            roleCache[name] = UnitGroupRolesAssigned(unit) or "NONE"
        end
    end
    local myName = UnitName("player")
    if myName then
        roleCache[myName] = UnitGroupRolesAssigned("player") or "NONE"
    end
end

--- Refresh the tracker display with current group data.
function ns.refreshTrackerDisplay()
    if not trackerFrame then return end
    if not trackerFrame:IsShown() then return end

    local content = trackerFrame.content
    local db = ns.db or {}

    -- Collapsed mode: hide content, shrink frame to header only
    if db.collapsed then
        content:Hide()
        local headerHeight = (PADDING * 2) + 14
        trackerFrame:SetHeight(headerHeight)
        return
    end
    content:Show()

    local now = GetTime()
    local spellData = ns.spellData or {}
    local groupData = ns.groupData or {}

    -- Hide all existing rows
    for i = 1, #rows do
        rows[i]:Hide()
    end

    -- Build role cache for sorting
    buildRoleCache()

    -- Collect entries
    local entryCount = 0
    for playerName, data in pairs(groupData) do
        for spellID, _ in pairs(data.spells) do
            local info = spellData[spellID]
            if info then
                local cat = info.category
                local show = (cat == "external" and db.trackerShowExternal ~= false)
                          or (cat == "personal" and db.trackerShowPersonal ~= false)
                          or (cat == "raidwide" and db.trackerShowRaidwide ~= false)
                if show then
                    entryCount = entryCount + 1
                    local e = sortedEntries[entryCount]
                    if not e then
                        e = {}
                        sortedEntries[entryCount] = e
                    end
                    e.playerName = playerName
                    e.spellID = spellID
                    e.category = cat
                    e.role = roleCache[playerName] or "NONE"
                    local cdEnd = data.cooldowns[spellID]
                    e.onCD = cdEnd ~= nil and cdEnd > now
                    e.remaining = e.onCD and (cdEnd - now) or 0
                    e.buffActive = false
                end
            end
        end
    end

    -- Clear stale entries beyond current count
    for i = entryCount + 1, #sortedEntries do sortedEntries[i] = nil end

    -- Sort by role order, then player name, then category order
    sort(sortedEntries, entryComparator)

    -- Render rows
    for i = 1, entryCount do
        local entry = sortedEntries[i]
        local row = getRow(i, content)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -((i - 1) * ROW_HEIGHT))
        row:SetPoint("RIGHT", content, "RIGHT", 0, 0)

        local spellID = entry.spellID
        row.iconHitFrame._spellID = spellID

        -- Cache spell texture
        if spellIconCache[spellID] == nil then
            spellIconCache[spellID] = C_Spell.GetSpellTexture(spellID) or false
        end
        local iconTex = spellIconCache[spellID]
        if iconTex then
            row.icon:SetTexture(iconTex)
            row.icon:SetDesaturated(entry.onCD)
            row.icon:Show()
        else
            row.icon:Hide()
        end

        row.activeBorder:Hide()

        -- Player name with class color
        local hex = ns.getClassColorHex and ns.getClassColorHex(entry.playerName) or "ffffff"
        row.name:SetText("|cff" .. hex .. entry.playerName .. "|r")

        -- Status text: Active > On cooldown > Ready
        if entry.onCD then
            row.status:SetText(string_format("|cffff4444%.1fs|r", entry.remaining))
        else
            row.status:SetText("|cff44ff44Ready|r")
        end

        row:Show()
    end

    -- Resize frame
    local totalHeight = (PADDING * 2) + 14 + (entryCount * ROW_HEIGHT)
    trackerFrame:SetHeight(math_max(FRAME_MIN_HEIGHT, totalHeight))
end

--- Apply the saved frame opacity.
function ns.applyFrameOpacity()
    if not trackerFrame then return end
    local opacity = (ns.db and ns.db.trackerOpacity or 80) / 100
    trackerFrame:SetAlpha(opacity)
end

-- Update timer for smooth cooldown display
updateFrame = CreateFrame("Frame")
local updateElapsed = 0

local function startUpdateTimer()
    updateElapsed = 0
    updateFrame:SetScript("OnUpdate", function(_, elapsed)
        updateElapsed = updateElapsed + elapsed
        if updateElapsed >= 0.1 then
            updateElapsed = 0
            ns.refreshTrackerDisplay()
        end
    end)
end

local function stopUpdateTimer()
    updateFrame:SetScript("OnUpdate", nil)
end

--- Restore saved frame position.
local function restoreFramePosition()
    if ns.db and ns.db.framePoint then
        local p = ns.db.framePoint
        trackerFrame:ClearAllPoints()
        trackerFrame:SetPoint(p[1], UIParent, p[3], p[4], p[5])
    end
end

--- Toggle the tracker frame visibility.
function ns.toggleTrackerDisplay()
    if not trackerFrame then
        createTrackerFrame()
    end
    if trackerFrame:IsShown() then
        trackerFrame:Hide()
        stopUpdateTimer()
    else
        restoreFramePosition()
        trackerFrame:Show()
        startUpdateTimer()
        ns.refreshTrackerDisplay()
    end
end

--- Show the tracker frame.
function ns.showTrackerDisplay()
    if not trackerFrame then
        createTrackerFrame()
    end
    restoreFramePosition()
    trackerFrame:Show()
    startUpdateTimer()
    ns.refreshTrackerDisplay()
end

--- Hide the tracker frame.
function ns.hideTrackerDisplay()
    if trackerFrame then
        trackerFrame:Hide()
    end
    stopUpdateTimer()
end

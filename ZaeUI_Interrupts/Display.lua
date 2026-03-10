-- ZaeUI_Interrupts: Floating tracker display
-- Shows group members' interrupt/stun cooldowns in real time

local _, ns = ...

local CreateFrame = CreateFrame
local UnitClass = UnitClass
local GetTime = GetTime
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local GetNumGroupMembers = GetNumGroupMembers
local IsInRaid = IsInRaid
local IsInGroup = IsInGroup
local UnitName = UnitName
local C_Spell = C_Spell
local math_max = math.max
local string_format = string.format
local table_sort = table.sort

local FRAME_WIDTH = 220
local FRAME_MIN_HEIGHT = 80
local ROW_HEIGHT = 22
local ICON_SIZE = 18
local PADDING = 8
local CATEGORY_LABELS = { interrupt = "Interrupts", stun = "Stuns & Others" }
local WHITE_COLOR = { r = 1, g = 1, b = 1 }

local trackerFrame
local rows = {}
local classColorCache = {}
local classColorHexCache = {}
local spellIconCache = {}
local updateFrame
local catEntriesInterrupt = {}
local catEntriesStun = {}

--- Sort comparator: on CD first, then by remaining time descending, then by name.
local function sortByRemainingDesc(a, b)
    if a.onCD ~= b.onCD then return a.onCD == true end
    if a.onCD then return a.remaining > b.remaining end
    return a.playerName < b.playerName
end

--- Create the main tracker frame.
local function createTrackerFrame()
    trackerFrame = CreateFrame("Frame", "ZaeUI_InterruptsFrame", UIParent, "BackdropTemplate")
    trackerFrame:SetSize(FRAME_WIDTH, FRAME_MIN_HEIGHT)
    trackerFrame:SetPoint("CENTER")
    trackerFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    trackerFrame:SetBackdropColor(0, 0, 0, 0.8)
    trackerFrame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    local opacity = (ns.db and ns.db.frameOpacity or 80) / 100
    trackerFrame:SetAlpha(opacity)
    trackerFrame:SetFrameStrata("MEDIUM")
    trackerFrame:SetClampedToScreen(true)
    trackerFrame:SetMovable(true)
    trackerFrame:EnableMouse(true)
    trackerFrame:RegisterForDrag("LeftButton")
    trackerFrame:SetScript("OnDragStart", function(self)
        if ns.db and ns.db.lockFrame then return end
        self:StartMoving()
    end)
    trackerFrame:SetScript("OnDragStop", function(self)
        if ns.db and ns.db.lockFrame then return end
        self:StopMovingOrSizing()
        -- Save position
        local point, _, relPoint, x, y = self:GetPoint()
        if ns.db then
            ns.db.framePoint = { point, nil, relPoint, x, y }
        end
    end)

    -- Title
    local title = trackerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", PADDING, -PADDING)
    title:SetText("|cff00ccffInterrupts|r")
    trackerFrame.title = title

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

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    row.name:SetWidth(100)
    row.name:SetJustifyH("LEFT")

    row.counter = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.counter:SetPoint("RIGHT", row, "RIGHT", -4, 0)

    row.status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.status:SetPoint("RIGHT", row.counter, "LEFT", -4, 0)

    rows[index] = row
    return row
end

--- Cache a class color and its hex representation.
--- @param playerName string
--- @param color table {r, g, b}
local function cacheClassColor(playerName, color)
    classColorCache[playerName] = color
    classColorHexCache[playerName] = string_format("%02x%02x%02x", color.r * 255, color.g * 255, color.b * 255)
end

--- Get class color hex string for a player name.
--- @param playerName string
--- @return string hex "rrggbb"
local function getClassColorHex(playerName)
    if classColorHexCache[playerName] then return classColorHexCache[playerName] end

    -- Try to find the unit ID for this player
    local numMembers = GetNumGroupMembers()
    for i = 1, numMembers do
        local unit = IsInRaid() and ("raid" .. i) or ("party" .. i)
        if UnitName(unit) == playerName then
            local _, className = UnitClass(unit)
            if className and RAID_CLASS_COLORS[className] then
                cacheClassColor(playerName, RAID_CLASS_COLORS[className])
                return classColorHexCache[playerName]
            end
        end
    end
    -- Check player
    if UnitName("player") == playerName then
        local _, className = UnitClass("player")
        if className and RAID_CLASS_COLORS[className] then
            cacheClassColor(playerName, RAID_CLASS_COLORS[className])
            return classColorHexCache[playerName]
        end
    end
    return "ffffff"
end

--- Check if a category is enabled in settings.
--- @param cat string "interrupt", "stun" or "other"
--- @return boolean
local function isCategoryEnabled(cat)
    local db = ns.db
    if not db then return true end
    if cat == "interrupt" then return db.showInterrupts ~= false end
    if cat == "stun" then return db.showStuns ~= false end
    return db.showOthers ~= false
end

--- Refresh the tracker display with current group data.
function ns.refreshDisplay()
    if not trackerFrame then return end
    if not trackerFrame:IsShown() then return end

    local content = trackerFrame.content
    local rowIndex = 0
    local now = GetTime()
    local spellData = ns.spellData or {}
    local db = ns.db or {}
    local hideReady = db.hideReady
    local sortByCD = db.sortByCD

    -- Hide all existing rows first
    for _, row in pairs(rows) do
        row:Hide()
    end

    -- Collect all entries, grouped by display category (reuse tables to reduce GC)
    local groupData = ns.groupData or {}
    local interruptEntries = catEntriesInterrupt
    local stunEntries = catEntriesStun
    local interruptCount, stunCount = 0, 0

    for playerName, data in pairs(groupData) do
        for spellID, _ in pairs(data.spells) do
            local info = spellData[spellID] or (db.customSpells and db.customSpells[spellID] and { category = "other" })
            if info then
                local spellCat = info.category or "other"
                if isCategoryEnabled(spellCat) then
                    local cdEnd = data.cooldowns[spellID]
                    local onCD = cdEnd ~= nil and cdEnd > now
                    if not hideReady or onCD then
                        local displayCat = (spellCat == "other") and "stun" or spellCat
                        local remaining = onCD and (cdEnd - now) or 0
                        if displayCat == "interrupt" then
                            interruptCount = interruptCount + 1
                            local e = interruptEntries[interruptCount]
                            if not e then
                                e = {}
                                interruptEntries[interruptCount] = e
                            end
                            e.playerName = playerName
                            e.spellID = spellID
                            e.onCD = onCD
                            e.remaining = remaining
                            e.counters = data.counters
                        else
                            stunCount = stunCount + 1
                            local e = stunEntries[stunCount]
                            if not e then
                                e = {}
                                stunEntries[stunCount] = e
                            end
                            e.playerName = playerName
                            e.spellID = spellID
                            e.onCD = onCD
                            e.remaining = remaining
                            e.counters = data.counters
                        end
                    end
                end
            end
        end
    end

    -- Sort entries within each category
    if sortByCD then
        if interruptCount > 1 then table_sort(interruptEntries, sortByRemainingDesc) end
        if stunCount > 1 then table_sort(stunEntries, sortByRemainingDesc) end
    end

    -- Render entries for a category
    local showCounter = db.showCounter
    for pass = 1, 2 do
        local entries = pass == 1 and interruptEntries or stunEntries
        local count = pass == 1 and interruptCount or stunCount
        local label = pass == 1 and CATEGORY_LABELS["interrupt"] or CATEGORY_LABELS["stun"]

        if count > 0 then
            -- Category header
            rowIndex = rowIndex + 1
            local headerRow = getRow(rowIndex, content)
            headerRow.icon:Hide()
            headerRow.name:SetText("|cffffcc00" .. label .. "|r")
            headerRow.name:SetWidth(200)
            headerRow.status:SetText("")
            headerRow.counter:SetText("")
            headerRow:Show()

            for i = 1, count do
                local entry = entries[i]
                rowIndex = rowIndex + 1
                local row = getRow(rowIndex, content)

                local spellID = entry.spellID
                if spellIconCache[spellID] == nil then
                    local spellInfo = C_Spell.GetSpellInfo(spellID)
                    spellIconCache[spellID] = (spellInfo and spellInfo.iconID) or false
                end
                local iconID = spellIconCache[spellID]
                if iconID then
                    row.icon:SetTexture(iconID)
                    row.icon:Show()
                else
                    row.icon:Hide()
                end

                row.name:SetText("|cff" .. getClassColorHex(entry.playerName) .. entry.playerName .. "|r")
                row.name:SetWidth(100)

                if entry.onCD then
                    row.status:SetText(string_format("|cffff4444%.1fs|r", entry.remaining))
                else
                    row.status:SetText("|cff44ff44Ready|r")
                end

                if showCounter then
                    local cnt = entry.counters and entry.counters[spellID] or 0
                    if cnt > 0 then
                        row.counter:SetText("|cffaaaaaa(" .. cnt .. ")|r")
                    else
                        row.counter:SetText("")
                    end
                else
                    row.counter:SetText("")
                end

                row:Show()
            end
        end
    end

    -- Resize frame
    local totalHeight = (PADDING * 2) + 14 + (rowIndex * ROW_HEIGHT)
    trackerFrame:SetHeight(math_max(FRAME_MIN_HEIGHT, totalHeight))
end

--- Apply the saved frame opacity.
function ns.applyFrameOpacity()
    if not trackerFrame then return end
    local opacity = (ns.db and ns.db.frameOpacity or 80) / 100
    trackerFrame:SetAlpha(opacity)
end

-- Update timer for smooth cooldown display (started/stopped with frame visibility)
updateFrame = CreateFrame("Frame")
local updateElapsed = 0

local function startUpdateTimer()
    updateElapsed = 0
    updateFrame:SetScript("OnUpdate", function(_, elapsed)
        updateElapsed = updateElapsed + elapsed
        if updateElapsed >= 0.1 then
            updateElapsed = 0
            ns.refreshDisplay()
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
function ns.toggleDisplay()
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
        ns.refreshDisplay()
    end
end

--- Show the tracker frame.
function ns.showDisplay()
    if not trackerFrame then
        createTrackerFrame()
    end
    restoreFramePosition()
    trackerFrame:Show()
    startUpdateTimer()
    ns.refreshDisplay()
end

--- Hide the tracker frame.
function ns.hideDisplay()
    if trackerFrame then
        trackerFrame:Hide()
    end
    stopUpdateTimer()
end

-- Auto-show/hide based on group status
local autoFrame = CreateFrame("Frame")
autoFrame:RegisterEvent("GROUP_JOINED")
autoFrame:RegisterEvent("GROUP_LEFT")
autoFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
autoFrame:SetScript("OnEvent", function()
    -- Clear class color caches on group changes
    for k in pairs(classColorCache) do classColorCache[k] = nil end
    for k in pairs(classColorHexCache) do classColorHexCache[k] = nil end

    if not ns.db then return end
    if not ns.db.showFrame then return end
    if ns.db.autoHide then
        if IsInGroup() or IsInRaid() then
            ns.showDisplay()
        else
            ns.hideDisplay()
        end
    end
end)

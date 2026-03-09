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

local FRAME_WIDTH = 220
local FRAME_MIN_HEIGHT = 80
local ROW_HEIGHT = 22
local ICON_SIZE = 18
local PADDING = 8
local CATEGORIES = { "interrupt", "stun", "other" }
local CATEGORY_LABELS = { interrupt = "Interrupts", stun = "Stuns & Others" }
local WHITE_COLOR = { r = 1, g = 1, b = 1 }

local trackerFrame
local rows = {}
local classColorCache = {}
local spellIconCache = {}
local updateFrame

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
    trackerFrame:SetFrameStrata("MEDIUM")
    trackerFrame:SetClampedToScreen(true)
    trackerFrame:SetMovable(true)
    trackerFrame:EnableMouse(true)
    trackerFrame:RegisterForDrag("LeftButton")
    trackerFrame:SetScript("OnDragStart", trackerFrame.StartMoving)
    trackerFrame:SetScript("OnDragStop", function(self)
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

--- Get class color for a player name.
--- @param playerName string
--- @return table color {r, g, b}
local function getClassColor(playerName)
    local cached = classColorCache[playerName]
    if cached then return cached end

    -- Try to find the unit ID for this player
    local numMembers = GetNumGroupMembers()
    for i = 1, numMembers do
        local unit = IsInRaid() and ("raid" .. i) or ("party" .. i)
        if UnitName(unit) == playerName then
            local _, className = UnitClass(unit)
            if className and RAID_CLASS_COLORS[className] then
                classColorCache[playerName] = RAID_CLASS_COLORS[className]
                return RAID_CLASS_COLORS[className]
            end
        end
    end
    -- Check player
    if UnitName("player") == playerName then
        local _, className = UnitClass("player")
        if className and RAID_CLASS_COLORS[className] then
            classColorCache[playerName] = RAID_CLASS_COLORS[className]
            return RAID_CLASS_COLORS[className]
        end
    end
    return WHITE_COLOR
end

--- Refresh the tracker display with current group data.
function ns.refreshDisplay()
    if not trackerFrame then return end
    if not trackerFrame:IsShown() then return end

    local content = trackerFrame.content
    local rowIndex = 0
    local now = GetTime()
    local spellData = ns.spellData or {}

    -- Hide all existing rows first
    for _, row in pairs(rows) do
        row:Hide()
    end

    -- Sort: interrupts first, then stuns/others
    local groupData = ns.groupData or {}
    local lastCategory = nil

    for _, cat in ipairs(CATEGORIES) do
        local displayCat = (cat == "other") and "stun" or cat

        for playerName, data in pairs(groupData) do
            for spellID, _ in pairs(data.spells) do
                local info = spellData[spellID] or (ns.db and ns.db.customSpells[spellID] and { category = "other" })
                if info then
                    local spellCat = info.category or "other"
                    local displaySpellCat = (spellCat == "other") and "stun" or spellCat
                    if displaySpellCat == displayCat and spellCat == cat then
                        -- Show category header if new category
                        if displayCat ~= lastCategory then
                            if CATEGORY_LABELS[displayCat] then
                                rowIndex = rowIndex + 1
                                local headerRow = getRow(rowIndex, content)
                                headerRow.icon:Hide()
                                headerRow.name:SetText("|cffffcc00" .. CATEGORY_LABELS[displayCat] .. "|r")
                                headerRow.name:SetWidth(200)
                                headerRow.status:SetText("")
                                headerRow.counter:SetText("")
                                headerRow:Show()
                                lastCategory = displayCat
                            end
                        end

                        rowIndex = rowIndex + 1
                        local row = getRow(rowIndex, content)

                        -- Icon (cached per spellID)
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

                        -- Player name with class color
                        local color = getClassColor(playerName)
                        row.name:SetText(string_format("|cff%02x%02x%02x%s|r",
                            color.r * 255, color.g * 255, color.b * 255, playerName))
                        row.name:SetWidth(100)

                        -- Cooldown status
                        local cdEnd = data.cooldowns[spellID]
                        if cdEnd and cdEnd > now then
                            local remaining = cdEnd - now
                            row.status:SetText(string_format("|cffff4444%.1fs|r", remaining))
                        else
                            row.status:SetText("|cff44ff44Ready|r")
                        end

                        -- Spell use counter
                        if ns.db and ns.db.showCounter then
                            local count = data.counters and data.counters[spellID] or 0
                            if count > 0 then
                                row.counter:SetText("|cffaaaaaa(" .. count .. ")|r")
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
        end
    end

    -- Resize frame
    local totalHeight = (PADDING * 2) + 14 + (rowIndex * ROW_HEIGHT)
    trackerFrame:SetHeight(math_max(FRAME_MIN_HEIGHT, totalHeight))
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
    -- Clear class color cache on group changes
    for k in pairs(classColorCache) do classColorCache[k] = nil end

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

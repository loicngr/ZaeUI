-- ZaeUI_Interrupts: Separate floating window for kick marker assignments
-- Shown when db.separateMarkerWindow is enabled

local _, ns = ...

local CreateFrame = CreateFrame
local pairs = pairs

local MARKER_ICON_SIZE = 16
local ROW_HEIGHT = 20
local PADDING = 8
local FRAME_WIDTH = 140

local markerFrame
local markerRows = {}
local displayEntries = {} -- reused table for refresh

--- Get class color hex, delegating to shared namespace utility.
local function getClassColorHex(playerName)
    return ns.getClassColorHex and ns.getClassColorHex(playerName) or "ffffff"
end

--- Create the marker display frame.
local function createMarkerFrame()
    markerFrame = CreateFrame("Frame", "ZaeUI_InterruptsMarkerFrame", UIParent, "BackdropTemplate")
    markerFrame:SetSize(FRAME_WIDTH, 60)
    markerFrame:SetPoint("CENTER")
    ns.applyBackdrop(markerFrame)
    markerFrame:SetFrameStrata("MEDIUM")
    markerFrame:SetClampedToScreen(true)
    markerFrame:SetMovable(true)
    markerFrame:EnableMouse(true)
    markerFrame:RegisterForDrag("LeftButton")
    markerFrame:SetScript("OnDragStart", function(self)
        if ns.db and ns.db.lockFrame then return end
        self:StartMoving()
    end)
    markerFrame:SetScript("OnDragStop", function(self)
        if ns.db and ns.db.lockFrame then return end
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        if ns.db then
            ns.db.markerWindowPoint = { point, nil, relPoint, x, y }
        end
    end)

    local title = markerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", PADDING, -PADDING)
    title:SetText("|cff00ccffKick Markers|r")

    markerFrame.content = CreateFrame("Frame", nil, markerFrame)
    markerFrame.content:SetPoint("TOPLEFT", PADDING, -(PADDING + 14))
    markerFrame.content:SetPoint("RIGHT", markerFrame, "RIGHT", -PADDING, 0)

    markerFrame:Hide()
    return markerFrame
end

--- Get or create a row in the marker display.
--- @param index number Row index
--- @param parent table Parent frame
--- @return table row
local function getRow(index, parent)
    if markerRows[index] then return markerRows[index] end

    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))
    row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)

    row.marker = row:CreateTexture(nil, "ARTWORK")
    row.marker:SetSize(MARKER_ICON_SIZE, MARKER_ICON_SIZE)
    row.marker:SetPoint("LEFT", 0, 0)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.marker, "RIGHT", 4, 0)
    row.name:SetJustifyH("LEFT")

    markerRows[index] = row
    return row
end

--- Restore saved frame position.
local function restorePosition()
    if ns.db and ns.db.markerWindowPoint then
        local p = ns.db.markerWindowPoint
        markerFrame:ClearAllPoints()
        markerFrame:SetPoint(p[1], UIParent, p[3], p[4], p[5])
    end
end

--- Refresh the marker display window.
function ns.refreshMarkerDisplay()
    local db = ns.db
    if not db then return end

    -- If option is disabled, hide and return
    if not db.separateMarkerWindow then
        if markerFrame then markerFrame:Hide() end
        return
    end

    local assignments = ns.markerAssignments or {}
    local groupData = ns.groupData or {}

    -- Collect only players currently in the group with an assignment (reuse table)
    local entries = displayEntries
    local count = 0
    for playerName, markIndex in pairs(assignments) do
        if groupData[playerName] then
            count = count + 1
            local e = entries[count]
            if not e then
                e = {}
                entries[count] = e
            end
            e.name = playerName
            e.mark = markIndex
        end
    end

    -- Clear stale entries beyond current count to release references
    for i = count + 1, #entries do entries[i] = nil end

    -- Hide if no assignments
    if count == 0 then
        if markerFrame then markerFrame:Hide() end
        return
    end

    -- Sort entries 1..count by marker index (insertion sort to avoid nil-hole issues)
    for i = 2, count do
        local key = entries[i]
        local j = i - 1
        while j >= 1 and entries[j].mark > key.mark do
            entries[j + 1] = entries[j]
            j = j - 1
        end
        entries[j + 1] = key
    end

    if not markerFrame then createMarkerFrame() end

    -- Hide all rows
    for i = 1, #markerRows do markerRows[i]:Hide() end

    -- Render rows
    local content = markerFrame.content
    for i = 1, count do
        local entry = entries[i]
        local row = getRow(i, content)
        row.marker:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. entry.mark)
        row.name:SetText("|cff" .. getClassColorHex(entry.name) .. entry.name .. "|r")
        row:Show()
    end

    -- Resize
    local totalHeight = (PADDING * 2) + 14 + (count * ROW_HEIGHT)
    markerFrame:SetHeight(totalHeight)

    -- Show and position
    if not markerFrame:IsShown() then
        restorePosition()
        markerFrame:Show()
    end
end

--- Apply frame opacity to marker window.
function ns.applyMarkerWindowOpacity()
    if not markerFrame then return end
    local opacity = (ns.db and ns.db.frameOpacity or 80) / 100
    markerFrame:SetAlpha(opacity)
end

-- ZaeUI_Interrupts: Floating tracker display
-- Shows group members' interrupt/stun cooldowns in real time

local _, ns = ...

local CreateFrame = CreateFrame
local GetTime = GetTime
local C_Spell = C_Spell
local math_max = math.max
local string_format = string.format


local FRAME_WIDTH = 220
local FRAME_MIN_HEIGHT = 80
local ROW_HEIGHT = 22
local ICON_SIZE = 18
local PADDING = 8
local CATEGORY_LABELS = { interrupt = "Interrupts", stun = "Stuns & Others" }
local CAT_KEYS = { "interrupt", "stun" }

local trackerFrame
local rows = {}
local spellIconCache = {}
local updateFrame
local catEntriesInterrupt = {}
local catEntriesStun = {}

--- Create the main tracker frame.
local function createTrackerFrame()
    trackerFrame = CreateFrame("Frame", "ZaeUI_InterruptsFrame", UIParent, "BackdropTemplate")
    trackerFrame:SetSize(FRAME_WIDTH, FRAME_MIN_HEIGHT)
    trackerFrame:SetPoint("CENTER")
    ns.applyBackdrop(trackerFrame)
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

    -- Collapse button (minimize/expand content)
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
        ns.refreshDisplay()
    end)
    trackerFrame.collapseBtn = collapseBtn

    -- Assign button (opens kick marker assignment panel)
    local assignBtn = CreateFrame("Button", nil, trackerFrame)
    assignBtn:SetSize(14, 14)
    assignBtn:SetPoint("RIGHT", collapseBtn, "LEFT", -4, 0)
    local assignIcon = assignBtn:CreateTexture(nil, "ARTWORK")
    assignIcon:SetAllPoints()
    assignIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_4")
    assignIcon:SetAlpha(0.7)
    assignBtn:SetScript("OnClick", function()
        if ns.toggleAssignPanel then ns.toggleAssignPanel() end
    end)
    assignBtn:SetScript("OnEnter", function(self)
        assignIcon:SetAlpha(1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Kick Marker Assignments")
        GameTooltip:AddLine("Only the group leader can assign markers.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    assignBtn:SetScript("OnLeave", function()
        assignIcon:SetAlpha(0.7)
        GameTooltip:Hide()
    end)

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

    row.marker = row:CreateTexture(nil, "ARTWORK")
    row.marker:SetSize(14, 14)
    row.marker:SetPoint("LEFT", row.icon, "RIGHT", 2, 0)
    row.marker:Hide()

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

--- Get class color hex, delegating to shared namespace utility.
local function getClassColorHex(playerName)
    return ns.getClassColorHex and ns.getClassColorHex(playerName) or "ffffff"
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
    local db = ns.db or {}

    -- Collapsed mode: hide content, shrink frame to header only
    if db.collapsed then
        content:Hide()
        local headerHeight = (PADDING * 2) + 14
        trackerFrame:SetHeight(headerHeight)
        return
    end
    content:Show()
    local rowIndex = 0
    local visualRow = 0
    local now = GetTime()
    local spellData = ns.spellData or {}
    local hideReady = db.hideReady

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

    -- Clear stale entries beyond current count to release references
    for i = interruptCount + 1, #interruptEntries do interruptEntries[i] = nil end
    for i = stunCount + 1, #stunEntries do stunEntries[i] = nil end

    -- Render entries for a category
    local showCounter = db.showCounter
    local showInlineMarker = not (db.separateMarkerWindow)
    local markerAssignments = ns.markerAssignments or {}
    for pass = 1, 2 do
        local entries = pass == 1 and interruptEntries or stunEntries
        local count = pass == 1 and interruptCount or stunCount
        local label = pass == 1 and CATEGORY_LABELS["interrupt"] or CATEGORY_LABELS["stun"]
        local catKey = CAT_KEYS[pass]
        local catCollapsed = db.collapsedCategories and db.collapsedCategories[catKey]

        if count > 0 then
            -- Category header
            rowIndex = rowIndex + 1
            local headerRow = getRow(rowIndex, content)
            headerRow.icon:Hide()
            if headerRow.marker then headerRow.marker:Hide() end
            headerRow.name:ClearAllPoints()
            headerRow.name:SetPoint("LEFT", headerRow.icon, "RIGHT", 4, 0)
            headerRow.name:SetText("|cffffcc00" .. label .. "|r")
            headerRow.name:SetWidth(180)
            headerRow.status:SetText("")
            headerRow.counter:SetText("")

            -- Category collapse button
            if not headerRow.collapseBtn then
                local btn = CreateFrame("Button", nil, headerRow)
                btn:SetSize(ROW_HEIGHT, ROW_HEIGHT)
                btn:SetPoint("RIGHT", headerRow, "RIGHT", 0, 0)
                local ico = btn:CreateTexture(nil, "ARTWORK")
                ico:SetSize(12, 12)
                ico:SetPoint("CENTER")
                ico:SetAlpha(0.6)
                btn:SetScript("OnEnter", function() ico:SetAlpha(1) end)
                btn:SetScript("OnLeave", function() ico:SetAlpha(0.6) end)
                btn:SetScript("OnClick", function(self)
                    local key = self._catKey
                    if db.collapsedCategories and key then
                        db.collapsedCategories[key] = not db.collapsedCategories[key]
                    end
                    ns.refreshDisplay()
                end)
                headerRow.collapseBtn = btn
                headerRow.collapseIcon = ico
            end
            headerRow.collapseIcon:SetTexture(catCollapsed
                and "Interface\\Buttons\\UI-PlusButton-UP"
                or "Interface\\Buttons\\UI-MinusButton-UP")
            headerRow.collapseBtn._catKey = catKey
            headerRow.collapseBtn:Show()
            headerRow:ClearAllPoints()
            headerRow:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(visualRow * ROW_HEIGHT))
            headerRow:SetPoint("RIGHT", content, "RIGHT", 0, 0)
            headerRow:Show()
            visualRow = visualRow + 1

            if catCollapsed then
                -- Skip rendering spell rows for this category
                count = 0
            end

            for i = 1, count do
                local entry = entries[i]
                rowIndex = rowIndex + 1
                local row = getRow(rowIndex, content)
                if row.collapseBtn then row.collapseBtn:Hide() end
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(visualRow * ROW_HEIGHT))
                row:SetPoint("RIGHT", content, "RIGHT", 0, 0)

                local spellID = entry.spellID
                row.iconHitFrame._spellID = spellID
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

                -- Show marker icon if player has an assignment (only when not using separate window)
                local markIndex = showInlineMarker and markerAssignments[entry.playerName]
                if markIndex and row.marker then
                    row.marker:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. markIndex)
                    row.marker:Show()
                    row.name:ClearAllPoints()
                    row.name:SetPoint("LEFT", row.marker, "RIGHT", 2, 0)
                    row.name:SetWidth(82)
                elseif row.marker then
                    row.marker:Hide()
                    row.name:ClearAllPoints()
                    row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
                    row.name:SetWidth(100)
                end

                row.name:SetText("|cff" .. getClassColorHex(entry.playerName) .. entry.playerName .. "|r")

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
                visualRow = visualRow + 1
            end
        end
    end

    -- Resize frame
    local totalHeight = (PADDING * 2) + 14 + (visualRow * ROW_HEIGHT)
    trackerFrame:SetHeight(math_max(FRAME_MIN_HEIGHT, totalHeight))
end

--- Apply the saved frame opacity.
function ns.applyFrameOpacity()
    if not trackerFrame then return end
    local opacity = (ns.db and ns.db.frameOpacity or 80) / 100
    trackerFrame:SetAlpha(opacity)
    if ns.applyMarkerWindowOpacity then ns.applyMarkerWindowOpacity() end
    if ns.applyAssignPanelOpacity then ns.applyAssignPanelOpacity() end
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
    if not ns.db then return end
    if not ns.db.showFrame then return end
    if ns.db.autoHide then
        if ns.isInAnyGroup() then
            ns.showDisplay()
        else
            ns.hideDisplay()
        end
    end
end)

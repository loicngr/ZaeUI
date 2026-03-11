-- ZaeUI_Interrupts: Marker assignment panel
-- Allows players to assign raid markers for kick coordination

local _, ns = ...

-- Local references to WoW APIs
local CreateFrame = CreateFrame
local UnitName = UnitName
local GetNumGroupMembers = GetNumGroupMembers
local IsInRaid = IsInRaid
local UnitIsGroupLeader = UnitIsGroupLeader
local strsplit = strsplit
local tonumber = tonumber
local tostring = tostring
local pairs = pairs
local ipairs = ipairs
local table_concat = table.concat

-- Constants
local MARKER_INDICES = { 1, 2, 3, 4, 5 } -- Star, Circle, Diamond, Triangle, Moon
local MARKER_TEXTURES = {}
for _, idx in ipairs(MARKER_INDICES) do
    MARKER_TEXTURES[idx] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. idx
end
local MARKER_ICON_SIZE = 20
local MARKER_HIGHLIGHT_COLOR = { 1, 0.84, 0, 0.6 } -- gold
local MARKER_DISABLED_ALPHA = 0.3
local PANEL_WIDTH = 260
local ROW_HEIGHT = 28
local PADDING = 10

-- State (persisted via db.markerAssignments, initialized in ADDON_LOADED)
ns.markerAssignments = {} -- { ["PlayerName"] = markIndex }
local pendingAssignments = {} -- local edits before sending
local assignFrame -- the panel frame

--- Build ordered list of current group member names.
--- @return table names List of player names (strings)
local function getGroupRoster()
    local roster = {}
    local numMembers = GetNumGroupMembers()
    if numMembers == 0 then
        local myName = UnitName("player")
        if myName then roster[1] = myName end
        return roster
    end
    local isRaid = IsInRaid()
    local count = isRaid and numMembers or (numMembers - 1)
    for i = 1, count do
        local unit = isRaid and ("raid" .. i) or ("party" .. i)
        local name = UnitName(unit)
        if name then roster[#roster + 1] = name end
    end
    -- party units don't include the player
    if not IsInRaid() then
        local myName = UnitName("player")
        if myName then roster[#roster + 1] = myName end
    end
    return roster
end


--- Remove marker assignments for players no longer in the group.
function ns.cleanStaleAssignments()
    local roster = getGroupRoster()
    local rosterSet = {}
    for _, name in ipairs(roster) do rosterSet[name] = true end
    for name in pairs(ns.markerAssignments) do
        if not rosterSet[name] then
            ns.markerAssignments[name] = nil
        end
    end
end

--- Check if a marker index is already assigned to another player in pending.
--- @param markIndex number The marker index to check
--- @param excludeName string The player to exclude from the check
--- @return boolean taken Whether the marker is taken
local function isMarkerTaken(markIndex, excludeName)
    for name, idx in pairs(pendingAssignments) do
        if idx == markIndex and name ~= excludeName then
            return true
        end
    end
    return false
end

-- Panel UI state
local playerRows = {} -- { [playerName] = { row, markerButtons = {} } }

--- Create the assignment panel frame.
local function createAssignFrame()
    assignFrame = CreateFrame("Frame", "ZaeUI_InterruptsAssignFrame", UIParent, "BackdropTemplate")
    assignFrame:SetSize(PANEL_WIDTH, 100) -- height adjusted dynamically
    -- Restore saved position or default to center
    if ns.db and ns.db.assignPanelPoint then
        local p = ns.db.assignPanelPoint
        assignFrame:SetPoint(p[1], UIParent, p[3], p[4], p[5])
    else
        assignFrame:SetPoint("CENTER")
    end
    ns.applyBackdrop(assignFrame)
    assignFrame:SetFrameStrata("DIALOG")
    assignFrame:SetClampedToScreen(true)
    assignFrame:SetMovable(true)
    assignFrame:EnableMouse(true)
    assignFrame:RegisterForDrag("LeftButton")
    assignFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    assignFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        if ns.db then
            ns.db.assignPanelPoint = { point, nil, relPoint, x, y }
        end
    end)

    -- Title
    local title = assignFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", PADDING, -PADDING)
    title:SetText("|cff00ccffKick Assignments|r")
    assignFrame.title = title

    -- Close button
    local closeBtn = CreateFrame("Button", nil, assignFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetSize(20, 20)
    closeBtn:SetScript("OnClick", function() assignFrame:Hide() end)

    -- Content area (player rows go here)
    assignFrame.content = CreateFrame("Frame", nil, assignFrame)
    assignFrame.content:SetPoint("TOPLEFT", PADDING, -(PADDING + 16))
    assignFrame.content:SetPoint("RIGHT", assignFrame, "RIGHT", -PADDING, 0)

    -- Footer buttons
    local sendBtn = CreateFrame("Button", nil, assignFrame, "UIPanelButtonTemplate")
    sendBtn:SetSize(60, 22)
    sendBtn:SetText("Send")
    sendBtn:SetScript("OnClick", function() ns.sendMarkerAssignments() end)
    assignFrame.sendBtn = sendBtn

    local clearBtn = CreateFrame("Button", nil, assignFrame, "UIPanelButtonTemplate")
    clearBtn:SetSize(60, 22)
    clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function()
        for k in pairs(pendingAssignments) do pendingAssignments[k] = nil end
        ns.refreshAssignPanel()
    end)
    assignFrame.clearBtn = clearBtn

    assignFrame:Hide()
    return assignFrame
end

--- Refresh the assignment panel with current group roster and pending assignments.
function ns.refreshAssignPanel()
    if not assignFrame or not assignFrame:IsShown() then return end

    local content = assignFrame.content
    local roster = getGroupRoster()
    local yOffset = 0

    -- Clean stale pending assignments for players no longer in the group
    local rosterSet = {}
    for _, name in ipairs(roster) do rosterSet[name] = true end
    for name in pairs(pendingAssignments) do
        if not rosterSet[name] then pendingAssignments[name] = nil end
    end

    -- Hide all existing rows
    for _, rowData in pairs(playerRows) do
        rowData.row:Hide()
    end

    for _, playerName in ipairs(roster) do
        -- Get or create row
        local rowData = playerRows[playerName]
        if not rowData then
            local row = CreateFrame("Frame", nil, content)
            row:SetHeight(ROW_HEIGHT)

            local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            nameText:SetPoint("LEFT", 0, 0)
            nameText:SetWidth(90)
            nameText:SetJustifyH("LEFT")

            local markerButtons = {}
            for btnIdx, markIndex in ipairs(MARKER_INDICES) do
                local btn = CreateFrame("Button", nil, row)
                btn:SetSize(MARKER_ICON_SIZE, MARKER_ICON_SIZE)
                btn:SetPoint("LEFT", 94 + (btnIdx - 1) * (MARKER_ICON_SIZE + 4), 0)

                local tex = btn:CreateTexture(nil, "ARTWORK")
                tex:SetAllPoints()
                tex:SetTexture(MARKER_TEXTURES[markIndex])
                btn.tex = tex

                local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
                highlight:SetAllPoints()
                highlight:SetColorTexture(MARKER_HIGHLIGHT_COLOR[1], MARKER_HIGHLIGHT_COLOR[2], MARKER_HIGHLIGHT_COLOR[3], MARKER_HIGHLIGHT_COLOR[4])
                btn.highlight = highlight

                local selected = btn:CreateTexture(nil, "OVERLAY")
                selected:SetPoint("TOPLEFT", -2, 2)
                selected:SetPoint("BOTTOMRIGHT", 2, -2)
                selected:SetColorTexture(MARKER_HIGHLIGHT_COLOR[1], MARKER_HIGHLIGHT_COLOR[2], MARKER_HIGHLIGHT_COLOR[3], 0.4)
                selected:Hide()
                btn.selected = selected

                btn.markIndex = markIndex
                btn.playerName = playerName
                btn:SetScript("OnClick", function(self)
                    local currentMark = pendingAssignments[self.playerName]
                    if currentMark == self.markIndex then
                        -- Deselect
                        pendingAssignments[self.playerName] = nil
                    elseif not isMarkerTaken(self.markIndex, self.playerName) then
                        -- Assign
                        pendingAssignments[self.playerName] = self.markIndex
                    end
                    ns.refreshAssignPanel()
                end)

                markerButtons[markIndex] = btn
            end

            rowData = { row = row, nameText = nameText, markerButtons = markerButtons }
            playerRows[playerName] = rowData
        end

        -- Position and configure row
        local row = rowData.row
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yOffset)
        row:SetPoint("RIGHT", content, "RIGHT", 0, 0)

        -- Set player name with class color
        local hex = ns.getClassColorHex and ns.getClassColorHex(playerName) or "ffffff"
        rowData.nameText:SetText("|cff" .. hex .. playerName .. "|r")

        -- Update marker button states
        local currentMark = pendingAssignments[playerName]
        for _, markIndex in ipairs(MARKER_INDICES) do
            local btn = rowData.markerButtons[markIndex]
            local taken = isMarkerTaken(markIndex, playerName)
            if currentMark == markIndex then
                -- Selected
                btn.selected:Show()
                btn.tex:SetAlpha(1)
                btn:Enable()
            elseif taken then
                -- Taken by another player
                btn.selected:Hide()
                btn.tex:SetAlpha(MARKER_DISABLED_ALPHA)
                btn:Disable()
            else
                -- Available
                btn.selected:Hide()
                btn.tex:SetAlpha(1)
                btn:Enable()
            end
        end

        row:Show()
        yOffset = yOffset - ROW_HEIGHT
    end

    -- Resize panel and position footer buttons
    local numPlayers = #roster
    local contentHeight = numPlayers * ROW_HEIGHT
    local totalHeight = PADDING + 16 + contentHeight + 10 + 22 + PADDING
    assignFrame:SetHeight(totalHeight)

    assignFrame.sendBtn:ClearAllPoints()
    assignFrame.sendBtn:SetPoint("BOTTOMRIGHT", assignFrame, "BOTTOMRIGHT", -(PADDING + 66), PADDING)
    assignFrame.clearBtn:ClearAllPoints()
    assignFrame.clearBtn:SetPoint("BOTTOMRIGHT", assignFrame, "BOTTOMRIGHT", -PADDING, PADDING)
end

--- Send marker assignments to the group via addon messaging.
--- @param silent boolean If true, broadcast current assignments without copying from pending or closing panel.
function ns.sendMarkerAssignments(silent)
    if not silent then
        -- Apply from pending to live
        for k in pairs(ns.markerAssignments) do ns.markerAssignments[k] = nil end
        for name, idx in pairs(pendingAssignments) do
            ns.markerAssignments[name] = idx
        end
    end
    if ns.refreshDisplay then ns.refreshDisplay() end
    if ns.refreshMarkerDisplay then ns.refreshMarkerDisplay() end

    -- Build and send message
    local parts = {}
    local n = 0
    for name, idx in pairs(ns.markerAssignments) do
        n = n + 1
        parts[n] = name .. "=" .. tostring(idx)
    end
    if n == 0 then
        ns.safeSend("MARKS:_")
    else
        ns.safeSend("MARKS:" .. table_concat(parts, ","))
    end

    if not silent and assignFrame then assignFrame:Hide() end
end

--- Handle incoming MARKS message payload.
--- @param payload string The payload after "MARKS:"
function ns.handleMarksMessage(payload)
    for k in pairs(ns.markerAssignments) do ns.markerAssignments[k] = nil end
    if payload and payload ~= "" and payload ~= "_" then
        for entry in payload:gmatch("[^,]+") do
            local name, idxStr = entry:match("^(.+)=(%d+)$")
            if name and idxStr then
                local idx = tonumber(idxStr)
                if idx and idx >= 1 and idx <= 5 then
                    -- Strip realm from name
                    local cleanName = strsplit("-", name)
                    ns.markerAssignments[cleanName] = idx
                end
            end
        end
    end
    -- Refresh marker display (tracker refresh is handled by handleAddonMessage caller)
    if ns.refreshMarkerDisplay then ns.refreshMarkerDisplay() end
    -- Sync pending if panel is open
    if assignFrame and assignFrame:IsShown() then
        for k in pairs(pendingAssignments) do pendingAssignments[k] = nil end
        for name, idx in pairs(ns.markerAssignments) do
            pendingAssignments[name] = idx
        end
        ns.refreshAssignPanel()
    end
end

--- Toggle the assignment panel visibility (leader only).
function ns.toggleAssignPanel()
    -- Only the group leader (or solo player) can open the panel
    if ns.isInAnyGroup() and not UnitIsGroupLeader("player") then
        print(ns.PREFIX .. "Only the group leader can assign kick markers.")
        return
    end
    if not assignFrame then createAssignFrame() end
    if assignFrame:IsShown() then
        assignFrame:Hide()
    else
        -- Copy current live assignments into pending
        for k in pairs(pendingAssignments) do pendingAssignments[k] = nil end
        for name, idx in pairs(ns.markerAssignments) do
            pendingAssignments[name] = idx
        end
        -- Restore saved position
        if ns.db and ns.db.assignPanelPoint then
            local p = ns.db.assignPanelPoint
            assignFrame:ClearAllPoints()
            assignFrame:SetPoint(p[1], UIParent, p[3], p[4], p[5])
        end
        assignFrame:Show()
        ns.refreshAssignPanel()
    end
end

--- Apply frame opacity to assignment panel.
function ns.applyAssignPanelOpacity()
    if not assignFrame then return end
    local opacity = (ns.db and ns.db.frameOpacity or 80) / 100
    assignFrame:SetAlpha(opacity)
end


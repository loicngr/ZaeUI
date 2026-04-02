-- ModernDefensivesDisplay.lua — Modern Gaming display for ZaeUI_Defensives
local _, ns = ...

local CreateFrame = CreateFrame
local GetTime = GetTime
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitName = UnitName
local IsInRaid = IsInRaid
local GetNumGroupMembers = GetNumGroupMembers
local pairs = pairs
local sort = table.sort
local floor = math.floor
local max = math.max
local C_Spell = C_Spell
local GameTooltip = GameTooltip

-- Layout
local FRAME_WIDTH_DEFAULT = 250
local FRAME_MIN_WIDTH = 180
local FRAME_MAX_WIDTH = 500
local FRAME_MIN_HEIGHT = 70
local FRAME_MAX_HEIGHT = 600
local HEADER_HEIGHT = 26
local BAR_HEIGHT = 24
local ICON_SIZE = 18
local PADDING = 7
local BAR_GAP = 2
local HEADER_GAP = 4
local UPDATE_INTERVAL = 0.1
local FONT_PATH = "Interface\\AddOns\\ZaeUI_Shared\\Fonts\\Roboto.ttf"

-- Colors (r, g, b)
local COLOR_BRAND = { 239/255, 97/255, 34/255 }       -- #ef6122
local COLOR_BG = { 10/255, 14/255, 23/255 }            -- #0a0e17
local COLOR_HEADER_BG = { 13/255, 17/255, 23/255 }     -- #0d1117
local COLOR_READY = { 0, 229/255, 1 }                  -- #00e5ff
local COLOR_CD_LOW = { 1, 61/255, 113/255 }             -- #ff3d71
local COLOR_CD_MID = { 1, 170/255, 0 }                  -- #ffaa00
local COLOR_BAR_BG = { 13/255, 17/255, 23/255 }        -- #0d1117

-- Role sort order
local ROLE_ORDER = { TANK = 1, HEALER = 2, DAMAGER = 3, NONE = 4 }
local CAT_ORDER = { external = 1, raidwide = 2, personal = 3 }

-- State
local modernFrame
local scrollFrame, scrollChild
local headerFrame
local updateFrame
local barPool = {}
local activeBarCount = 0
local sortedEntries = {}
local spellIconCache = {}
local roleCache = {}
local elapsed_acc = 0
local isResizing = false
local wasCollapsed = false

-- Pre-computed hex strings and gradient colors (avoids allocations in hot path)
local HEX_READY = "00e5ff"
local HEX_CD_MID = "ffaa00"
local HEX_CD_LOW = "ff3d71"

local GRAD_READY_START = CreateColor(COLOR_READY[1], COLOR_READY[2], COLOR_READY[3], 0.18)
local GRAD_READY_END   = CreateColor(COLOR_READY[1], COLOR_READY[2], COLOR_READY[3], 0)
local GRAD_MID_START   = CreateColor(COLOR_CD_MID[1], COLOR_CD_MID[2], COLOR_CD_MID[3], 0.18)
local GRAD_MID_END     = CreateColor(COLOR_CD_MID[1], COLOR_CD_MID[2], COLOR_CD_MID[3], 0)
local GRAD_LOW_START   = CreateColor(COLOR_CD_LOW[1], COLOR_CD_LOW[2], COLOR_CD_LOW[3], 0.18)
local GRAD_LOW_END     = CreateColor(COLOR_CD_LOW[1], COLOR_CD_LOW[2], COLOR_CD_LOW[3], 0)

local function getProgressColor(progress)
    if progress >= 0.9 then
        return COLOR_READY[1], COLOR_READY[2], COLOR_READY[3], HEX_READY, GRAD_READY_START, GRAD_READY_END
    elseif progress >= 0.5 then
        return COLOR_CD_MID[1], COLOR_CD_MID[2], COLOR_CD_MID[3], HEX_CD_MID, GRAD_MID_START, GRAD_MID_END
    else
        return COLOR_CD_LOW[1], COLOR_CD_LOW[2], COLOR_CD_LOW[3], HEX_CD_LOW, GRAD_LOW_START, GRAD_LOW_END
    end
end

local function isCategoryEnabled(category)
    local db = ns.db
    if category == "external" then return db.trackerShowExternal end
    if category == "personal" then return db.trackerShowPersonal end
    if category == "raidwide" then return db.trackerShowRaidwide end
    return false
end

--- Build a role lookup table for all current group members.
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

local function entryComparator(a, b)
    local ra = ROLE_ORDER[a.role] or 4
    local rb = ROLE_ORDER[b.role] or 4
    if ra ~= rb then return ra < rb end
    if a.playerName ~= b.playerName then return a.playerName < b.playerName end
    local ca = CAT_ORDER[a.category] or 99
    local cb = CAT_ORDER[b.category] or 99
    return ca < cb
end

local function collectAndSortEntries()
    local n = 0
    local now = GetTime()
    local spellData = ns.spellData or {}
    local groupData = ns.groupData or {}

    buildRoleCache()

    local myName = UnitName("player")
    for playerName, data in pairs(groupData) do
        if data.spells then
            for spellID in pairs(data.spells) do
                local spellInfo = spellData[spellID]
                if spellInfo and isCategoryEnabled(spellInfo.category)
                   and not (spellInfo.category == "external" and ns.db.trackerHideOwnExternals and playerName == myName) then
                    local cdEnd = data.cooldowns and data.cooldowns[spellID] or 0
                    local remaining = (cdEnd > now) and (cdEnd - now) or 0
                    local isReady = remaining == 0

                    n = n + 1
                    local entry = sortedEntries[n]
                    if not entry then
                        entry = {}
                        sortedEntries[n] = entry
                    end
                    entry.playerName = playerName
                    entry.spellID = spellID
                    entry.spellName = spellInfo.name
                    entry.cooldown = spellInfo.cooldown
                    entry.remaining = remaining
                    entry.isReady = isReady
                    entry.category = spellInfo.category
                    entry.role = roleCache[playerName] or "NONE"
                    entry.chargeData = data.charges and data.charges[spellID] or nil
                end
            end
        end
    end

    for i = n + 1, #sortedEntries do
        sortedEntries[i] = nil
    end

    sort(sortedEntries, entryComparator)
    return n
end

-- Bar row factory
local function getBar(index)
    local bar = barPool[index]
    if bar then return bar end

    bar = CreateFrame("StatusBar", nil, scrollChild)
    bar:SetHeight(BAR_HEIGHT)
    bar:SetStatusBarTexture("Interface\\BUTTONS\\WHITE8X8")
    bar:SetMinMaxValues(0, 1)

    -- Dark background
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(COLOR_BAR_BG[1], COLOR_BAR_BG[2], COLOR_BAR_BG[3], 0.9)

    -- Thin border (very subtle)
    bar.border = CreateFrame("Frame", nil, bar, "BackdropTemplate")
    bar.border:SetAllPoints()
    bar.border:SetBackdrop({
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 1,
    })

    -- Gradient overlay on top of the status bar fill (brighter left, fades right)
    bar.gradient = bar:CreateTexture(nil, "ARTWORK", nil, 0)
    bar.gradient:SetAllPoints()
    bar.gradient:SetTexture("Interface\\BUTTONS\\WHITE8X8")

    bar.iconBg = bar:CreateTexture(nil, "ARTWORK", nil, 1)
    bar.iconBg:SetSize(ICON_SIZE, ICON_SIZE)
    bar.iconBg:SetPoint("LEFT", PADDING, 0)
    bar.iconBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)

    bar.icon = bar:CreateTexture(nil, "ARTWORK", nil, 2)
    bar.icon:SetSize(ICON_SIZE, ICON_SIZE)
    bar.icon:SetPoint("LEFT", PADDING, 0)

    -- Tooltip hit frame over the icon
    bar.iconHit = CreateFrame("Frame", nil, bar)
    bar.iconHit:SetAllPoints(bar.icon)
    bar.iconHit:EnableMouse(true)
    bar.iconHit:SetScript("OnEnter", function(self)
        local id = self._spellID
        if not id then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(id)
        GameTooltip:Show()
    end)
    bar.iconHit:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    bar.nameText = bar:CreateFontString(nil, "OVERLAY")
    bar.nameText:SetFont(FONT_PATH, 10, "")
    bar.nameText:SetShadowOffset(1, -1)
    bar.nameText:SetPoint("LEFT", bar.icon, "RIGHT", 4, 0)
    bar.nameText:SetJustifyH("LEFT")

    bar.statusText = bar:CreateFontString(nil, "OVERLAY")
    bar.statusText:SetFont(FONT_PATH, 9, "")
    bar.statusText:SetShadowOffset(1, -1)
    bar.statusText:SetPoint("RIGHT", -PADDING, 0)
    bar.statusText:SetJustifyH("RIGHT")

    bar.chargeText = bar:CreateFontString(nil, "OVERLAY")
    bar.chargeText:SetFont(FONT_PATH, 8, "")
    bar.chargeText:SetShadowOffset(1, -1)
    bar.chargeText:SetPoint("RIGHT", bar.statusText, "LEFT", -4, 0)
    bar.chargeText:SetJustifyH("RIGHT")
    bar.chargeText:SetTextColor(1, 1, 1, 0.3)

    barPool[index] = bar
    return bar
end

-- Main frame creation
local function createModernFrame()
    local db = ns.db
    local width = db.frameWidth or FRAME_WIDTH_DEFAULT
    local height = (db.frameHeight and db.frameHeight > 0) and db.frameHeight or FRAME_MIN_HEIGHT

    modernFrame = CreateFrame("Frame", "ZaeUI_DefensivesModernFrame", UIParent)
    modernFrame:SetSize(width, height)
    modernFrame:SetPoint("CENTER")
    modernFrame:SetClampedToScreen(true)
    modernFrame:SetMovable(true)
    modernFrame:SetResizable(true)
    modernFrame:SetResizeBounds(FRAME_MIN_WIDTH, FRAME_MIN_HEIGHT, FRAME_MAX_WIDTH, FRAME_MAX_HEIGHT)
    modernFrame:SetFrameStrata("MEDIUM")

    local bg = modernFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(COLOR_BG[1], COLOR_BG[2], COLOR_BG[3], db.trackerOpacity / 100)
    modernFrame.bg = bg

    headerFrame = CreateFrame("Frame", nil, modernFrame)
    headerFrame:SetHeight(HEADER_HEIGHT)
    headerFrame:SetPoint("TOPLEFT")
    headerFrame:SetPoint("TOPRIGHT")

    local headerBg = headerFrame:CreateTexture(nil, "BACKGROUND")
    headerBg:SetAllPoints()
    headerBg:SetColorTexture(COLOR_HEADER_BG[1], COLOR_HEADER_BG[2], COLOR_HEADER_BG[3], 0.95)

    local accent = headerFrame:CreateTexture(nil, "ARTWORK")
    accent:SetHeight(2)
    accent:SetPoint("BOTTOMLEFT")
    accent:SetPoint("BOTTOMRIGHT")
    accent:SetColorTexture(COLOR_BRAND[1], COLOR_BRAND[2], COLOR_BRAND[3], 1)

    local title = headerFrame:CreateFontString(nil, "OVERLAY")
    title:SetFont(FONT_PATH, 11, "")
    title:SetShadowOffset(1, -1)
    title:SetPoint("LEFT", 12, 0)
    title:SetText("|cffef6122DEFENSIVES|r")
    title:SetJustifyH("LEFT")

    -- Badge pill (ready count / total)
    local badgeFrame = CreateFrame("Frame", nil, headerFrame)
    badgeFrame:SetHeight(14)
    badgeFrame:SetPoint("LEFT", title, "RIGHT", 8, 0)

    local badgeBg = badgeFrame:CreateTexture(nil, "BACKGROUND")
    badgeBg:SetAllPoints()
    badgeBg:SetColorTexture(COLOR_BRAND[1], COLOR_BRAND[2], COLOR_BRAND[3], 0.12)

    local badge = badgeFrame:CreateFontString(nil, "OVERLAY")
    badge:SetFont(FONT_PATH, 8, "")
    badge:SetShadowOffset(1, -1)
    badge:SetPoint("CENTER", 0, 0)
    modernFrame.badge = badge
    modernFrame.badgeFrame = badgeFrame

    local btnSize = 14
    local btnGap = 4

    -- Helper: make a button propagate drag to the header for window moving
    local function setupButtonDrag(btn)
        btn:RegisterForDrag("LeftButton")
        btn:SetScript("OnDragStart", function()
            if not db.trackerLocked then modernFrame:StartMoving() end
        end)
        btn:SetScript("OnDragStop", function()
            modernFrame:StopMovingOrSizing()
            local point, _, relPoint, x, y = modernFrame:GetPoint()
            db.framePoint = { point, nil, relPoint, x, y }
        end)
    end

    -- Helper: create a header button with subtle background square
    local function createHeaderButton(parent, anchor, offsetX, texture, texSize, onClick)
        local btn = CreateFrame("Button", nil, parent)
        btn:SetSize(btnSize, btnSize)
        if type(anchor) == "table" then
            btn:SetPoint("RIGHT", anchor, "LEFT", offsetX, 0)
        else
            btn:SetPoint("RIGHT", offsetX, 0)
        end

        -- Subtle background square
        btn.bg = btn:CreateTexture(nil, "BACKGROUND")
        btn.bg:SetAllPoints()
        btn.bg:SetColorTexture(1, 1, 1, 0.06)

        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetSize(texSize, texSize)
        btn.icon:SetPoint("CENTER")
        btn.icon:SetTexture(texture)
        btn.icon:SetVertexColor(0.53, 0.53, 0.53)

        btn:SetScript("OnClick", onClick)
        btn:SetScript("OnEnter", function()
            btn.icon:SetVertexColor(1, 1, 1)
            btn.bg:SetColorTexture(1, 1, 1, 0.1)
        end)
        btn:SetScript("OnLeave", function()
            btn.icon:SetVertexColor(0.53, 0.53, 0.53)
            btn.bg:SetColorTexture(1, 1, 1, 0.06)
        end)
        setupButtonDrag(btn)
        return btn
    end

    -- Collapse button
    local collapseBtn = createHeaderButton(headerFrame, nil, -8,
        "Interface\\AddOns\\ZaeUI_Shared\\Textures\\icon-arrow-down", 12,
        function()
            ns.db.collapsed = not ns.db.collapsed
            ns.refreshModernTrackerDisplay()
        end)
    modernFrame.collapseBtn = collapseBtn

    -- Settings button
    createHeaderButton(headerFrame, collapseBtn, -btnGap,
        "Interface\\AddOns\\ZaeUI_Shared\\Textures\\icon-gear", 10,
        function()
            if ns.settingsCategory then
                Settings.OpenToCategory(ns.settingsCategory.ID)
            end
        end)

    -- Header drag
    headerFrame:EnableMouse(true)
    headerFrame:RegisterForDrag("LeftButton")
    headerFrame:SetScript("OnDragStart", function()
        if not db.trackerLocked then modernFrame:StartMoving() end
    end)
    headerFrame:SetScript("OnDragStop", function()
        modernFrame:StopMovingOrSizing()
        local point, _, relPoint, x, y = modernFrame:GetPoint()
        db.framePoint = { point, nil, relPoint, x, y }
    end)

    scrollFrame = CreateFrame("ScrollFrame", nil, modernFrame)
    scrollFrame:SetPoint("TOPLEFT", headerFrame, "BOTTOMLEFT", 0, -HEADER_GAP)
    scrollFrame:SetPoint("BOTTOMRIGHT", 0, 14)

    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(width)
    scrollFrame:SetScrollChild(scrollChild)

    -- Mouse wheel scrolling
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local maxScroll = max(scrollChild:GetHeight() - self:GetHeight(), 0)
        local newScroll = current - (delta * BAR_HEIGHT * 2)
        if newScroll < 0 then newScroll = 0 end
        if newScroll > maxScroll then newScroll = maxScroll end
        self:SetVerticalScroll(newScroll)
    end)

    local resizeBtn = CreateFrame("Button", nil, modernFrame)
    resizeBtn:SetSize(14, 14)
    resizeBtn:SetPoint("BOTTOMRIGHT", -2, 2)
    resizeBtn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeBtn:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeBtn:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeBtn:SetScript("OnMouseDown", function()
        if not db.trackerLocked then
            isResizing = true
            modernFrame:StartSizing("BOTTOMRIGHT")
        end
    end)
    resizeBtn:SetScript("OnMouseUp", function()
        isResizing = false
        modernFrame:StopMovingOrSizing()
        db.frameWidth = floor(modernFrame:GetWidth() + 0.5)
        local h = floor(modernFrame:GetHeight() + 0.5)
        db.frameHeight = h
        scrollChild:SetWidth(db.frameWidth)
        ns.refreshModernTrackerDisplay()
    end)

    local p = db.framePoint
    if p and p[1] then
        modernFrame:ClearAllPoints()
        modernFrame:SetPoint(p[1], UIParent, p[3], p[4], p[5])
    end
end

local function refreshBars(entryCount)
    local db = ns.db
    local frameWidth = modernFrame:GetWidth()
    local readyCount = 0

    for i = 1, entryCount do
        local entry = sortedEntries[i]
        local bar = getBar(i)

        bar:SetWidth(frameWidth - PADDING * 2)
        bar:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", PADDING, -(BAR_GAP + (i - 1) * (BAR_HEIGHT + BAR_GAP)))

        local progress
        if entry.isReady then
            progress = 1
            readyCount = readyCount + 1
        else
            local cd = entry.cooldown
            if cd and cd > 0 then
                progress = (cd - entry.remaining) / cd
                if progress < 0 then progress = 0 end
                if progress > 1 then progress = 1 end
            else
                progress = 0
            end
        end

        bar:SetValue(progress)

        local r, g, b, progressHex, gradStart, gradEnd = getProgressColor(progress)
        bar:SetStatusBarColor(r, g, b, 0.08)
        bar.gradient:SetGradient("HORIZONTAL", gradStart, gradEnd)
        -- Border: barely visible
        bar.border:SetBackdropBorderColor(r, g, b, entry.isReady and 0.2 or 0.08)

        local iconID = spellIconCache[entry.spellID]
        if not iconID then
            local info = C_Spell.GetSpellInfo(entry.spellID)
            iconID = info and info.iconID or 134400
            spellIconCache[entry.spellID] = iconID
        end
        bar.icon:SetTexture(iconID)
        bar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        bar.iconHit._spellID = entry.spellID

        local classColor = ns.getClassColor(entry.playerName)
        if classColor then
            bar.iconBg:SetColorTexture(classColor.r * 0.3, classColor.g * 0.3, classColor.b * 0.3, 0.8)
        end

        local nameHex = ns.getClassColorHex(entry.playerName) or "ffffff"
        bar.nameText:SetText("|cff" .. nameHex .. entry.playerName .. "|r")

        -- Status text with charge info
        local chargeData = entry.chargeData
        local chargeStr = ""
        if chargeData and chargeData.max and chargeData.max > 1 then
            chargeStr = " |cffffcc00" .. chargeData.current .. "/" .. chargeData.max .. "|r"
        end

        if entry.isReady then
            bar.statusText:SetText("|cff00e5ffREADY|r" .. chargeStr)
            bar.statusText:SetShadowColor(0, 229/255, 1, 0.5)
            bar.statusText:SetShadowOffset(0, 0)
        else
            bar.statusText:SetShadowColor(0, 0, 0, 1)
            bar.statusText:SetShadowOffset(1, -1)
            local remaining = entry.remaining
            local text
            if remaining >= 10 then
                text = floor(remaining) .. "s"
            else
                local whole = floor(remaining)
                local frac = floor((remaining - whole) * 10)
                text = whole .. "." .. frac .. "s"
            end
            bar.statusText:SetText("|cff" .. progressHex .. text .. "|r" .. chargeStr)
        end

        -- No counter in Defensives; hide charge text element (charges shown in statusText)
        bar.chargeText:Hide()

        bar:Show()
    end

    for i = entryCount + 1, activeBarCount do
        local bar = barPool[i]
        if bar then bar:Hide() end
    end
    activeBarCount = entryCount

    local contentHeight = entryCount * (BAR_HEIGHT + BAR_GAP) + BAR_GAP
    scrollChild:SetHeight(max(contentHeight, 1))

    modernFrame.badge:SetText("|cffef6122" .. readyCount .. "/" .. entryCount .. "|r")
    modernFrame.badgeFrame:SetWidth(modernFrame.badge:GetStringWidth() + 12)

    if not isResizing then
        local db_h = db.frameHeight
        if not db_h or db_h == 0 then
            local totalHeight = HEADER_HEIGHT + HEADER_GAP + contentHeight + 14
            totalHeight = max(totalHeight, FRAME_MIN_HEIGHT)
            if totalHeight > FRAME_MAX_HEIGHT then totalHeight = FRAME_MAX_HEIGHT end
            modernFrame:SetHeight(totalHeight)
        end
    end
end

-- Public API
function ns.refreshModernTrackerDisplay()
    if not modernFrame then createModernFrame() end
    if not modernFrame:IsShown() then return end

    if ns.db.collapsed then
        wasCollapsed = true
        scrollFrame:Hide()
        modernFrame:SetHeight(HEADER_HEIGHT)
        modernFrame.collapseBtn.icon:SetTexture("Interface\\AddOns\\ZaeUI_Shared\\Textures\\icon-arrow-up")
        local entryCount = collectAndSortEntries()
        local readyCount = 0
        for i = 1, entryCount do
            if sortedEntries[i].isReady then readyCount = readyCount + 1 end
        end
        modernFrame.badge:SetText("|cffef6122" .. readyCount .. "/" .. entryCount .. "|r")
        modernFrame.badgeFrame:SetWidth(modernFrame.badge:GetStringWidth() + 12)
        return
    end

    modernFrame.collapseBtn.icon:SetTexture("Interface\\AddOns\\ZaeUI_Shared\\Textures\\icon-arrow-down")
    scrollFrame:Show()

    -- Restore height when uncollapsing
    if wasCollapsed then
        wasCollapsed = false
        local db_h = ns.db.frameHeight
        if db_h and db_h > 0 then
            modernFrame:SetHeight(db_h)
        end
    end

    local entryCount = collectAndSortEntries()
    refreshBars(entryCount)
end

function ns.showModernTrackerDisplay()
    if not modernFrame then createModernFrame() end
    modernFrame:Show()
    if not updateFrame then
        updateFrame = CreateFrame("Frame")
        updateFrame:SetScript("OnUpdate", function(_, elapsed)
            elapsed_acc = elapsed_acc + elapsed
            if elapsed_acc >= UPDATE_INTERVAL then
                elapsed_acc = 0
                ns.refreshModernTrackerDisplay()
            end
        end)
    end
    elapsed_acc = 0
    updateFrame:Show()
    ns.refreshModernTrackerDisplay()
end

function ns.hideModernTrackerDisplay()
    if modernFrame then modernFrame:Hide() end
    if updateFrame then updateFrame:Hide() end
end

function ns.toggleModernTrackerDisplay()
    if modernFrame and modernFrame:IsShown() then
        ns.hideModernTrackerDisplay()
    else
        ns.showModernTrackerDisplay()
    end
end

function ns.applyModernTrackerOpacity()
    if modernFrame and modernFrame.bg then
        modernFrame.bg:SetColorTexture(COLOR_BG[1], COLOR_BG[2], COLOR_BG[3], ns.db.trackerOpacity / 100)
    end
end

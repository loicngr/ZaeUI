-- ZaeUI_Nameplates: Enhance your target nameplate with scaling, overlap adjustment, arrows and highlight
-- Uses native CVars and nameplate frame manipulation

local _, ns = ...

-- Local references to WoW APIs
local CreateFrame = CreateFrame
local GetCVar = GetCVar
local SetCVar = SetCVar
local C_NamePlate = C_NamePlate
local UnitIsUnit = UnitIsUnit
local strtrim = strtrim

-- Constants
local ADDON_NAME = "ZaeUI_Nameplates"
local DEFAULT_SCALE = 1.6
local MIN_SCALE = 0.5
local MAX_SCALE = 3.0
local DEFAULT_OVERLAP = 1.3
local MIN_OVERLAP = 0.5
local MAX_OVERLAP = 5.0
local DEFAULT_HIGHLIGHT = false
local DEFAULT_ARROWS = true
local PREFIX = "|cff00ccff[ZaeUI_Nameplates]|r "

local DEFAULT_BORDER = 2
local MIN_BORDER = 1
local MAX_BORDER = 10

local DEFAULT_ARROW_SIZE = 12
local MIN_ARROW_SIZE = 4
local MAX_ARROW_SIZE = 24
local DEFAULT_ARROW_OFFSET = 8
local MIN_ARROW_OFFSET = 0
local MAX_ARROW_OFFSET = 20

-- Local state
local originalOverlapV
local db
local highlightFrame
local borderTextures
local arrowTextures

-- Default settings
local DEFAULTS = {
    scale = DEFAULT_SCALE,
    overlapV = DEFAULT_OVERLAP,
    baseOverlapV = nil,
    highlight = DEFAULT_HIGHLIGHT,
    arrows = DEFAULT_ARROWS,
    highlightColor = { r = 1.0, g = 1.0, b = 1.0, a = 0.6 },
    borderSize = DEFAULT_BORDER,
    arrowSize = DEFAULT_ARROW_SIZE,
    arrowOffset = DEFAULT_ARROW_OFFSET,
}

--- Initialize database with defaults for any missing keys.
local function initDB()
    if not ZaeUI_NameplatesDB then
        ZaeUI_NameplatesDB = {}
    end
    for key, value in pairs(DEFAULTS) do
        if ZaeUI_NameplatesDB[key] == nil then
            if type(value) == "table" then
                ZaeUI_NameplatesDB[key] = { r = value.r, g = value.g, b = value.b, a = value.a }
            else
                ZaeUI_NameplatesDB[key] = value
            end
        end
    end
    if not ZaeUI_NameplatesDB.baseOverlapV then
        ZaeUI_NameplatesDB.baseOverlapV = tonumber(GetCVar("nameplateOverlapV")) or 1.1
    end
    db = ZaeUI_NameplatesDB
    ns.db = db
end

--- Apply the overlap value (auto-proportional or manual override).
--- @param scale number The current nameplate scale
local function applyOverlap(scale)
    if db.overlapV then
        SetCVar("nameplateOverlapV", db.overlapV)
    else
        SetCVar("nameplateOverlapV", originalOverlapV * scale)
    end
end

--- Apply scale and recalculate overlap.
--- @param scale number The scale factor to apply
local function applyScale(scale)
    SetCVar("nameplateSelectedScale", scale)
    applyOverlap(scale)
end

-- Highlight

--- Create the border textures (top, bottom, left, right) on the highlight frame
--- and set their anchor points. Anchors are set once and updated via updateBorderSize.
local function createBorderTextures()
    highlightFrame = CreateFrame("Frame")
    borderTextures = {}
    for i = 1, 4 do
        borderTextures[i] = highlightFrame:CreateTexture(nil, "OVERLAY")
    end
    local top, bottom, left, right = borderTextures[1], borderTextures[2], borderTextures[3], borderTextures[4]
    local t = db.borderSize

    top:SetPoint("TOPLEFT", highlightFrame, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", highlightFrame, "TOPRIGHT", 0, 0)
    top:SetHeight(t)

    bottom:SetPoint("BOTTOMLEFT", highlightFrame, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", highlightFrame, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(t)

    -- Inset left/right to avoid corner overlap with top/bottom
    left:SetPoint("TOPLEFT", highlightFrame, "TOPLEFT", 0, -t)
    left:SetPoint("BOTTOMLEFT", highlightFrame, "BOTTOMLEFT", 0, t)
    left:SetWidth(t)

    right:SetPoint("TOPRIGHT", highlightFrame, "TOPRIGHT", 0, -t)
    right:SetPoint("BOTTOMRIGHT", highlightFrame, "BOTTOMRIGHT", 0, t)
    right:SetWidth(t)
end

--- Reposition border textures after a size change.
local function updateBorderSize()
    if not borderTextures then return end
    local t = db.borderSize
    local top, bottom, left, right = borderTextures[1], borderTextures[2], borderTextures[3], borderTextures[4]

    -- Top/bottom only need SetHeight: their anchors span full width and don't depend on t
    top:SetHeight(t)
    bottom:SetHeight(t)

    -- Left/right need ClearAllPoints because their Y insets change with t
    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", highlightFrame, "TOPLEFT", 0, -t)
    left:SetPoint("BOTTOMLEFT", highlightFrame, "BOTTOMLEFT", 0, t)
    left:SetWidth(t)

    right:ClearAllPoints()
    right:SetPoint("TOPRIGHT", highlightFrame, "TOPRIGHT", 0, -t)
    right:SetPoint("BOTTOMRIGHT", highlightFrame, "BOTTOMRIGHT", 0, t)
    right:SetWidth(t)
end

--- Apply border color to all 4 edge textures.
local function applyBorderColor()
    local c = db.highlightColor
    for i = 1, 4 do
        borderTextures[i]:SetColorTexture(c.r, c.g, c.b, c.a)
    end
end

local ARROW_TEXTURE = "Interface\\AddOns\\ZaeUI_Nameplates\\arrow"

--- Create two arrow textures (left ◀ and right ▶) on the highlight frame.
--- Uses a triangle texture file, mirrored horizontally for the left arrow.
local function createArrowTextures()
    arrowTextures = {}
    for i = 1, 2 do
        arrowTextures[i] = highlightFrame:CreateTexture(nil, "OVERLAY")
        arrowTextures[i]:SetTexture(ARROW_TEXTURE)
    end
    -- Left arrow: mirror horizontally (ULx/LLx swapped with URx/LRx)
    arrowTextures[1]:SetTexCoord(1, 0, 1, 1, 0, 0, 0, 1)
end

--- Reposition and resize arrow textures based on current settings.
local function updateArrowPositions()
    if not arrowTextures then return end
    local size = db.arrowSize
    local offset = db.arrowOffset
    local left, right = arrowTextures[1], arrowTextures[2]

    left:ClearAllPoints()
    left:SetSize(size, size)
    left:SetPoint("RIGHT", highlightFrame, "LEFT", -offset, 0)

    right:ClearAllPoints()
    right:SetSize(size, size)
    right:SetPoint("LEFT", highlightFrame, "RIGHT", offset, 0)
end

--- Apply highlight color to arrow textures.
local function applyArrowColor()
    local c = db.highlightColor
    for i = 1, 2 do
        arrowTextures[i]:SetVertexColor(c.r, c.g, c.b, c.a)
    end
end

--- Find the health bar inside a nameplate frame.
--- Blizzard default nameplates use namePlate.UnitFrame.healthBar.
--- @param namePlate table The nameplate root frame
--- @return table|nil anchor The frame to anchor the border to
local function findHealthBar(namePlate)
    local unitFrame = namePlate.UnitFrame
    if unitFrame and unitFrame.healthBar then
        return unitFrame.healthBar
    end
    return namePlate
end

--- Show a colored border and/or arrows around the target nameplate health bar.
--- Uses a dedicated overlay frame to avoid issues with nameplate recycling.
local function showHighlight()
    if not db.highlight and not db.arrows then
        return
    end
    local namePlate = C_NamePlate.GetNamePlateForUnit("target")
    if not namePlate then
        return
    end
    if not highlightFrame then
        createBorderTextures()
    end
    if not arrowTextures then
        createArrowTextures()
    end
    local anchor = findHealthBar(namePlate)
    highlightFrame:SetParent(anchor)
    highlightFrame:SetAllPoints(anchor)
    highlightFrame:SetFrameStrata("HIGH")
    -- Border visibility
    if db.highlight then
        applyBorderColor()
        for i = 1, 4 do borderTextures[i]:Show() end
    else
        for i = 1, 4 do borderTextures[i]:Hide() end
    end
    -- Arrow visibility
    if db.arrows then
        updateArrowPositions()
        applyArrowColor()
        for i = 1, 2 do arrowTextures[i]:Show() end
    else
        for i = 1, 2 do arrowTextures[i]:Hide() end
    end
    highlightFrame:Show()
end

--- Hide the highlight border.
local function hideHighlight()
    if highlightFrame then
        highlightFrame:Hide()
    end
end

-- Main frame and event handling
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")

local events = {}

function events.ADDON_LOADED(_, addonName)
    if addonName ~= ADDON_NAME then
        return
    end
    initDB()

    originalOverlapV = db.baseOverlapV
    applyScale(db.scale)

    frame:UnregisterEvent("ADDON_LOADED")
    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")

    print(PREFIX .. "Loaded. Type /znp help for commands.")
end

function events.PLAYER_TARGET_CHANGED()
    hideHighlight()
    showHighlight()
end

function events.NAME_PLATE_UNIT_ADDED(_, unit)
    if UnitIsUnit(unit, "target") then
        hideHighlight()
        showHighlight()
    end
end

function events.NAME_PLATE_UNIT_REMOVED(_, unit)
    if UnitIsUnit(unit, "target") then
        hideHighlight()
    end
end

frame:SetScript("OnEvent", function(_, event, ...)
    if events[event] then
        events[event](frame, ...)
    end
end)

-- Slash command handler
SLASH_ZAEUINAMEPLATES1 = "/znp"

SlashCmdList["ZAEUINAMEPLATES"] = function(msg)
    msg = strtrim(msg)

    if msg == "" or msg == "options" then
        if ns.settingsCategory then
            Settings.OpenToCategory(ns.settingsCategory.ID)
        else
            print(PREFIX .. "Options panel not yet loaded.")
        end
        return
    end

    if msg == "help" then
        print(PREFIX .. "Usage:")
        print(PREFIX .. "  /znp - Open the options panel")
        print(PREFIX .. "  /znp <number> - Set target nameplate scale (" .. MIN_SCALE .. "-" .. MAX_SCALE .. ")")
        print(PREFIX .. "  /znp reset - Reset all settings to defaults")
        print(PREFIX .. "  /znp overlap <number> - Override overlap (" .. MIN_OVERLAP .. "-" .. MAX_OVERLAP .. ")")
        print(PREFIX .. "  /znp overlap auto - Reset overlap to automatic")
        print(PREFIX .. "  /znp highlight - Toggle highlight on/off")
        print(PREFIX .. "  /znp border <number> - Set border thickness (" .. MIN_BORDER .. "-" .. MAX_BORDER .. ")")
        print(PREFIX .. "  /znp arrows - Toggle arrows on/off")
        print(PREFIX .. "  /znp arrows size <number> - Set arrow size (" .. MIN_ARROW_SIZE .. "-" .. MAX_ARROW_SIZE .. ")")
        print(PREFIX .. "  /znp arrows offset <number> - Set arrow offset (" .. MIN_ARROW_OFFSET .. "-" .. MAX_ARROW_OFFSET .. ")")
        return
    end

    if msg == "reset" then
        db.scale = DEFAULT_SCALE
        db.overlapV = DEFAULT_OVERLAP
        db.highlight = DEFAULT_HIGHLIGHT
        db.arrows = DEFAULT_ARROWS
        db.borderSize = DEFAULT_BORDER
        db.arrowSize = DEFAULT_ARROW_SIZE
        db.arrowOffset = DEFAULT_ARROW_OFFSET
        local dc = DEFAULTS.highlightColor
        db.highlightColor = { r = dc.r, g = dc.g, b = dc.b, a = dc.a }
        applyScale(DEFAULT_SCALE)
        hideHighlight()
        if highlightFrame then
            updateBorderSize()
            if arrowTextures then
                updateArrowPositions()
            end
        end
        showHighlight()
        if ns.refreshWidgets then
            ns.refreshWidgets()
        end
        print(PREFIX .. "All settings reset to defaults.")
        return
    end

    -- Overlap subcommand
    if msg == "overlap auto" then
        db.overlapV = nil
        applyOverlap(db.scale)
        print(PREFIX .. "Overlap set to automatic.")
        return
    end

    local overlapArg = msg:match("^overlap%s+(.+)$")
    if overlapArg then
        local value = tonumber(overlapArg)
        if not value then
            print(PREFIX .. "Usage: /znp overlap <number> | /znp overlap auto")
            return
        end
        if value < MIN_OVERLAP or value > MAX_OVERLAP then
            print(PREFIX .. "Overlap must be between " .. MIN_OVERLAP .. " and " .. MAX_OVERLAP)
            return
        end
        db.overlapV = value
        applyOverlap(db.scale)
        print(PREFIX .. "Overlap manually set to: " .. value)
        return
    end

    -- Border subcommand
    local borderArg = msg:match("^border%s+(.+)$")
    if borderArg then
        local value = tonumber(borderArg)
        if not value then
            print(PREFIX .. "Usage: /znp border <number>")
            return
        end
        value = math.floor(value)
        if value < MIN_BORDER or value > MAX_BORDER then
            print(PREFIX .. "Border thickness must be between " .. MIN_BORDER .. " and " .. MAX_BORDER)
            return
        end
        db.borderSize = value
        if highlightFrame then
            updateBorderSize()
        end
        print(PREFIX .. "Border thickness set to: " .. value)
        return
    end

    -- Arrows subcommands
    if msg == "arrows" then
        db.arrows = not db.arrows
        if db.arrows then
            showHighlight()
            print(PREFIX .. "Arrows enabled.")
        else
            hideHighlight()
            showHighlight()
            print(PREFIX .. "Arrows disabled.")
        end
        return
    end

    local arrowSizeArg = msg:match("^arrows%s+size%s+(.+)$")
    if arrowSizeArg then
        local value = tonumber(arrowSizeArg)
        if not value then
            print(PREFIX .. "Usage: /znp arrows size <number>")
            return
        end
        value = math.floor(value)
        if value < MIN_ARROW_SIZE or value > MAX_ARROW_SIZE then
            print(PREFIX .. "Arrow size must be between " .. MIN_ARROW_SIZE .. " and " .. MAX_ARROW_SIZE)
            return
        end
        db.arrowSize = value
        if arrowTextures then
            updateArrowPositions()
        end
        print(PREFIX .. "Arrow size set to: " .. value)
        return
    end

    local arrowOffsetArg = msg:match("^arrows%s+offset%s+(.+)$")
    if arrowOffsetArg then
        local value = tonumber(arrowOffsetArg)
        if not value then
            print(PREFIX .. "Usage: /znp arrows offset <number>")
            return
        end
        value = math.floor(value)
        if value < MIN_ARROW_OFFSET or value > MAX_ARROW_OFFSET then
            print(PREFIX .. "Arrow offset must be between " .. MIN_ARROW_OFFSET .. " and " .. MAX_ARROW_OFFSET)
            return
        end
        db.arrowOffset = value
        if arrowTextures then
            updateArrowPositions()
        end
        print(PREFIX .. "Arrow offset set to: " .. value)
        return
    end

    -- Highlight subcommand
    if msg == "highlight" then
        db.highlight = not db.highlight
        hideHighlight()
        showHighlight()
        if db.highlight then
            print(PREFIX .. "Highlight enabled.")
        else
            print(PREFIX .. "Highlight disabled.")
        end
        return
    end

    -- Scale command
    local value = tonumber(msg)
    if not value then
        print(PREFIX .. "Usage: /znp <number> | /znp reset | /znp help")
        return
    end

    if value < MIN_SCALE or value > MAX_SCALE then
        print(PREFIX .. "Scale must be between " .. MIN_SCALE .. " and " .. MAX_SCALE)
        return
    end

    db.scale = value
    applyScale(value)
    print(PREFIX .. "Target nameplate scale set to: " .. value)
end

-- Expose to namespace for Options.lua
ns.constants = {
    MIN_SCALE = MIN_SCALE, MAX_SCALE = MAX_SCALE, DEFAULT_SCALE = DEFAULT_SCALE,
    MIN_OVERLAP = MIN_OVERLAP, MAX_OVERLAP = MAX_OVERLAP,
    MIN_BORDER = MIN_BORDER, MAX_BORDER = MAX_BORDER, DEFAULT_BORDER = DEFAULT_BORDER,
    MIN_ARROW_SIZE = MIN_ARROW_SIZE, MAX_ARROW_SIZE = MAX_ARROW_SIZE, DEFAULT_ARROW_SIZE = DEFAULT_ARROW_SIZE,
    MIN_ARROW_OFFSET = MIN_ARROW_OFFSET, MAX_ARROW_OFFSET = MAX_ARROW_OFFSET, DEFAULT_ARROW_OFFSET = DEFAULT_ARROW_OFFSET,
    DEFAULT_HIGHLIGHT = DEFAULT_HIGHLIGHT, DEFAULT_ARROWS = DEFAULT_ARROWS,
    DEFAULTS = DEFAULTS,
}
ns.applyScale = applyScale
ns.applyOverlap = applyOverlap
ns.showHighlight = showHighlight
ns.hideHighlight = hideHighlight
ns.updateBorderSize = updateBorderSize
ns.updateArrowPositions = updateArrowPositions
ns.applyBorderColor = applyBorderColor
ns.applyArrowColor = applyArrowColor

-- ZaeUI_ActionBars: Hide action bars with mouse hover fade in/out
local _, ns = ...

-- Local references to WoW APIs
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local RegisterStateDriver = RegisterStateDriver
local C_Timer = C_Timer
local strtrim = strtrim
local math_abs = math.abs
local pairs = pairs
local ipairs = ipairs

-- Constants
local ADDON_NAME = "ZaeUI_ActionBars"
local PREFIX = "|cff00ccff[ZaeUI_ActionBars]|r "
local HOVER_POLL_INTERVAL = 0.1

local MIN_FADE = 0.1
local MAX_FADE = 1.0
local DEFAULT_FADE_IN = 0.3
local DEFAULT_FADE_OUT = 0.3
local MIN_DELAY = 0.0
local MAX_DELAY = 3.0
local DEFAULT_DELAY = 1.0

-- Bar registry: maps internal barID to Blizzard global frame name
local BAR_REGISTRY = {
    bar1    = "MainMenuBar",
    bar2    = "MultiBarBottomLeft",
    bar3    = "MultiBarBottomRight",
    bar4    = "MultiBarRight",
    bar5    = "MultiBarLeft",
    bar6    = "MultiBar5",
    bar7    = "MultiBar6",
    bar8    = "MultiBar7",
    stance  = "StanceBar",
    pet     = "PetActionBar",
}

-- Display names for UI/help
local BAR_NAMES = {
    bar1    = "Action Bar 1",
    bar2    = "Action Bar 2",
    bar3    = "Action Bar 3",
    bar4    = "Action Bar 4",
    bar5    = "Action Bar 5",
    bar6    = "Action Bar 6",
    bar7    = "Action Bar 7",
    bar8    = "Action Bar 8",
    stance  = "Stance Bar",
    pet     = "Pet Bar",
}

-- Ordered list for consistent iteration
local BAR_ORDER = { "bar1", "bar2", "bar3", "bar4", "bar5", "bar6", "bar7", "bar8", "stance", "pet" }

-- Local state
local db

-- Behavior options: "default" (no effect), "show" (only when active), "hide" (hidden when active)
local BEHAVIOR_DEFAULT = "default"

-- Default settings per bar
local BAR_DEFAULTS = {
    enabled = false,
    fadeIn = DEFAULT_FADE_IN,
    fadeOut = DEFAULT_FADE_OUT,
    delay = DEFAULT_DELAY,
    showInCombat = true,
    flyingBehavior = BEHAVIOR_DEFAULT,
    mountedBehavior = BEHAVIOR_DEFAULT,
}

--- Initialize database with defaults for any missing keys.
local function initDB()
    if not ZaeUI_ActionBarsDB then
        ZaeUI_ActionBarsDB = {}
    end
    if not ZaeUI_ActionBarsDB.bars then
        ZaeUI_ActionBarsDB.bars = {}
    end
    for _, barID in ipairs(BAR_ORDER) do
        if not ZaeUI_ActionBarsDB.bars[barID] then
            ZaeUI_ActionBarsDB.bars[barID] = {}
        end
        local barDB = ZaeUI_ActionBarsDB.bars[barID]
        -- Migrate old showWhileFlying boolean to flyingBehavior
        if barDB.showWhileFlying ~= nil then
            if barDB.showWhileFlying == true then
                barDB.flyingBehavior = "show"
            end
            barDB.showWhileFlying = nil
        end
        for key, value in pairs(BAR_DEFAULTS) do
            if barDB[key] == nil then
                barDB[key] = value
            end
        end
    end
    db = ZaeUI_ActionBarsDB
    ns.db = db
end

-- Fade engine ---------------------------------------------------------------

-- Per-bar state: { frame, timer, fading, fadeElapsed, fadeDuration, fadeFrom, fadeTo, mouseOver, hooked, conditionHidden }
local barStates = {}

-- Active fades tracking (avoids pairs() in OnUpdate)
local activeFadeList = {}
local activeFadeCount = 0

-- Active hover bars (enabled bars that need IsMouseOver polling)
local hoverBarList = {}
local hoverBarCount = 0
local hoverElapsed = 0

-- Combat queue: bars that need re-evaluation after combat ends
local combatQueue = {}
local combatQueueCount = 0

-- Condition states: tracked via detector frames using RegisterStateDriver
local isFlying = false
local isMounted = false

local engineFrame = CreateFrame("Frame")

--- Start a fade on a bar.
--- @param barID string The bar identifier
--- @param targetAlpha number Target alpha (0 or 1)
--- @param duration number Fade duration in seconds
local function startFade(barID, targetAlpha, duration)
    local state = barStates[barID]
    if not state or not state.frame then return end

    local currentAlpha = state.frame:GetAlpha()
    if math_abs(currentAlpha - targetAlpha) < 0.01 then
        state.frame:SetAlpha(targetAlpha)
        if state.fading then
            state.fading = false
            for i = 1, activeFadeCount do
                if activeFadeList[i] == barID then
                    activeFadeList[i] = activeFadeList[activeFadeCount]
                    activeFadeList[activeFadeCount] = nil
                    activeFadeCount = activeFadeCount - 1
                    break
                end
            end
        end
        return
    end

    if not state.fading then
        activeFadeCount = activeFadeCount + 1
        activeFadeList[activeFadeCount] = barID
    end
    state.fading = true
    state.fadeElapsed = 0
    state.fadeDuration = duration
    state.fadeFrom = currentAlpha
    state.fadeTo = targetAlpha
end

-- Hover detection -----------------------------------------------------------

--- Called when mouse enters a bar's area.
--- @param barID string The bar identifier
local function onBarMouseEnter(barID)
    local state = barStates[barID]
    if not state then return end
    if EditModeManagerFrame and EditModeManagerFrame:IsEditModeActive() then return end
    local settings = db.bars[barID]
    state.mouseOver = true
    -- Cancel pending fade out
    if state.timer then
        state.timer:Cancel()
        state.timer = nil
    end
    startFade(barID, 1, settings.fadeIn)
end

--- Called when mouse leaves a bar's area.
--- @param barID string The bar identifier
local function onBarMouseLeave(barID)
    local state = barStates[barID]
    if not state then return end
    state.mouseOver = false
    local settings = db.bars[barID]
    state.timer = C_Timer.NewTimer(settings.delay, function()
        state.timer = nil
        if state.mouseOver then return end
        if settings.showInCombat and InCombatLockdown() then return end
        startFade(barID, 0, settings.fadeOut)
    end)
end

-- Condition-based visibility ------------------------------------------------

-- Forward declaration
local ensureEngineRunning

--- Check if a bar should be hidden based on flying and mounted behaviors.
--- @param barID string The bar identifier
--- @return boolean shouldHide
local function shouldConditionHide(barID)
    local settings = db.bars[barID]
    local fb = settings.flyingBehavior
    local mb = settings.mountedBehavior
    -- "hide" when condition is active, "show" when condition is NOT active
    if fb ~= BEHAVIOR_DEFAULT then
        if (fb == "hide" and isFlying) or (fb == "show" and not isFlying) then
            return true
        end
    end
    if mb ~= BEHAVIOR_DEFAULT then
        if (mb == "hide" and isMounted) or (mb == "show" and not isMounted) then
            return true
        end
    end
    return false
end

--- Apply condition visibility to all managed bars.
--- Called when flying or mounted state changes.
local function onConditionChanged()
    for _, barID in ipairs(BAR_ORDER) do
        local state = barStates[barID]
        if state and state.frame then
            local settings = db.bars[barID]
            if settings.flyingBehavior ~= BEHAVIOR_DEFAULT or settings.mountedBehavior ~= BEHAVIOR_DEFAULT then
                state.mouseOver = state.frame:IsMouseOver()
                if state.timer then
                    state.timer:Cancel()
                    state.timer = nil
                end

                if shouldConditionHide(barID) then
                    state.conditionHidden = true
                    startFade(barID, 0, settings.fadeOut)
                else
                    state.conditionHidden = false
                    if settings.enabled then
                        startFade(barID, 0, settings.fadeOut)
                    else
                        state.frame:SetAlpha(1)
                    end
                end
            end
        end
    end
    ensureEngineRunning()
end

-- Detector frames: hidden frames whose visibility is toggled by macro conditionals.
-- OnShow = condition active, OnHide = condition inactive.
local flyingDetector = CreateFrame("Frame")
flyingDetector:Hide()
flyingDetector:SetScript("OnShow", function()
    isFlying = true
    onConditionChanged()
end)
flyingDetector:SetScript("OnHide", function()
    isFlying = false
    onConditionChanged()
end)

local mountedDetector = CreateFrame("Frame")
mountedDetector:Hide()
mountedDetector:SetScript("OnShow", function()
    isMounted = true
    onConditionChanged()
end)
mountedDetector:SetScript("OnHide", function()
    isMounted = false
    onConditionChanged()
end)

-- Combined OnUpdate: processes fades and polls hover state
local function onEngineUpdate(_, elapsed)
    -- Process active fades
    local i = 1
    while i <= activeFadeCount do
        local barID = activeFadeList[i]
        local state = barStates[barID]
        if state and state.fading then
            state.fadeElapsed = state.fadeElapsed + elapsed
            local progress = state.fadeElapsed / state.fadeDuration
            if progress >= 1 then
                progress = 1
                state.fading = false
                activeFadeList[i] = activeFadeList[activeFadeCount]
                activeFadeList[activeFadeCount] = nil
                activeFadeCount = activeFadeCount - 1
            else
                i = i + 1
            end
            local alpha = state.fadeFrom + (state.fadeTo - state.fadeFrom) * progress
            state.frame:SetAlpha(alpha)
        else
            activeFadeList[i] = activeFadeList[activeFadeCount]
            activeFadeList[activeFadeCount] = nil
            activeFadeCount = activeFadeCount - 1
        end
    end

    -- Poll managed bars at throttled interval
    hoverElapsed = hoverElapsed + elapsed
    if hoverElapsed >= HOVER_POLL_INTERVAL then
        hoverElapsed = 0
        for j = 1, hoverBarCount do
            local barID = hoverBarList[j]
            local state = barStates[barID]
            if state and state.frame then
                if state.conditionHidden then
                    -- Enforce alpha 0 (Blizzard may reset it on some bars)
                    if state.frame:GetAlpha() > 0 then
                        state.frame:SetAlpha(0)
                    end
                elseif db.bars[barID].enabled then
                    -- Hover-fade polling
                    local isOver = state.frame:IsMouseOver()
                    if isOver and not state.mouseOver then
                        onBarMouseEnter(barID)
                    elseif not isOver and state.mouseOver then
                        onBarMouseLeave(barID)
                    end
                end
            end
        end
    end

    -- Stop OnUpdate only when no fades active AND no bars to poll
    if activeFadeCount <= 0 and hoverBarCount <= 0 then
        activeFadeCount = 0
        engineFrame:SetScript("OnUpdate", nil)
    end
end

--- Ensure the engine OnUpdate is running.
ensureEngineRunning = function()
    engineFrame:SetScript("OnUpdate", onEngineUpdate)
end

--- Add a bar to the hover poll list.
--- @param barID string The bar identifier
local function addHoverBar(barID)
    for i = 1, hoverBarCount do
        if hoverBarList[i] == barID then return end
    end
    hoverBarCount = hoverBarCount + 1
    hoverBarList[hoverBarCount] = barID
    ensureEngineRunning()
end

--- Remove a bar from the hover poll list.
--- @param barID string The bar identifier
local function removeHoverBar(barID)
    for i = 1, hoverBarCount do
        if hoverBarList[i] == barID then
            hoverBarList[i] = hoverBarList[hoverBarCount]
            hoverBarList[hoverBarCount] = nil
            hoverBarCount = hoverBarCount - 1
            return
        end
    end
end

-- Bar apply/remove -----------------------------------------------------------

--- Remove fade behavior from a bar (restore alpha and visibility).
--- @param barID string The bar identifier
local function removeBar(barID)
    local state = barStates[barID]
    if not state then return end

    removeHoverBar(barID)

    if state.timer then
        state.timer:Cancel()
        state.timer = nil
    end
    if state.fading then
        state.fading = false
        for i = 1, activeFadeCount do
            if activeFadeList[i] == barID then
                activeFadeList[i] = activeFadeList[activeFadeCount]
                activeFadeList[activeFadeCount] = nil
                activeFadeCount = activeFadeCount - 1
                break
            end
        end
    end
    if state.frame then
        state.frame:SetAlpha(1)
    end
    state.mouseOver = false
    state.conditionHidden = false
end

--- Determine if a bar needs management (hover-fade or flying behavior).
--- @param barID string The bar identifier
--- @return boolean needsManagement
local function barNeedsManagement(barID)
    local settings = db.bars[barID]
    return settings.enabled or settings.flyingBehavior ~= BEHAVIOR_DEFAULT or settings.mountedBehavior ~= BEHAVIOR_DEFAULT
end

--- Apply fade behavior to a bar (register for hover polling, set initial alpha).
--- @param barID string The bar identifier
local function applyBar(barID)
    if InCombatLockdown() then return end
    if EditModeManagerFrame and EditModeManagerFrame:IsEditModeActive() then return end

    local frameName = BAR_REGISTRY[barID]
    local barFrame = _G[frameName]
    -- Fallback: MainMenuBar was renamed to MainActionBar in modern WoW
    if not barFrame and frameName == "MainMenuBar" then
        barFrame = _G["MainActionBar"]
    end
    if not barFrame then return end

    local settings = db.bars[barID]
    if not barNeedsManagement(barID) then
        removeBar(barID)
        return
    end

    local state = barStates[barID]
    if not state then
        state = { frame = barFrame, timer = nil, fading = false, mouseOver = false, hooked = false, conditionHidden = false }
        barStates[barID] = state
    end

    -- Hook OnShow to set correct alpha when Blizzard forces a show
    if not state.hooked then
        barFrame:HookScript("OnShow", function()
            if state.mouseOver then return end
            -- Condition hidden (flying/mounted): force alpha 0
            if state.conditionHidden then
                barFrame:SetAlpha(0)
                return
            end
            local s = db.bars[barID]
            if not s.enabled then return end
            if InCombatLockdown() and s.showInCombat then return end
            barFrame:SetAlpha(0)
        end)
        state.hooked = true
    end

    -- Register for polling (hover-fade and/or flying alpha enforcement)
    addHoverBar(barID)

    -- Set initial visibility based on current state
    if shouldConditionHide(barID) then
        state.conditionHidden = true
        barFrame:SetAlpha(0)
    elseif settings.enabled then
        state.conditionHidden = false
        if settings.showInCombat and InCombatLockdown() then
            barFrame:SetAlpha(1)
        else
            barFrame:SetAlpha(0)
        end
    else
        state.conditionHidden = false
        barFrame:SetAlpha(1)
    end
end

-- Combat handling ------------------------------------------------------------

local function processCombatQueue()
    for i = 1, combatQueueCount do
        applyBar(combatQueue[i])
        combatQueue[i] = nil
    end
    combatQueueCount = 0
end

local function applyAllBars()
    for _, barID in ipairs(BAR_ORDER) do
        if barNeedsManagement(barID) then
            if InCombatLockdown() then
                combatQueueCount = combatQueueCount + 1
                combatQueue[combatQueueCount] = barID
            else
                applyBar(barID)
            end
        end
    end
end

-- Event handling -------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")

local events = {}

function events.ADDON_LOADED(_, addonName)
    if addonName ~= ADDON_NAME then return end
    if not ZaeUI_Shared then
        local msg = "ZaeUI_Shared is required. Install it from CurseForge."
        print(PREFIX .. "Error: " .. msg .. " Addon disabled.")
        C_Timer.After(5, function() UIErrorsFrame:AddMessage("|cffff0000[" .. ADDON_NAME .. "]|r " .. msg, 1, 0.2, 0.2, 1, 5) end)
        return
    end
    initDB()
    frame:UnregisterEvent("ADDON_LOADED")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

function events.PLAYER_LOGIN()
    if _G["ElvUI"] or _G["Bartender4"] then
        print(PREFIX .. "Warning: ElvUI or Bartender detected. Some bars may not work correctly.")
    end
    -- Start condition detectors (macro conditionals on helper frames)
    RegisterStateDriver(flyingDetector, "visibility", "[flying] show; hide")
    isFlying = flyingDetector:IsShown()
    RegisterStateDriver(mountedDetector, "visibility", "[mounted] show; hide")
    isMounted = mountedDetector:IsShown()
    applyAllBars()
    frame:UnregisterEvent("PLAYER_LOGIN")
    print(PREFIX .. "Loaded. Type /zab help for commands.")
end

function events.PLAYER_REGEN_DISABLED()
    for _, barID in ipairs(BAR_ORDER) do
        local settings = db.bars[barID]
        if settings.enabled and settings.showInCombat then
            startFade(barID, 1, settings.fadeIn)
            ensureEngineRunning()
        end
    end
end

function events.PLAYER_REGEN_ENABLED()
    for _, barID in ipairs(BAR_ORDER) do
        local settings = db.bars[barID]
        if settings.enabled and settings.showInCombat then
            local state = barStates[barID]
            if state and not state.mouseOver then
                startFade(barID, 0, settings.fadeOut)
                ensureEngineRunning()
            end
        end
    end
    processCombatQueue()
end

frame:SetScript("OnEvent", function(_, event, ...)
    if events[event] then
        events[event](frame, ...)
    end
end)

-- Slash commands -------------------------------------------------------------

local function resetDefaults()
    for _, barID in ipairs(BAR_ORDER) do
        removeBar(barID)
        for key, value in pairs(BAR_DEFAULTS) do
            db.bars[barID][key] = value
        end
    end
    if ns.refreshWidgets then
        ns.refreshWidgets()
    end
    print(PREFIX .. "All settings reset to defaults.")
end

SLASH_ZAEUIACTIONBARS1 = "/zab"

SlashCmdList["ZAEUIACTIONBARS"] = function(msg)
    msg = strtrim(msg)

    if msg == "" then
        if ns.settingsCategory then
            Settings.OpenToCategory(ns.settingsCategory.ID)
        else
            print(PREFIX .. "Options panel not yet loaded.")
        end
        return
    end

    if msg == "help" then
        print(PREFIX .. "Usage:")
        print(PREFIX .. "  /zab - Open the options panel")
        print(PREFIX .. "  /zab reset - Reset all settings to defaults")
        print(PREFIX .. "  /zab help - Show this help")
        return
    end

    if msg == "reset" then
        resetDefaults()
        return
    end

    print(PREFIX .. "Unknown command. Type /zab help for usage.")
end

-- Expose to namespace for Options.lua
ns.BEHAVIOR_OPTIONS = {
    { "default", "Default" },
    { "show", "Show only" },
    { "hide", "Hide" },
}
ns.constants = {
    MIN_FADE = MIN_FADE, MAX_FADE = MAX_FADE,
    DEFAULT_FADE_IN = DEFAULT_FADE_IN, DEFAULT_FADE_OUT = DEFAULT_FADE_OUT,
    MIN_DELAY = MIN_DELAY, MAX_DELAY = MAX_DELAY, DEFAULT_DELAY = DEFAULT_DELAY,
    BEHAVIOR_DEFAULT = BEHAVIOR_DEFAULT,
    BAR_DEFAULTS = BAR_DEFAULTS,
}
ns.bars = barStates
ns.BAR_REGISTRY = BAR_REGISTRY
ns.BAR_NAMES = BAR_NAMES
ns.BAR_ORDER = BAR_ORDER
ns.applyBar = applyBar
ns.removeBar = removeBar
ns.resetDefaults = resetDefaults

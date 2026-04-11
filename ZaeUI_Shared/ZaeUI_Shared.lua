-- ZaeUI_Shared: Common utilities for all ZaeUI addons
-- Provides shared UI widgets, backdrop styling, a minimap button and helper
-- functions. Hosts the "ZaeUI" parent category for Blizzard Settings.

local CreateFrame = CreateFrame
local math_floor = math.floor
local string_format = string.format
local type = type
local pairs = pairs
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid

-- Shared backdrop definition
local SHARED_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

-- Shared SavedVariables defaults. The `minimapButton` sub-table uses the
-- key names expected by LibDBIcon-1.0 (hide, lock, minimapPos, ...).
local SHARED_DEFAULTS = {
    minimapButton = {
        hide = false,
        minimapPos = 225, -- degrees, 225° = bottom-left of the minimap
    },
}

-- LibDBIcon-1.0 key used to register / look up our button.
local MINIMAP_BUTTON_KEY = "ZaeUI"

ZaeUI_Shared = {}

-- Module-level state populated on ADDON_LOADED / PLAYER_LOGIN.
local sharedDB

--- Initialize ZaeUI_SharedDB with defaults for any missing keys.
--- Also migrates from the pre-LibDBIcon flat layout that existed only in
--- unreleased 1.3.0 dev builds (minimapButtonEnabled / minimapButtonAngle).
local function initSharedDB()
    if not ZaeUI_SharedDB then
        ZaeUI_SharedDB = {}
    end
    if ZaeUI_SharedDB.minimapButtonEnabled ~= nil or ZaeUI_SharedDB.minimapButtonAngle ~= nil then
        ZaeUI_SharedDB.minimapButton = ZaeUI_SharedDB.minimapButton or {
            hide = ZaeUI_SharedDB.minimapButtonEnabled == false,
            minimapPos = ZaeUI_SharedDB.minimapButtonAngle or 225,
        }
        ZaeUI_SharedDB.minimapButtonEnabled = nil
        ZaeUI_SharedDB.minimapButtonAngle = nil
    end
    for key, value in pairs(SHARED_DEFAULTS) do
        if ZaeUI_SharedDB[key] == nil then
            if type(value) == "table" then
                local copy = {}
                for k, v in pairs(value) do copy[k] = v end
                ZaeUI_SharedDB[key] = copy
            else
                ZaeUI_SharedDB[key] = value
            end
        end
    end
    -- Fill any missing keys inside the minimapButton sub-table.
    for k, v in pairs(SHARED_DEFAULTS.minimapButton) do
        if ZaeUI_SharedDB.minimapButton[k] == nil then
            ZaeUI_SharedDB.minimapButton[k] = v
        end
    end
    sharedDB = ZaeUI_SharedDB
end

--- Check if the player is in any type of group.
--- Covers manual groups (LE_PARTY_CATEGORY_HOME) and LFG/instance groups
--- (LE_PARTY_CATEGORY_INSTANCE) so the addon works in all scenarios.
--- @return boolean
function ZaeUI_Shared.isInAnyGroup()
    return not not (IsInGroup() or IsInGroup(LE_PARTY_CATEGORY_INSTANCE) or IsInRaid())
end

--- Apply standard backdrop styling to a frame (without opacity).
--- Callers should set alpha separately since each addon uses a different db key.
--- @param frame table The frame (must inherit BackdropTemplate)
function ZaeUI_Shared.applyBackdrop(frame)
    frame:SetBackdrop(SHARED_BACKDROP)
    frame:SetBackdropColor(0, 0, 0, 0.8)
    frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
end

-- Right-click context menu -----------------------------------------------

-- Ordered list of actions registered by sub-addons for the right-click menu.
local menuActions = {}
local table_sort = table.sort

--- Public: register an action to appear in the minimap button right-click menu.
--- Sub-addons should call this from their ADDON_LOADED handler so the entry
--- is available the first time the menu is opened.
--- @param label string Menu label (displayed as-is)
--- @param onClick function Handler called with no arguments when clicked
--- @param order number|nil Sort order (lower = earlier). Defaults to registration order.
function ZaeUI_Shared.registerMenuAction(label, onClick, order)
    if type(label) ~= "string" or type(onClick) ~= "function" then return end
    menuActions[#menuActions + 1] = {
        label = label,
        onClick = onClick,
        order = order or (#menuActions + 1),
    }
    table_sort(menuActions, function(a, b) return a.order < b.order end)
end

--- Open the Blizzard Settings on the ZaeUI parent category.
local function openZaeUISettings()
    if ZaeUI_SettingsCategory and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(ZaeUI_SettingsCategory.ID)
    end
end

--- Show the minimap button right-click context menu.
--- @param owner table The frame that anchors the menu (usually the LDB button)
local function showContextMenu(owner)
    if not MenuUtil or not MenuUtil.CreateContextMenu then return end
    MenuUtil.CreateContextMenu(owner, function(_, rootDescription)
        rootDescription:CreateTitle("ZaeUI")
        rootDescription:CreateButton("Open Settings", openZaeUISettings)
        if #menuActions > 0 then
            rootDescription:CreateDivider()
            for _, action in ipairs(menuActions) do
                rootDescription:CreateButton(action.label, action.onClick)
            end
        end
        rootDescription:CreateDivider()
        rootDescription:CreateButton("Hide minimap button", function()
            ZaeUI_Shared.setMinimapButtonShown(false)
        end)
    end)
end

-- Minimap button (LibDBIcon-1.0) ------------------------------------------

--- Register the LDB launcher and the minimap button. Safe to call multiple
--- times; LibDBIcon guards against double-registration via IsRegistered.
local function registerMinimapButton()
    if not sharedDB then return end
    if not LibStub then return end
    local LibDBIcon = LibStub("LibDBIcon-1.0", true)
    local LibDataBroker = LibStub("LibDataBroker-1.1", true)
    if not LibDBIcon or not LibDataBroker then return end
    if LibDBIcon:IsRegistered(MINIMAP_BUTTON_KEY) then return end

    -- NewDataObject returns nil if the name is already taken, so reuse the
    -- existing object in that case (edge case when the addon is reloaded).
    local launcher = LibDataBroker:GetDataObjectByName(MINIMAP_BUTTON_KEY)
    if not launcher then
        launcher = LibDataBroker:NewDataObject(MINIMAP_BUTTON_KEY, {
            type = "launcher",
            label = "ZaeUI",
            text = "ZaeUI",
            icon = "Interface\\AddOns\\ZaeUI_Shared\\Textures\\logo",
            OnClick = function(self, button)
                if button == "RightButton" then
                    showContextMenu(self)
                    return
                end
                openZaeUISettings()
            end,
            OnTooltipShow = function(tooltip)
                if not tooltip or not tooltip.AddLine then return end
                tooltip:AddLine("ZaeUI")
                tooltip:AddLine("|cffffffffLeft-click|r to open settings", 1, 1, 1)
                tooltip:AddLine("|cffffffffRight-click|r for actions", 1, 1, 1)
                tooltip:AddLine("|cffffffffDrag|r to reposition", 1, 1, 1)
            end,
        })
    end
    if not launcher then return end

    LibDBIcon:Register(MINIMAP_BUTTON_KEY, launcher, sharedDB.minimapButton)
end

--- Public: toggle the minimap button visibility and persist the choice.
--- @param shown boolean
function ZaeUI_Shared.setMinimapButtonShown(shown)
    if not sharedDB or not sharedDB.minimapButton then return end
    sharedDB.minimapButton.hide = not shown
    if not LibStub then return end
    local LibDBIcon = LibStub("LibDBIcon-1.0", true)
    if not LibDBIcon then return end
    if shown then
        LibDBIcon:Show(MINIMAP_BUTTON_KEY)
    else
        LibDBIcon:Hide(MINIMAP_BUTTON_KEY)
    end
end

--- Public: return whether the minimap button is currently visible.
--- @return boolean
function ZaeUI_Shared.isMinimapButtonShown()
    if not sharedDB or not sharedDB.minimapButton then return false end
    return not sharedDB.minimapButton.hide
end

--- Ensure the shared ZaeUI parent settings category exists.
--- Must be called synchronously (not in a timer) to avoid race conditions.
--- @return table parentCategory The shared parent category
function ZaeUI_Shared.ensureParentCategory()
    if ZaeUI_SettingsCategory then
        return ZaeUI_SettingsCategory
    end

    local parentPanel = CreateFrame("Frame")
    parentPanel:SetSize(1, 1)

    local parentTitle = parentPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    parentTitle:SetPoint("TOPLEFT", 16, -16)
    parentTitle:SetText("ZaeUI")

    local parentDesc = parentPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    parentDesc:SetPoint("TOPLEFT", parentTitle, "BOTTOMLEFT", 0, -8)
    parentDesc:SetText("A collection of lightweight World of Warcraft addons.")

    -- Global ZaeUI settings section (shared across every sub-addon)
    local globalHeader = parentPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    globalHeader:SetPoint("TOPLEFT", parentDesc, "BOTTOMLEFT", 0, -20)
    globalHeader:SetText("Global")

    local minimapCb, _ = ZaeUI_Shared.createCheckbox(
        parentPanel,
        -(16 + 16 + 20 + 20 + 16 + 24), -- initial y offset below the header
        "Show minimap button",
        function() return ZaeUI_Shared.isMinimapButtonShown() end,
        function(checked) ZaeUI_Shared.setMinimapButtonShown(checked) end
    )
    -- Re-anchor the checkbox directly under the Global header for a clean layout,
    -- independent of the createCheckbox initial positioning math above.
    minimapCb:ClearAllPoints()
    minimapCb:SetPoint("TOPLEFT", globalHeader, "BOTTOMLEFT", 0, -6)

    local hint = parentPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", minimapCb, "BOTTOMLEFT", 4, -4)
    hint:SetText("Click the button to open this panel. Shift-drag to reposition it around the minimap.")

    local category = Settings.RegisterCanvasLayoutCategory(parentPanel, "ZaeUI")
    Settings.RegisterAddOnCategory(category)
    ZaeUI_SettingsCategory = category
    return category
end

-- Shared addon lifecycle --------------------------------------------------

local sharedFrame = CreateFrame("Frame")
sharedFrame:RegisterEvent("ADDON_LOADED")
sharedFrame:RegisterEvent("PLAYER_LOGIN")
sharedFrame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" then
        if addonName ~= "ZaeUI_Shared" then return end
        initSharedDB()
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        -- Register with LibDBIcon on PLAYER_LOGIN so Minimap dimensions and
        -- external minimap shape providers (MBB, SexyMap, ...) are ready.
        registerMinimapButton()
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)

--- Create a checkbox control.
--- @param parent table Parent frame
--- @param y number Y offset from TOPLEFT
--- @param label string Checkbox label
--- @param get function Returns current boolean value
--- @param set function Called with new boolean value
--- @return table checkbox The created checkbox
--- @return number nextY The Y offset for the next widget
function ZaeUI_Shared.createCheckbox(parent, y, label, get, set)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
    cb.text:SetText(label)
    cb.text:SetFontObject("GameFontHighlight")
    cb:SetChecked(get())
    cb:SetScript("OnClick", function(self)
        set(not not self:GetChecked())
    end)
    cb.refresh = function()
        cb:SetChecked(get())
    end
    return cb, y - 30
end

--- Create a slider control with value display.
--- @param parent table Parent frame
--- @param y number Y offset from TOPLEFT
--- @param label string Slider label
--- @param minVal number Minimum value
--- @param maxVal number Maximum value
--- @param step number Step increment
--- @param get function Returns current value
--- @param set function Called with new value
--- @param fmt string|nil Format string for display (e.g. "%d%%"), defaults to tostring
--- @return table slider The created slider
--- @return number nextY The Y offset for the next widget
function ZaeUI_Shared.createSlider(parent, y, label, minVal, maxVal, step, get, set, fmt)
    local sliderLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sliderLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
    sliderLabel:SetText(label)

    local valueText = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueText:SetPoint("LEFT", sliderLabel, "RIGHT", 8, 0)

    y = y - 18
    local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, y)
    slider:SetWidth(180)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(get())
    slider.Low:SetText("")
    slider.High:SetText("")
    slider.Text:SetText("")

    if fmt then
        valueText:SetText(string_format(fmt, get()))
    else
        valueText:SetText(tostring(get()))
    end

    slider:SetScript("OnValueChanged", function(_, value)
        value = math_floor(value / step + 0.5) * step
        if fmt then
            valueText:SetText(string_format(fmt, value))
        else
            valueText:SetText(tostring(value))
        end
        set(value)
    end)
    slider.refresh = function()
        slider:SetValue(get())
        if fmt then
            valueText:SetText(string_format(fmt, get()))
        else
            valueText:SetText(tostring(get()))
        end
    end

    --- Set enabled/disabled state for the slider and its label.
    local origSetEnabled = slider.SetEnabled
    slider.SetEnabled = function(self, enabled)
        origSetEnabled(self, enabled)
        if enabled then
            sliderLabel:SetFontObject("GameFontHighlight")
        else
            sliderLabel:SetFontObject("GameFontDisable")
        end
    end

    return slider, y - 24
end

--- Create a dropdown control.
--- @param parent table Parent frame
--- @param y number Y offset from TOPLEFT
--- @param label string Dropdown label
--- @param options table Array of { value = string, text = string }
--- @param get function Returns current value string
--- @param set function Called with new value string
--- @return table dropdown The created dropdown container
--- @return number nextY The Y offset for the next widget
function ZaeUI_Shared.createDropdown(parent, y, label, options, get, set)
    local dropLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    dropLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
    dropLabel:SetText(label)
    y = y - 20

    local container = CreateFrame("Frame", nil, parent)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
    container:SetSize(200, 28)

    local bg = container:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)

    local selected = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    selected:SetPoint("LEFT", 8, 0)

    local arrow = container:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(12, 12)
    arrow:SetPoint("RIGHT", -4, 0)
    arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")

    -- Find display text for current value
    local function updateText()
        local val = get()
        for _, opt in ipairs(options) do
            if opt.value == val then
                selected:SetText(opt.text)
                return
            end
        end
        selected:SetText(val or "")
    end
    updateText()

    -- Custom popup menu (no taint)
    local popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    popup:SetBackdropColor(0.08, 0.08, 0.1, 0.95)
    popup:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    popup:Hide()
    popup:EnableMouse(true)

    local OPTION_HEIGHT = 22
    local optionButtons = {}
    for i, opt in ipairs(options) do
        local optBtn = CreateFrame("Button", nil, popup)
        optBtn:SetHeight(OPTION_HEIGHT)
        optBtn:SetPoint("TOPLEFT", popup, "TOPLEFT", 4, -4 - ((i - 1) * OPTION_HEIGHT))
        optBtn:SetPoint("RIGHT", popup, "RIGHT", -4, 0)

        local optBg = optBtn:CreateTexture(nil, "BACKGROUND")
        optBg:SetAllPoints()
        optBg:SetColorTexture(1, 1, 1, 0)

        local optText = optBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        optText:SetPoint("LEFT", 8, 0)
        optText:SetText(opt.text)

        local optCheck = optBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        optCheck:SetPoint("RIGHT", -8, 0)

        optBtn:SetScript("OnEnter", function() optBg:SetColorTexture(1, 1, 1, 0.1) end)
        optBtn:SetScript("OnLeave", function() optBg:SetColorTexture(1, 1, 1, 0) end)
        optBtn:SetScript("OnClick", function()
            set(opt.value)
            updateText()
            popup:Hide()
            -- Update check marks
            for j, ob in ipairs(optionButtons) do
                ob.check:SetText(options[j].value == opt.value and "|cff44ff44*|r" or "")
            end
        end)

        optBtn.check = optCheck
        optionButtons[i] = optBtn
    end

    popup:SetSize(200, 8 + (#options * OPTION_HEIGHT))

    -- Close popup when clicking elsewhere
    popup:SetScript("OnShow", function()
        -- Update check marks on show
        local val = get()
        for i, ob in ipairs(optionButtons) do
            ob.check:SetText(options[i].value == val and "|cff44ff44*|r" or "")
        end
    end)

    -- Close on escape or click outside
    local closeFrame = CreateFrame("Frame", nil, popup)
    closeFrame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            popup:Hide()
            self:SetPropagateKeyboardInput(false)
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    local btn = CreateFrame("Button", nil, container)
    btn:SetAllPoints()
    btn:SetScript("OnClick", function(self)
        if popup:IsShown() then
            popup:Hide()
        else
            popup:ClearAllPoints()
            popup:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
            popup:Show()
        end
    end)

    -- Hide popup when parent settings panel hides
    container:SetScript("OnHide", function() popup:Hide() end)

    container.refresh = function()
        updateText()
    end

    return container, y - 32
end

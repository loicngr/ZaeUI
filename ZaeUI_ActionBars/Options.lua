-- ZaeUI_ActionBars Options panel
-- Registers a settings panel under AddOns > ZaeUI > ActionBars

local _, ns = ...

local math_floor = math.floor

-- Widget helpers ----------------------------------------------------------------

--- Create a checkbox control.
--- @param parent table Parent frame
--- @param y number Y offset from TOPLEFT
--- @param label string Checkbox label
--- @param get function Returns current boolean value
--- @param set function Called with new boolean value
--- @return table checkbox The created checkbox
--- @return number nextY The Y offset for the next widget
local function createCheckbox(parent, y, label, get, set)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
    cb.text:SetText(label)
    cb.text:SetFontObject("GameFontHighlight")
    cb:SetChecked(get())
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked())
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
--- @param get function Returns current numeric value
--- @param set function Called with new numeric value
--- @return table slider The created slider
--- @return number nextY The Y offset for the next widget
local function createSlider(parent, y, label, minVal, maxVal, step, get, set)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(250, 50)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, y)

    local title = container:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetText(label)

    local slider = CreateFrame("Slider", nil, container, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 0, -18)
    slider:SetWidth(220)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(get())
    slider.Low:SetText(tostring(minVal))
    slider.High:SetText(tostring(maxVal))

    local valueText = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueText:SetPoint("LEFT", slider, "RIGHT", 8, 0)
    valueText:SetText(tostring(get()))

    slider:SetScript("OnValueChanged", function(_, value)
        local mult = 1 / step
        value = math_floor(value * mult + 0.5) / mult
        valueText:SetText(tostring(value))
        set(value)
    end)

    slider.refresh = function()
        slider:SetValue(get())
        valueText:SetText(tostring(get()))
    end

    return slider, y - 56
end

--- Create a cycle button that rotates through a list of options.
--- @param parent table Parent frame
--- @param y number Y offset from TOPLEFT
--- @param label string Button label
--- @param options table Array of { value, text } pairs
--- @param get function Returns current value
--- @param set function Called with new value
--- @return table button The created button
--- @return number nextY The Y offset for the next widget
local function createCycleButton(parent, y, label, options, get, set)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(350, 26)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)

    local title = container:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("LEFT", 0, 0)
    title:SetText(label .. ":")

    local btn = CreateFrame("Button", nil, container)
    btn:SetSize(120, 22)
    btn:SetPoint("LEFT", title, "RIGHT", 8, 0)

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.2, 0.2, 0.2, 0.8)

    local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btnText:SetPoint("CENTER")

    local function updateText()
        local current = get()
        for i = 1, #options do
            if options[i][1] == current then
                btnText:SetText(options[i][2])
                return
            end
        end
        btnText:SetText("?")
    end

    updateText()

    btn:SetScript("OnClick", function()
        local current = get()
        local nextIdx = 1
        for i = 1, #options do
            if options[i][1] == current then
                nextIdx = (i % #options) + 1
                break
            end
        end
        set(options[nextIdx][1])
        updateText()
    end)

    btn:SetScript("OnEnter", function()
        bg:SetColorTexture(0.3, 0.3, 0.3, 0.9)
    end)
    btn:SetScript("OnLeave", function()
        bg:SetColorTexture(0.2, 0.2, 0.2, 0.8)
    end)

    btn.refresh = function()
        updateText()
    end

    return btn, y - 30
end

-- Parent category ---------------------------------------------------------------

--- Ensure the shared ZaeUI parent category exists.
--- @return table parentCategory The shared parent category
local function ensureParentCategory()
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

    local category = Settings.RegisterCanvasLayoutCategory(parentPanel, "ZaeUI")
    Settings.RegisterAddOnCategory(category)
    ZaeUI_SettingsCategory = category
    return category
end

-- Tab bar colors
local TAB_COLOR_NORMAL = { r = 0.2, g = 0.2, b = 0.2, a = 0.8 }
local TAB_COLOR_HOVER = { r = 0.3, g = 0.3, b = 0.3, a = 0.9 }
local TAB_COLOR_SELECTED = { r = 0.1, g = 0.4, b = 0.7, a = 1.0 }
local TAB_HEIGHT = 24
local TAB_SPACING = 2
local TABS_PER_ROW = 5

-- Panel creation ----------------------------------------------------------------

local function createOptionsPanel(parentCategory)
    local currentDB = ns.db
    local C = ns.constants
    local orderList = ns.BAR_ORDER
    local nameList = ns.BAR_NAMES

    local panel = CreateFrame("Frame")
    panel:SetSize(1, 1)

    -- Tab buttons container (two rows: 5 + 5)
    local tabContainer = CreateFrame("Frame", nil, panel)
    tabContainer:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -8)
    tabContainer:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -8)
    tabContainer:SetHeight(TAB_HEIGHT * 2 + TAB_SPACING)

    -- Content area below tabs
    local contentArea = CreateFrame("Frame", nil, panel)
    contentArea:SetPoint("TOPLEFT", tabContainer, "BOTTOMLEFT", 0, -8)
    contentArea:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)

    -- Separator line between tabs and content
    local separator = contentArea:CreateTexture(nil, "ARTWORK")
    separator:SetPoint("TOPLEFT", contentArea, "TOPLEFT", 0, 0)
    separator:SetPoint("TOPRIGHT", contentArea, "TOPRIGHT", 0, 0)
    separator:SetHeight(1)
    separator:SetColorTexture(0.4, 0.4, 0.4, 0.6)

    -- Per-bar content frames (created once, shown/hidden on tab switch)
    local barPages = {}
    local tabButtons = {}
    local selectedTab = nil

    --- Switch to the given tab, hiding all others.
    --- @param barID string The bar to show
    local function selectTab(barID)
        if selectedTab == barID then return end
        -- Hide previous page
        if selectedTab and barPages[selectedTab] then
            barPages[selectedTab]:Hide()
        end
        -- Update tab button colors
        for _, id in ipairs(orderList) do
            local btn = tabButtons[id]
            if id == barID then
                btn.bg:SetColorTexture(TAB_COLOR_SELECTED.r, TAB_COLOR_SELECTED.g, TAB_COLOR_SELECTED.b, TAB_COLOR_SELECTED.a)
                btn.label:SetFontObject("GameFontHighlight")
            else
                btn.bg:SetColorTexture(TAB_COLOR_NORMAL.r, TAB_COLOR_NORMAL.g, TAB_COLOR_NORMAL.b, TAB_COLOR_NORMAL.a)
                btn.label:SetFontObject("GameFontNormalSmall")
            end
        end
        -- Show new page
        selectedTab = barID
        barPages[barID]:Show()
    end

    -- Create tab buttons (two rows of 5)
    for i, barID in ipairs(orderList) do
        local row = (i <= TABS_PER_ROW) and 0 or 1
        local col = (i <= TABS_PER_ROW) and (i - 1) or (i - TABS_PER_ROW - 1)

        local btn = CreateFrame("Button", nil, tabContainer)
        btn:SetHeight(TAB_HEIGHT)

        -- Background texture
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(TAB_COLOR_NORMAL.r, TAB_COLOR_NORMAL.g, TAB_COLOR_NORMAL.b, TAB_COLOR_NORMAL.a)
        btn.bg = bg

        -- Label
        local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("CENTER")
        label:SetText(nameList[barID])
        btn.label = label

        -- Position: evenly spaced across the container width
        local yOffset = -(row * (TAB_HEIGHT + TAB_SPACING))

        btn:SetPoint("TOPLEFT", tabContainer, "TOPLEFT", 0, yOffset)
        -- Use relative width via anchoring to fraction of container
        btn:SetScript("OnShow", function(self)
            local containerWidth = tabContainer:GetWidth()
            local tabWidth = (containerWidth - (TABS_PER_ROW - 1) * TAB_SPACING) / TABS_PER_ROW
            self:SetWidth(tabWidth)
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", tabContainer, "TOPLEFT", col * (tabWidth + TAB_SPACING), yOffset)
        end)

        -- Hover effects
        btn:SetScript("OnEnter", function()
            if selectedTab ~= barID then
                bg:SetColorTexture(TAB_COLOR_HOVER.r, TAB_COLOR_HOVER.g, TAB_COLOR_HOVER.b, TAB_COLOR_HOVER.a)
            end
        end)
        btn:SetScript("OnLeave", function()
            if selectedTab ~= barID then
                bg:SetColorTexture(TAB_COLOR_NORMAL.r, TAB_COLOR_NORMAL.g, TAB_COLOR_NORMAL.b, TAB_COLOR_NORMAL.a)
            end
        end)

        btn:SetScript("OnClick", function()
            selectTab(barID)
        end)

        tabButtons[barID] = btn
    end

    -- Resize tabs when panel size changes
    panel:SetScript("OnSizeChanged", function()
        local containerWidth = tabContainer:GetWidth()
        if containerWidth <= 0 then return end
        local tabWidth = (containerWidth - (TABS_PER_ROW - 1) * TAB_SPACING) / TABS_PER_ROW
        for i, barID in ipairs(orderList) do
            local row = (i <= TABS_PER_ROW) and 0 or 1
            local col = (i <= TABS_PER_ROW) and (i - 1) or (i - TABS_PER_ROW - 1)
            local yOffset = -(row * (TAB_HEIGHT + TAB_SPACING))
            local btn = tabButtons[barID]
            btn:SetWidth(tabWidth)
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", tabContainer, "TOPLEFT", col * (tabWidth + TAB_SPACING), yOffset)
        end
    end)

    -- Per-bar widget lists for refresh
    local barWidgets = {}

    -- Create content pages for each bar
    for _, barID in ipairs(orderList) do
        local barSettings = currentDB.bars[barID]
        local widgets = {}

        -- Page container (holds the scroll frame)
        local page = CreateFrame("Frame", nil, contentArea)
        page:SetPoint("TOPLEFT", contentArea, "TOPLEFT", 0, -8)
        page:SetPoint("BOTTOMRIGHT", contentArea, "BOTTOMRIGHT", 0, 0)
        page:Hide()

        -- ScrollFrame inside each tab page
        local pageScroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
        pageScroll:SetPoint("TOPLEFT", 0, 0)
        pageScroll:SetPoint("BOTTOMRIGHT", -26, 0)

        local pageContent = CreateFrame("Frame", nil, pageScroll)
        pageContent:SetWidth(pageScroll:GetWidth() or 540)
        pageScroll:SetScrollChild(pageContent)

        page:SetScript("OnSizeChanged", function(_, width)
            pageContent:SetWidth(width - 26)
        end)

        local y = -8
        local w

        w, y = createCheckbox(pageContent, y, "Enable",
            function() return barSettings.enabled end,
            function(checked)
                if checked and InCombatLockdown() then
                    print("|cff00ccff[ZaeUI_ActionBars]|r Cannot enable bar during combat. Try again after combat.")
                    -- Revert checkbox visually
                    C_Timer.After(0, function() w:SetChecked(false) end)
                    return
                end
                barSettings.enabled = checked
                if checked then
                    ns.applyBar(barID)
                else
                    ns.removeBar(barID)
                end
            end
        )
        widgets[#widgets + 1] = w

        w, y = createCheckbox(pageContent, y, "Show in combat",
            function() return barSettings.showInCombat end,
            function(checked) barSettings.showInCombat = checked end
        )
        widgets[#widgets + 1] = w

        w, y = createCycleButton(pageContent, y, "While flying", ns.BEHAVIOR_OPTIONS,
            function() return barSettings.flyingBehavior end,
            function(v)
                if InCombatLockdown() then
                    print("|cff00ccff[ZaeUI_ActionBars]|r Cannot change this setting during combat.")
                    return
                end
                barSettings.flyingBehavior = v
                ns.applyBar(barID)
            end
        )
        widgets[#widgets + 1] = w

        w, y = createCycleButton(pageContent, y, "While mounted", ns.BEHAVIOR_OPTIONS,
            function() return barSettings.mountedBehavior end,
            function(v)
                if InCombatLockdown() then
                    print("|cff00ccff[ZaeUI_ActionBars]|r Cannot change this setting during combat.")
                    return
                end
                barSettings.mountedBehavior = v
                ns.applyBar(barID)
            end
        )
        widgets[#widgets + 1] = w

        w, y = createSlider(pageContent, y, "Fade In (s)", C.MIN_FADE, C.MAX_FADE, 0.1,
            function() return barSettings.fadeIn end,
            function(v) barSettings.fadeIn = v end
        )
        widgets[#widgets + 1] = w

        w, y = createSlider(pageContent, y, "Fade Out (s)", C.MIN_FADE, C.MAX_FADE, 0.1,
            function() return barSettings.fadeOut end,
            function(v) barSettings.fadeOut = v end
        )
        widgets[#widgets + 1] = w

        w, y = createSlider(pageContent, y, "Delay (s)", C.MIN_DELAY, C.MAX_DELAY, 0.1,
            function() return barSettings.delay end,
            function(v) barSettings.delay = v end
        )
        widgets[#widgets + 1] = w

        pageContent:SetHeight(-y + 16)

        barPages[barID] = page
        barWidgets[barID] = widgets
    end

    -- Expose refresh function for /zab reset
    ns.refreshWidgets = function()
        for _, barID in ipairs(orderList) do
            local wList = barWidgets[barID]
            if wList then
                for j = 1, #wList do
                    if wList[j].refresh then
                        wList[j].refresh()
                    end
                end
            end
        end
    end

    -- Select first tab by default
    selectTab(orderList[1])

    local subCategory = Settings.RegisterCanvasLayoutSubcategory(parentCategory, panel, "ActionBars")

    ns.settingsCategory = subCategory
end

-- Loader --------------------------------------------------------------------

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, addonName)
    if addonName ~= "ZaeUI_ActionBars" then return end
    self:UnregisterEvent("ADDON_LOADED")

    local parentCategory = ensureParentCategory()

    C_Timer.After(0, function()
        if ns.db then
            createOptionsPanel(parentCategory)
        else
            print("|cff00ccff[ZaeUI_ActionBars]|r Options panel failed to load: database not initialized.")
        end
    end)
end)

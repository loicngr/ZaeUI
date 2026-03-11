-- ZaeUI_Interrupts Options panel
-- Registers a settings panel under AddOns > ZaeUI > Interrupts

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
        set(not not self:GetChecked())
    end)
    return cb, y - 30
end

--- Create a slider control.
--- @param parent table Parent frame
--- @param y number Y offset from TOPLEFT
--- @param label string Slider label
--- @param minVal number Minimum value
--- @param maxVal number Maximum value
--- @param step number Step increment
--- @param get function Returns current value
--- @param set function Called with new value
--- @param fmt string Format string for display (e.g. "%d%%")
--- @return table slider The created slider
--- @return number nextY The Y offset for the next widget
local function createSlider(parent, y, label, minVal, maxVal, step, get, set, fmt)
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
    valueText:SetText(string.format(fmt, get()))
    slider:SetScript("OnValueChanged", function(_, value)
        value = math_floor(value / step + 0.5) * step
        valueText:SetText(string.format(fmt, value))
        set(value)
    end)
    return slider, y - 24
end

-- Parent category ---------------------------------------------------------------

--- Ensure the shared ZaeUI parent category exists.
--- Must be called synchronously (not in a timer) to avoid race conditions.
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
    category.ID = "ZaeUI"
    Settings.RegisterAddOnCategory(category)
    ZaeUI_SettingsCategory = category
    return category
end

-- Panel creation ----------------------------------------------------------------

local function createOptionsPanel(parentCategory)
    local db = ns.db

    -- Sub panel: Interrupts
    local panel = CreateFrame("Frame")
    panel:SetSize(1, 1)

    local y = -16

    local header = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, y)
    header:SetText("Interrupts")
    y = y - 28

    _, y = createCheckbox(panel, y, "Show tracker window",
        function() return db.showFrame end,
        function(checked)
            db.showFrame = checked
            if ns.showDisplay and ns.hideDisplay then
                if checked then
                    ns.showDisplay()
                else
                    ns.hideDisplay()
                end
            end
        end
    )

    _, y = createCheckbox(panel, y, "Auto-hide when not in a group",
        function() return db.autoHide end,
        function(checked)
            db.autoHide = checked
        end
    )

    _, y = createCheckbox(panel, y, "Show spell use counter",
        function() return db.showCounter end,
        function(checked)
            db.showCounter = checked
            if ns.refreshDisplay then ns.refreshDisplay() end
        end
    )

    _, y = createCheckbox(panel, y, "Auto-reset counters on instance entry",
        function() return db.autoResetCounters end,
        function(checked)
            db.autoResetCounters = checked
        end
    )

    _, y = createCheckbox(panel, y, "Hide ready spells (only show cooldowns)",
        function() return db.hideReady end,
        function(checked)
            db.hideReady = checked
            if ns.refreshDisplay then ns.refreshDisplay() end
        end
    )

    _, y = createCheckbox(panel, y, "Lock tracker window position",
        function() return db.lockFrame end,
        function(checked)
            db.lockFrame = checked
        end
    )

    -- Category filters
    y = y - 12
    local catHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    catHeader:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, y)
    catHeader:SetText("Category Filters")
    y = y - 22

    _, y = createCheckbox(panel, y, "Show Interrupts",
        function() return db.showInterrupts end,
        function(checked)
            db.showInterrupts = checked
            if ns.refreshDisplay then ns.refreshDisplay() end
        end
    )

    _, y = createCheckbox(panel, y, "Show Stuns",
        function() return db.showStuns end,
        function(checked)
            db.showStuns = checked
            if ns.refreshDisplay then ns.refreshDisplay() end
        end
    )

    _, y = createCheckbox(panel, y, "Show Others (knockbacks, disorients...)",
        function() return db.showOthers end,
        function(checked)
            db.showOthers = checked
            if ns.refreshDisplay then ns.refreshDisplay() end
        end
    )

    -- Kick Markers section
    y = y - 12
    local markerHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    markerHeader:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, y)
    markerHeader:SetText("Kick Markers")
    y = y - 22

    _, y = createCheckbox(panel, y, "Show markers in a separate window",
        function() return db.separateMarkerWindow end,
        function(checked)
            db.separateMarkerWindow = checked
            if ns.refreshDisplay then ns.refreshDisplay() end
            if ns.refreshMarkerDisplay then ns.refreshMarkerDisplay() end
        end
    )

    -- Common
    y = y - 12
    local commonHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    commonHeader:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, y)
    commonHeader:SetText("Common")
    y = y - 22

    _, y = createSlider(panel, y, "Window opacity", 10, 100, 5,
        function() return db.frameOpacity or 80 end,
        function(value)
            db.frameOpacity = value
            if ns.applyFrameOpacity then ns.applyFrameOpacity() end
        end,
        "%d%%"
    )

    -- Hint text
    y = y - 12
    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, y)
    hint:SetText("All group members need the addon for cooldown tracking.\nUse /zint assign to open kick marker assignments.")

    -- Register subcategory under ZaeUI
    local subCategory = Settings.RegisterCanvasLayoutSubcategory(parentCategory, panel, "Interrupts")
    subCategory.ID = "ZaeUI_Interrupts"

    -- Expose for /zint options command
    ns.settingsCategory = subCategory
end

-- Wait for the main addon to finish loading before creating the panel.
-- ns.db is set during ADDON_LOADED in the main file.
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, addonName)
    if addonName ~= "ZaeUI_Interrupts" then
        return
    end
    self:UnregisterEvent("ADDON_LOADED")

    -- Create parent category synchronously to avoid race with other ZaeUI addons
    local parentCategory = ensureParentCategory()

    -- Delay one frame to ensure ns.db is populated
    C_Timer.After(0, function()
        if ns.db then
            createOptionsPanel(parentCategory)
        else
            print("|cff00ccff[ZaeUI_Interrupts]|r Options panel failed to load: database not initialized.")
        end
    end)
end)

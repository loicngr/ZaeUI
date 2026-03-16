-- ZaeUI_Defensives Options panel
-- Registers a settings panel under AddOns > ZaeUI > Defensives

local _, ns = ...

local math_floor = math.floor
local C_Timer = C_Timer

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
    cb.refresh = function()
        cb:SetChecked(get())
    end
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
    slider.refresh = function()
        slider:SetValue(get())
        valueText:SetText(string.format(fmt, get()))
    end
    return slider, y - 24
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

-- Panel creation ----------------------------------------------------------------

local function createOptionsPanel(parentCategory)
    local db = ns.db

    local panel = CreateFrame("Frame")
    panel:SetSize(1, 1)

    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 0)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(scrollFrame:GetWidth() or 580)
    scrollFrame:SetScrollChild(content)

    panel:SetScript("OnSizeChanged", function(_, width)
        scrollFrame:SetPoint("BOTTOMRIGHT", -26, 0)
        content:SetWidth(width - 26)
    end)

    local widgets = {}
    local y = -16

    -- Section: Tracker ----------------------------------------------------------

    local trackerHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    trackerHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
    trackerHeader:SetText("Tracker")
    y = y - 28

    local w
    w, y = createCheckbox(content, y, "Show tracker window",
        function() return db.trackerEnabled end,
        function(checked)
            db.trackerEnabled = checked
            if ns.showDisplay and ns.hideDisplay then
                if checked then
                    ns.showDisplay()
                else
                    ns.hideDisplay()
                end
            end
        end
    )
    widgets[#widgets + 1] = w

    w, y = createCheckbox(content, y, "Auto-hide when not in a group",
        function() return db.trackerHideWhenSolo end,
        function(checked)
            db.trackerHideWhenSolo = checked
        end
    )
    widgets[#widgets + 1] = w

    w, y = createCheckbox(content, y, "Lock tracker window position",
        function() return db.trackerLocked end,
        function(checked)
            db.trackerLocked = checked
        end
    )
    widgets[#widgets + 1] = w

    -- Sub-header: Category Filters
    y = y - 12
    local catHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    catHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
    catHeader:SetText("Category Filters")
    y = y - 22

    w, y = createCheckbox(content, y, "Show Externals",
        function() return db.trackerShowExternal end,
        function(checked)
            db.trackerShowExternal = checked
            if ns.refreshDisplay then ns.refreshDisplay() end
        end
    )
    widgets[#widgets + 1] = w

    w, y = createCheckbox(content, y, "Show Personal",
        function() return db.trackerShowPersonal end,
        function(checked)
            db.trackerShowPersonal = checked
            if ns.refreshDisplay then ns.refreshDisplay() end
        end
    )
    widgets[#widgets + 1] = w

    w, y = createCheckbox(content, y, "Show Raidwide",
        function() return db.trackerShowRaidwide end,
        function(checked)
            db.trackerShowRaidwide = checked
            if ns.refreshDisplay then ns.refreshDisplay() end
        end
    )
    widgets[#widgets + 1] = w

    -- Sub-header: Appearance
    y = y - 12
    local appearanceHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    appearanceHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
    appearanceHeader:SetText("Appearance")
    y = y - 22

    w, y = createSlider(content, y, "Window opacity", 30, 100, 5,
        function() return db.trackerOpacity end,
        function(value)
            db.trackerOpacity = value
            if ns.applyFrameOpacity then ns.applyFrameOpacity() end
        end,
        "%d%%"
    )
    widgets[#widgets + 1] = w

    -- Hint text
    y = y - 20
    local hint = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
    hint:SetText("All group members need the addon for cooldown tracking.")

    content:SetHeight(-y + 40)

    -- Expose refresh function for /zdef reset
    ns.refreshWidgets = function()
        for i = 1, #widgets do
            if widgets[i].refresh then
                widgets[i].refresh()
            end
        end
    end

    local subCategory = Settings.RegisterCanvasLayoutSubcategory(parentCategory, panel, "Defensives")
    ns.settingsCategory = subCategory
end

-- Wait for the main addon to finish loading before creating the panel.
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, addonName)
    if addonName ~= "ZaeUI_Defensives" then
        return
    end
    self:UnregisterEvent("ADDON_LOADED")

    local parentCategory = ensureParentCategory()

    C_Timer.After(0, function()
        if ns.db then
            createOptionsPanel(parentCategory)
        else
            print("|cff00ccff[ZaeUI_Defensives]|r Options panel failed to load: database not initialized.")
        end
    end)
end)

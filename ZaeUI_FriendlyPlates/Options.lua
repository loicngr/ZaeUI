-- ZaeUI_FriendlyPlates Options panel
-- Registers a settings panel under AddOns > ZaeUI > FriendlyPlates

local _, ns = ...

local math_floor = math.floor

-- Widget helpers ----------------------------------------------------------------

--- Create a section header label.
--- @param parent table Parent frame
--- @param y number Y offset from TOPLEFT
--- @param text string Header text
--- @return table fontString The created font string
--- @return number nextY The Y offset for the next widget
local function createHeader(parent, y, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
    fs:SetText(text)
    return fs, y - 28
end

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

    local slider = CreateFrame("Slider", nil, container, "UISliderTemplate")
    slider:SetPoint("TOPLEFT", 0, -18)
    slider:SetWidth(220)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(get())
    -- UISliderTemplate may not include Low/High labels; create them if missing
    if not slider.Low then
        slider.Low = slider:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        slider.Low:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, 0)
    end
    if not slider.High then
        slider.High = slider:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        slider.High:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", 0, 0)
    end
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

    local origSetEnabled = slider.SetEnabled
    slider.SetEnabled = function(self, enabled)
        origSetEnabled(self, enabled)
        if enabled then
            title:SetFontObject("GameFontHighlight")
        else
            title:SetFontObject("GameFontDisable")
        end
    end

    return slider, y - 56
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
    local C = ns.constants

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

    -- Friendly Nameplates section
    _, y = createHeader(content, y, "Friendly Nameplates")

    local enableCB
    local showOnlyNameCB
    local classColorCB
    local customFontCB
    local fontSizeSlider

    enableCB, y = createCheckbox(content, y, "Enable Friendly Nameplates",
        function() return db.enabled end,
        function(checked)
            db.enabled = checked
            ns.applyCVars()
            if showOnlyNameCB then showOnlyNameCB:SetEnabled(checked) end
            if classColorCB then classColorCB:SetEnabled(checked) end
            if customFontCB then customFontCB:SetEnabled(checked) end
            if fontSizeSlider then fontSizeSlider:SetEnabled(checked and db.customFont) end
        end
    )
    widgets[#widgets + 1] = enableCB

    showOnlyNameCB, y = createCheckbox(content, y, "Show Only Name",
        function() return db.showOnlyName end,
        function(checked)
            db.showOnlyName = checked
            ns.applyCVars()
        end
    )
    showOnlyNameCB:SetEnabled(db.enabled)
    widgets[#widgets + 1] = showOnlyNameCB

    classColorCB, y = createCheckbox(content, y, "Class Color Names",
        function() return db.classColor end,
        function(checked)
            db.classColor = checked
            ns.applyCVars()
        end
    )
    classColorCB:SetEnabled(db.enabled)
    widgets[#widgets + 1] = classColorCB

    -- Font section
    _, y = createHeader(content, y - 8, "Font")

    customFontCB, y = createCheckbox(content, y, "Custom Font Size",
        function() return db.customFont end,
        function(checked)
            db.customFont = checked
            if checked then
                ns.applyFont()
                ns.setFontForAll()
            else
                ns.restoreFont()
                ns.reloadNameplates()
            end
            if fontSizeSlider then
                fontSizeSlider:SetEnabled(checked)
                if checked and fontSizeSlider.refresh then
                    fontSizeSlider.refresh()
                end
            end
        end
    )
    customFontCB:SetEnabled(db.enabled)
    widgets[#widgets + 1] = customFontCB

    fontSizeSlider, y = createSlider(content, y, "Font Size",
        C.MIN_FONT_SIZE, C.MAX_FONT_SIZE, 1,
        function() return db.fontSize end,
        function(v)
            db.fontSize = v
            if db.customFont then
                ns.forceUpdateFont(true)
                ns.setFontForAll()
            end
        end
    )
    fontSizeSlider:SetEnabled(db.enabled and db.customFont)
    widgets[#widgets + 1] = fontSizeSlider

    -- Hint text
    y = y - 40
    local hint = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
    hint:SetText("Changes apply immediately. Some settings may require a zone change in instances.")

    content:SetHeight(-y + 16)

    -- Expose refresh function for /zfp reset
    ns.refreshWidgets = function()
        for i = 1, #widgets do
            if widgets[i].refresh then
                widgets[i].refresh()
            end
        end
        -- Re-sync enabled state
        if showOnlyNameCB then showOnlyNameCB:SetEnabled(db.enabled) end
        if classColorCB then classColorCB:SetEnabled(db.enabled) end
        if customFontCB then customFontCB:SetEnabled(db.enabled) end
        if fontSizeSlider then fontSizeSlider:SetEnabled(db.enabled and db.customFont) end
    end

    local subCategory = Settings.RegisterCanvasLayoutSubcategory(parentCategory, panel, "FriendlyPlates")
    ns.settingsCategory = subCategory
end

-- Wait for the main addon to finish loading before creating the panel.
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, addonName)
    if addonName ~= "ZaeUI_FriendlyPlates" then
        return
    end
    self:UnregisterEvent("ADDON_LOADED")

    local parentCategory = ensureParentCategory()

    C_Timer.After(0, function()
        if ns.db then
            createOptionsPanel(parentCategory)
        else
            print("|cff00ccff[ZaeUI_FriendlyPlates]|r Options panel failed to load: database not initialized.")
        end
    end)
end)

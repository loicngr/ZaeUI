-- ZaeUI_Defensives Options panel
-- Registers a settings panel under AddOns > ZaeUI > Defensives

local _, ns = ...

local C_Timer = C_Timer

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
    w, y = ZaeUI_Shared.createDropdown(content, y, "Display mode",
        {
            { value = "floating",  text = "Floating window" },
            { value = "anchored",  text = "Anchored to unit frames" },
        },
        function() return db.displayMode or "floating" end,
        function(value)
            db.displayMode = value
            ns.routeHideDisplay()
            if db.trackerEnabled then
                ns.routeShowDisplay()
            end
            if ns.refreshWidgets then ns.refreshWidgets() end
        end
    )
    widgets[#widgets + 1] = w

    local floatingWidgets = {}

    local styleWidget
    styleWidget, y = ZaeUI_Shared.createDropdown(content, y, "Display style",
        {
            { value = "classic", text = "Classic" },
            { value = "modern",  text = "Modern" },
        },
        function() return db.displayStyle or "modern" end,
        function(value)
            db.displayStyle = value
            ns.switchDisplayStyle()
            if ns.refreshWidgets then ns.refreshWidgets() end
        end
    )
    widgets[#widgets + 1] = styleWidget
    floatingWidgets[#floatingWidgets + 1] = styleWidget

    y = y - 4

    w, y = ZaeUI_Shared.createCheckbox(content, y, "Enable display",
        function() return db.trackerEnabled end,
        function(checked)
            db.trackerEnabled = checked
            if checked then
                ns.routeShowDisplay()
            else
                ns.routeHideDisplay()
            end
        end
    )
    widgets[#widgets + 1] = w

    w, y = ZaeUI_Shared.createCheckbox(content, y, "Auto-hide when not in a group",
        function() return db.trackerHideWhenSolo end,
        function(checked)
            db.trackerHideWhenSolo = checked
        end
    )
    floatingWidgets[#floatingWidgets + 1] = w
    widgets[#widgets + 1] = w

    w, y = ZaeUI_Shared.createCheckbox(content, y, "Lock tracker window position",
        function() return db.trackerLocked end,
        function(checked)
            db.trackerLocked = checked
        end
    )
    floatingWidgets[#floatingWidgets + 1] = w
    widgets[#widgets + 1] = w

    -- Sub-header: Category Filters
    y = y - 12
    local catHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    catHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
    catHeader:SetText("Category Filters")
    y = y - 22

    w, y = ZaeUI_Shared.createCheckbox(content, y, "Show Externals",
        function() return db.trackerShowExternal end,
        function(checked)
            db.trackerShowExternal = checked
            if ns.routeRefreshDisplay then ns.routeRefreshDisplay() end
        end
    )
    widgets[#widgets + 1] = w

    w, y = ZaeUI_Shared.createCheckbox(content, y, "Show Personal",
        function() return db.trackerShowPersonal end,
        function(checked)
            db.trackerShowPersonal = checked
            if ns.routeRefreshDisplay then ns.routeRefreshDisplay() end
        end
    )
    widgets[#widgets + 1] = w

    w, y = ZaeUI_Shared.createCheckbox(content, y, "Show Raidwide",
        function() return db.trackerShowRaidwide end,
        function(checked)
            db.trackerShowRaidwide = checked
            if ns.routeRefreshDisplay then ns.routeRefreshDisplay() end
        end
    )
    widgets[#widgets + 1] = w

    -- Sub-header: Appearance
    y = y - 12
    local appearanceHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    appearanceHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
    appearanceHeader:SetText("Appearance")
    y = y - 22

    w, y = ZaeUI_Shared.createSlider(content, y, "Window opacity", 30, 100, 5,
        function() return db.trackerOpacity end,
        function(value)
            db.trackerOpacity = value
            if ns.applyFrameOpacity then ns.applyFrameOpacity() end
            if ns.applyModernTrackerOpacity then ns.applyModernTrackerOpacity() end
        end,
        "%d%%"
    )
    floatingWidgets[#floatingWidgets + 1] = w
    widgets[#widgets + 1] = w

    -- Sub-header: Anchored Mode Settings
    y = y - 12
    local anchoredHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    anchoredHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
    anchoredHeader:SetText("Anchored Display")
    y = y - 22

    local anchoredWidgets = {}

    w, y = ZaeUI_Shared.createSlider(content, y, "Icon size", 16, 48, 1,
        function() return db.anchoredIconSize or 28 end,
        function(value)
            db.anchoredIconSize = value
            ns.routeRefreshDisplay()
        end,
        "%dpx"
    )
    anchoredWidgets[#anchoredWidgets + 1] = w
    widgets[#widgets + 1] = w

    w, y = ZaeUI_Shared.createSlider(content, y, "Spacing", 0, 10, 1,
        function() return db.anchoredSpacing or 2 end,
        function(value)
            db.anchoredSpacing = value
            ns.routeRefreshDisplay()
        end,
        "%dpx"
    )
    anchoredWidgets[#anchoredWidgets + 1] = w
    widgets[#widgets + 1] = w

    w, y = ZaeUI_Shared.createSlider(content, y, "Icons per row", 2, 8, 1,
        function() return db.anchoredIconsPerRow or 4 end,
        function(value)
            db.anchoredIconsPerRow = value
            ns.routeRefreshDisplay()
        end
    )
    anchoredWidgets[#anchoredWidgets + 1] = w
    widgets[#widgets + 1] = w

    w, y = ZaeUI_Shared.createDropdown(content, y, "Anchor side",
        {
            { value = "BOTTOM",      text = "Bottom" },
            { value = "BOTTOMLEFT",  text = "Bottom-left" },
            { value = "BOTTOMRIGHT", text = "Bottom-right" },
            { value = "TOP",         text = "Top" },
            { value = "LEFT",        text = "Left" },
            { value = "RIGHT",       text = "Right" },
        },
        function() return db.anchoredSide or "BOTTOM" end,
        function(value)
            db.anchoredSide = value
            ns.routeRefreshDisplay()
        end
    )
    anchoredWidgets[#anchoredWidgets + 1] = w
    widgets[#widgets + 1] = w

    w, y = ZaeUI_Shared.createSlider(content, y, "Offset X", -50, 50, 1,
        function() return db.anchoredOffsetX or 0 end,
        function(value)
            db.anchoredOffsetX = value
            ns.routeRefreshDisplay()
        end
    )
    anchoredWidgets[#anchoredWidgets + 1] = w
    widgets[#widgets + 1] = w

    w, y = ZaeUI_Shared.createSlider(content, y, "Offset Y", -50, 50, 1,
        function() return db.anchoredOffsetY or 0 end,
        function(value)
            db.anchoredOffsetY = value
            ns.routeRefreshDisplay()
        end
    )
    anchoredWidgets[#anchoredWidgets + 1] = w
    widgets[#widgets + 1] = w

    w, y = ZaeUI_Shared.createCheckbox(content, y, "Show own cooldowns",
        function() return db.anchoredShowPlayer end,
        function(checked)
            db.anchoredShowPlayer = checked
            ns.routeRefreshDisplay()
        end
    )
    anchoredWidgets[#anchoredWidgets + 1] = w
    widgets[#widgets + 1] = w

    -- Hint text
    y = y - 20
    local hint = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
    hint:SetText("All group members need the addon for cooldown tracking.")

    -- Mode visibility toggling --------------------------------------------------

    local function updateModeVisibility()
        local mode = db.displayMode or "floating"
        local isFloating = (mode == "floating")
        for _, fw in ipairs(floatingWidgets) do
            if isFloating then fw:Show() else fw:Hide() end
        end
        appearanceHeader:SetShown(isFloating)
        anchoredHeader:SetShown(not isFloating)
        for _, aw in ipairs(anchoredWidgets) do
            if isFloating then aw:Hide() else aw:Show() end
        end
    end

    content:SetHeight(-y + 40)

    -- Expose refresh function for /zdef reset
    ns.refreshWidgets = function()
        for i = 1, #widgets do
            if widgets[i].refresh then
                widgets[i].refresh()
            end
        end
        updateModeVisibility()
    end

    updateModeVisibility()

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
    if not ZaeUI_Shared then return end

    local parentCategory = ZaeUI_Shared.ensureParentCategory()

    C_Timer.After(0, function()
        if ns.db then
            createOptionsPanel(parentCategory)
        else
            print("|cff00ccff[ZaeUI_Defensives]|r Options panel failed to load: database not initialized.")
        end
    end)
end)

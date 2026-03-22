-- ZaeUI_Interrupts Options panel
-- Registers a settings panel under AddOns > ZaeUI > Interrupts

local _, ns = ...

-- Panel creation ----------------------------------------------------------------

local function createOptionsPanel(parentCategory)
    local db = ns.db

    -- Sub panel: Interrupts
    local panel = CreateFrame("Frame")
    panel:SetSize(1, 1)

    -- ScrollFrame fills the panel
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

    local header = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
    header:SetText("Interrupts")
    y = y - 28

    local w
    w, y = ZaeUI_Shared.createCheckbox(content, y, "Show tracker window",
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
    widgets[#widgets + 1] = w

    w, y = ZaeUI_Shared.createDropdown(content, y, "Display style",
        {
            { value = "list", text = "List" },
            { value = "bars", text = "Progress Bars" },
        },
        function() return db.displayStyle or "list" end,
        function(value)
            db.displayStyle = value
            if ns.refreshDisplay then ns.refreshDisplay() end
        end
    )
    widgets[#widgets + 1] = w

    w, y = ZaeUI_Shared.createCheckbox(content, y, "Auto-hide when not in a group",
        function() return db.autoHide end,
        function(checked)
            db.autoHide = checked
        end
    )
    widgets[#widgets + 1] = w

    w, y = ZaeUI_Shared.createCheckbox(content, y, "Show spell use counter",
        function() return db.showCounter end,
        function(checked)
            db.showCounter = checked
            if ns.refreshDisplay then ns.refreshDisplay() end
        end
    )
    widgets[#widgets + 1] = w

    w, y = ZaeUI_Shared.createCheckbox(content, y, "Auto-reset counters on instance entry",
        function() return db.autoResetCounters end,
        function(checked)
            db.autoResetCounters = checked
        end
    )
    widgets[#widgets + 1] = w

    w, y = ZaeUI_Shared.createCheckbox(content, y, "Hide ready spells (only show cooldowns)",
        function() return db.hideReady end,
        function(checked)
            db.hideReady = checked
            if ns.refreshDisplay then ns.refreshDisplay() end
        end
    )
    widgets[#widgets + 1] = w

    w, y = ZaeUI_Shared.createCheckbox(content, y, "Lock tracker window position",
        function() return db.lockFrame end,
        function(checked)
            db.lockFrame = checked
        end
    )
    widgets[#widgets + 1] = w

    -- Category filters
    y = y - 12
    local catHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    catHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
    catHeader:SetText("Category Filters")
    y = y - 22

    w, y = ZaeUI_Shared.createCheckbox(content, y, "Show Interrupts",
        function() return db.showInterrupts end,
        function(checked)
            db.showInterrupts = checked
            if ns.refreshDisplay then ns.refreshDisplay() end
        end
    )
    widgets[#widgets + 1] = w

    w, y = ZaeUI_Shared.createCheckbox(content, y, "Show Stuns",
        function() return db.showStuns end,
        function(checked)
            db.showStuns = checked
            if ns.refreshDisplay then ns.refreshDisplay() end
        end
    )
    widgets[#widgets + 1] = w

    w, y = ZaeUI_Shared.createCheckbox(content, y, "Show Others (knockbacks, disorients...)",
        function() return db.showOthers end,
        function(checked)
            db.showOthers = checked
            if ns.refreshDisplay then ns.refreshDisplay() end
        end
    )
    widgets[#widgets + 1] = w

    -- Kick Markers section
    y = y - 12
    local markerHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    markerHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
    markerHeader:SetText("Kick Markers")
    y = y - 22

    w, y = ZaeUI_Shared.createCheckbox(content, y, "Show markers in a separate window",
        function() return db.separateMarkerWindow end,
        function(checked)
            db.separateMarkerWindow = checked
            if ns.refreshDisplay then ns.refreshDisplay() end
            if ns.refreshMarkerDisplay then ns.refreshMarkerDisplay() end
        end
    )
    widgets[#widgets + 1] = w

    -- Common
    y = y - 12
    local commonHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    commonHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
    commonHeader:SetText("Common")
    y = y - 22

    w, y = ZaeUI_Shared.createSlider(content, y, "Window opacity", 10, 100, 5,
        function() return db.frameOpacity or 80 end,
        function(value)
            db.frameOpacity = value
            if ns.applyFrameOpacity then ns.applyFrameOpacity() end
        end,
        "%d%%"
    )
    widgets[#widgets + 1] = w

    w, y = ZaeUI_Shared.createSlider(content, y, "Bar width", 150, 400, 10,
        function() return db.barWidth or 220 end,
        function(value)
            db.barWidth = value
            if ns.refreshDisplay then ns.refreshDisplay() end
        end,
        "%dpx"
    )
    widgets[#widgets + 1] = w

    -- Hint text
    y = y - 12
    local hint = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
    hint:SetText("All group members need the addon for cooldown tracking.\nUse /zint assign to open kick marker assignments.")

    -- Set content height for scroll range
    content:SetHeight(-y + 40)

    -- Expose refresh function for /zint reset
    ns.refreshWidgets = function()
        for i = 1, #widgets do
            if widgets[i].refresh then
                widgets[i].refresh()
            end
        end
    end

    -- Register subcategory under ZaeUI
    local subCategory = Settings.RegisterCanvasLayoutSubcategory(parentCategory, panel, "Interrupts")

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

    if not ZaeUI_Shared then return end
    local parentCategory = ZaeUI_Shared.ensureParentCategory()

    -- Delay one frame to ensure ns.db is populated
    C_Timer.After(0, function()
        if ns.db then
            createOptionsPanel(parentCategory)
        else
            print("|cff00ccff[ZaeUI_Interrupts]|r Options panel failed to load: database not initialized.")
        end
    end)
end)

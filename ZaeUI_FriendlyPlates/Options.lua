-- ZaeUI_FriendlyPlates Options panel
-- Registers a settings panel under AddOns > ZaeUI > FriendlyPlates

local _, ns = ...

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

    enableCB, y = ZaeUI_Shared.createCheckbox(content, y, "Enable Friendly Nameplates",
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

    showOnlyNameCB, y = ZaeUI_Shared.createCheckbox(content, y, "Show Only Name",
        function() return db.showOnlyName end,
        function(checked)
            db.showOnlyName = checked
            ns.applyCVars()
        end
    )
    showOnlyNameCB:SetEnabled(db.enabled)
    widgets[#widgets + 1] = showOnlyNameCB

    classColorCB, y = ZaeUI_Shared.createCheckbox(content, y, "Class Color Names",
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

    customFontCB, y = ZaeUI_Shared.createCheckbox(content, y, "Custom Font Size",
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

    fontSizeSlider, y = ZaeUI_Shared.createSlider(content, y, "Font Size",
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

    local w
    w, y = ZaeUI_Shared.createCheckbox(content, y, "Show load message in chat",
        function() return db.showLoadMessage end,
        function(checked)
            db.showLoadMessage = checked
        end
    )
    widgets[#widgets + 1] = w

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
    if not ZaeUI_Shared then return end

    local parentCategory = ZaeUI_Shared.ensureParentCategory()

    C_Timer.After(0, function()
        if ns.db then
            createOptionsPanel(parentCategory)
        else
            print("|cff00ccff[ZaeUI_FriendlyPlates]|r Options panel failed to load: database not initialized.")
        end
    end)
end)

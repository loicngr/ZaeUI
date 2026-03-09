-- ZaeUI_Interrupts Options panel
-- Registers a settings panel under AddOns > ZaeUI > Interrupts

local _, ns = ...

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
    return cb, y - 30
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

    -- Hint text
    y = y - 12
    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, y)
    hint:SetText("All group members need the addon for cooldown tracking.")

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

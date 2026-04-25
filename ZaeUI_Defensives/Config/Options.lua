-- ZaeUI_Defensives/Config/Options.lua
-- Settings panel for v3. Uses ZaeUI_Shared widget helpers for consistency
-- with the other ZaeUI addons.
-- luacheck: no self

local _, ns = ...
ns.Config = ns.Config or {}

local O = {}

StaticPopupDialogs = StaticPopupDialogs or {}
StaticPopupDialogs["ZAEUI_DEFENSIVES_RESET_CONFIRM"] = {
    text = "This will reset all ZaeUI_Defensives settings to defaults and reload the UI. Continue?",
    button1 = ACCEPT or "Accept",
    button2 = CANCEL or "Cancel",
    OnAccept = function()
        if ns.ResetAll then ns.ResetAll() end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function db() return ZaeUI_DefensivesDB end

local function buildPanel()
    local panel = CreateFrame("Frame")
    panel.name = "Defensives"

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
    local floatingWidgets = {}
    local anchoredWidgets = {}
    local y = -16

    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, y)
    title:SetText("ZaeUI Defensives")
    y = y - 32

    -- ---- General ----
    local hdr1 = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    hdr1:SetPoint("TOPLEFT", 16, y); hdr1:SetText("General"); y = y - 22

    local w
    w, y = ZaeUI_Shared.createCheckbox(content, y, "Enable tracker",
        function() return db().trackerEnabled end,
        function(checked)
            db().trackerEnabled = checked
            if ns.routeRefreshDisplay then ns.routeRefreshDisplay() end
        end)
    widgets[#widgets + 1] = w

    w, y = ZaeUI_Shared.createCheckbox(content, y, "Hide when solo",
        function() return db().trackerHideWhenSolo end,
        function(checked)
            db().trackerHideWhenSolo = checked
            if ns.routeRefreshDisplay then ns.routeRefreshDisplay() end
        end)
    widgets[#widgets + 1] = w

    w, y = ZaeUI_Shared.createCheckbox(content, y, "Enable in raids (>5 players)",
        function() return db().enabledInRaid end,
        function(checked)
            db().enabledInRaid = checked
            if ns.routeRefreshDisplay then ns.routeRefreshDisplay() end
        end)
    widgets[#widgets + 1] = w

    w, y = ZaeUI_Shared.createCheckbox(content, y, "Enable in Mythic+ keystones",
        function() return db().enabledInMythicPlus end,
        function(checked)
            db().enabledInMythicPlus = checked
            if ns.routeRefreshDisplay then ns.routeRefreshDisplay() end
        end)
    widgets[#widgets + 1] = w

    w, y = ZaeUI_Shared.createCheckbox(content, y, "Show load message",
        function() return db().showLoadMessage end,
        function(checked) db().showLoadMessage = checked end)
    widgets[#widgets + 1] = w

    y = y - 4
    local btnTestParty = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    btnTestParty:SetText("Test Mode (Party)")
    btnTestParty:SetSize(160, 22)
    btnTestParty:SetPoint("TOPLEFT", 16, y)
    btnTestParty:SetScript("OnClick", function()
        if ns.Modules and ns.Modules.TestMode then
            ns.Modules.TestMode:Start(false, false)
        end
    end)
    y = y - 28

    local btnTestRaid = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    btnTestRaid:SetText("Test Mode (Raid)")
    btnTestRaid:SetSize(160, 22)
    btnTestRaid:SetPoint("TOPLEFT", 16, y)
    btnTestRaid:SetScript("OnClick", function()
        if ns.Modules and ns.Modules.TestMode then
            ns.Modules.TestMode:StartRaid(false)
        end
    end)
    y = y - 36

    -- ---- Display Mode ----
    local hdr2 = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    hdr2:SetPoint("TOPLEFT", 16, y); hdr2:SetText("Display Mode"); y = y - 22

    w, y = ZaeUI_Shared.createDropdown(content, y, "Display mode",
        {
            { value = "floating",  text = "Floating window" },
            { value = "anchored",  text = "Anchored to unit frames" },
        },
        function() return db().displayMode or "floating" end,
        function(value)
            db().displayMode = value
            if ns.routeRefreshDisplay then ns.routeRefreshDisplay() end
            if ns.refreshWidgets then ns.refreshWidgets() end
        end)
    widgets[#widgets + 1] = w

    y = y - 4

    -- ---- Floating settings ----
    local floatingHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    floatingHeader:SetPoint("TOPLEFT", 16, y); floatingHeader:SetText("Floating Display"); y = y - 22

    w, y = ZaeUI_Shared.createCheckbox(content, y, "Lock window position",
        function() return db().trackerLocked end,
        function(checked) db().trackerLocked = checked end)
    floatingWidgets[#floatingWidgets + 1] = w
    widgets[#widgets + 1] = w

    w, y = ZaeUI_Shared.createSlider(content, y, "Window opacity", 30, 100, 5,
        function() return db().trackerOpacity or 80 end,
        function(value)
            db().trackerOpacity = value
            if ns.routeRefreshDisplay then ns.routeRefreshDisplay() end
        end,
        "%d%%")
    floatingWidgets[#floatingWidgets + 1] = w
    widgets[#widgets + 1] = w

    y = y - 8

    -- ---- Anchored settings ----
    local anchoredHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    anchoredHeader:SetPoint("TOPLEFT", 16, y); anchoredHeader:SetText("Anchored Display"); y = y - 22

    w, y = ZaeUI_Shared.createSlider(content, y, "Icon size", 16, 48, 1,
        function() return db().anchoredIconSize or 28 end,
        function(value)
            db().anchoredIconSize = value
            if ns.routeRefreshDisplay then ns.routeRefreshDisplay() end
        end,
        "%dpx")
    anchoredWidgets[#anchoredWidgets + 1] = w
    widgets[#widgets + 1] = w

    w, y = ZaeUI_Shared.createSlider(content, y, "Spacing", 0, 10, 1,
        function() return db().anchoredSpacing or 3 end,
        function(value)
            db().anchoredSpacing = value
            if ns.routeRefreshDisplay then ns.routeRefreshDisplay() end
        end,
        "%dpx")
    anchoredWidgets[#anchoredWidgets + 1] = w
    widgets[#widgets + 1] = w

    w, y = ZaeUI_Shared.createSlider(content, y, "Icons per row", 1, 8, 1,
        function() return db().anchoredIconsPerRow or 2 end,
        function(value)
            db().anchoredIconsPerRow = value
            if ns.routeRefreshDisplay then ns.routeRefreshDisplay() end
        end)
    anchoredWidgets[#anchoredWidgets + 1] = w
    widgets[#widgets + 1] = w

    w, y = ZaeUI_Shared.createDropdown(content, y, "Anchor side",
        {
            { value = "BOTTOM", text = "Bottom" },
            { value = "TOP",    text = "Top" },
            { value = "LEFT",   text = "Left" },
            { value = "RIGHT",  text = "Right" },
        },
        function() return db().anchoredSide or "RIGHT" end,
        function(value)
            db().anchoredSide = value
            if ns.routeRefreshDisplay then ns.routeRefreshDisplay() end
        end)
    anchoredWidgets[#anchoredWidgets + 1] = w
    widgets[#widgets + 1] = w

    w, y = ZaeUI_Shared.createSlider(content, y, "Offset X", -50, 50, 1,
        function() return db().anchoredOffsetX or 2 end,
        function(value)
            db().anchoredOffsetX = value
            if ns.routeRefreshDisplay then ns.routeRefreshDisplay() end
        end)
    anchoredWidgets[#anchoredWidgets + 1] = w
    widgets[#widgets + 1] = w

    w, y = ZaeUI_Shared.createSlider(content, y, "Offset Y", -50, 50, 1,
        function() return db().anchoredOffsetY or 30 end,
        function(value)
            db().anchoredOffsetY = value
            if ns.routeRefreshDisplay then ns.routeRefreshDisplay() end
        end)
    anchoredWidgets[#anchoredWidgets + 1] = w
    widgets[#widgets + 1] = w

    w, y = ZaeUI_Shared.createCheckbox(content, y, "Show own cooldowns",
        function() return db().anchoredShowPlayer end,
        function(checked)
            db().anchoredShowPlayer = checked
            if ns.routeRefreshDisplay then ns.routeRefreshDisplay() end
        end)
    anchoredWidgets[#anchoredWidgets + 1] = w
    widgets[#widgets + 1] = w

    y = y - 8

    -- ---- Filters — Categories ----
    local hdr3 = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    hdr3:SetPoint("TOPLEFT", 16, y); hdr3:SetText("Filters — Categories"); y = y - 22

    w, y = ZaeUI_Shared.createCheckbox(content, y, "Show externals",
        function() return db().trackerShowExternal end,
        function(checked)
            db().trackerShowExternal = checked
            if ns.routeRefreshDisplay then ns.routeRefreshDisplay() end
        end)
    widgets[#widgets + 1] = w

    w, y = ZaeUI_Shared.createCheckbox(content, y, "Show personals",
        function() return db().trackerShowPersonal end,
        function(checked)
            db().trackerShowPersonal = checked
            if ns.routeRefreshDisplay then ns.routeRefreshDisplay() end
        end)
    widgets[#widgets + 1] = w

    w, y = ZaeUI_Shared.createCheckbox(content, y, "Show raidwide",
        function() return db().trackerShowRaidwide end,
        function(checked)
            db().trackerShowRaidwide = checked
            if ns.routeRefreshDisplay then ns.routeRefreshDisplay() end
        end)
    widgets[#widgets + 1] = w

    w, y = ZaeUI_Shared.createCheckbox(content, y, "Hide externals cast by yourself",
        function() return db().trackerHideOwnExternals end,
        function(checked)
            db().trackerHideOwnExternals = checked
            if ns.routeRefreshDisplay then ns.routeRefreshDisplay() end
        end)
    widgets[#widgets + 1] = w

    y = y - 8

    -- ---- Filters — Roles ----
    local hdr4 = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    hdr4:SetPoint("TOPLEFT", 16, y); hdr4:SetText("Filters — Roles"); y = y - 22

    w, y = ZaeUI_Shared.createCheckbox(content, y, "Show tank cooldowns",
        function() return db().trackerShowTankCooldowns end,
        function(checked)
            db().trackerShowTankCooldowns = checked
            if ns.routeRefreshDisplay then ns.routeRefreshDisplay() end
        end)
    widgets[#widgets + 1] = w

    w, y = ZaeUI_Shared.createCheckbox(content, y, "Show healer cooldowns",
        function() return db().trackerShowHealerCooldowns end,
        function(checked)
            db().trackerShowHealerCooldowns = checked
            if ns.routeRefreshDisplay then ns.routeRefreshDisplay() end
        end)
    widgets[#widgets + 1] = w

    w, y = ZaeUI_Shared.createCheckbox(content, y, "Show DPS cooldowns",
        function() return db().trackerShowDpsCooldowns end,
        function(checked)
            db().trackerShowDpsCooldowns = checked
            if ns.routeRefreshDisplay then ns.routeRefreshDisplay() end
        end)
    widgets[#widgets + 1] = w

    y = y - 12

    -- ---- Reset ----
    local hdr5 = content:CreateFontString(nil, "ARTWORK", "GameFontRed")
    hdr5:SetPoint("TOPLEFT", 16, y); hdr5:SetText("Danger zone"); y = y - 24

    local btnReset = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    btnReset:SetText("Reset all settings")
    btnReset:SetSize(160, 22)
    btnReset:SetPoint("TOPLEFT", 16, y)
    btnReset:SetScript("OnClick", function()
        if StaticPopup_Show then StaticPopup_Show("ZAEUI_DEFENSIVES_RESET_CONFIRM") end
    end)
    y = y - 32

    content:SetHeight(math.abs(y) + 16)

    -- ---- Mode visibility toggling ----

    local function updateModeVisibility()
        local isFloating = (db().displayMode or "floating") ~= "anchored"
        floatingHeader:SetShown(isFloating)
        for _, fw in ipairs(floatingWidgets) do
            if isFloating then fw:Show() else fw:Hide() end
        end
        anchoredHeader:SetShown(not isFloating)
        for _, aw in ipairs(anchoredWidgets) do
            if not isFloating then aw:Show() else aw:Hide() end
        end
    end

    ns.refreshWidgets = function()
        for _, widget in ipairs(widgets) do
            if widget.refresh then widget.refresh() end
        end
        updateModeVisibility()
    end

    panel:SetScript("OnShow", function()
        if ns.refreshWidgets then ns.refreshWidgets() end
    end)

    updateModeVisibility()
    return panel
end

function O:Init()
    if not Settings or not Settings.RegisterCanvasLayoutSubcategory then
        return
    end
    if not (ZaeUI_Shared and ZaeUI_Shared.ensureParentCategory) then return end
    local parentCategory = ZaeUI_Shared.ensureParentCategory()
    if not parentCategory then return end
    local panel = buildPanel()
    ns.settingsCategory = Settings.RegisterCanvasLayoutSubcategory(parentCategory, panel, "Defensives")
    Settings.RegisterAddOnCategory(ns.settingsCategory)
end

ns.Config.Options = O
return O

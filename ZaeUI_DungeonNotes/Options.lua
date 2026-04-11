-- ZaeUI_DungeonNotes Options panel
-- Registers a settings panel under AddOns > ZaeUI > DungeonNotes

local _, ns = ...

local CreateFrame = CreateFrame
local C_Timer = C_Timer

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

    -- Section: Notifications --------------------------------------------------

    local notifHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    notifHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
    notifHeader:SetText("Notifications")
    y = y - 28

    local w

    w, y = ZaeUI_Shared.createCheckbox(content, y, "Show notification on instance entry",
        function() return db.showNotification end,
        function(checked) db.showNotification = checked end
    )
    widgets[#widgets + 1] = w

    w, y = ZaeUI_Shared.createCheckbox(content, y, "Notify even when no note exists for this instance",
        function() return db.notifyEmptyInstances end,
        function(checked) db.notifyEmptyInstances = checked end
    )
    widgets[#widgets + 1] = w

    w, y = ZaeUI_Shared.createSlider(content, y, "Notification duration", 5, 60, 1,
        function() return db.notificationDuration end,
        function(value) db.notificationDuration = value end,
        "%ds"
    )
    widgets[#widgets + 1] = w

    -- Section: Instance types -------------------------------------------------

    y = y - 12
    local typesHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    typesHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
    typesHeader:SetText("Instance Types")
    y = y - 22

    w, y = ZaeUI_Shared.createCheckbox(content, y, "Enable for 5-man dungeons (including Mythic+)",
        function() return db.enableParty end,
        function(checked) db.enableParty = checked end
    )
    widgets[#widgets + 1] = w

    w, y = ZaeUI_Shared.createCheckbox(content, y, "Enable for raids",
        function() return db.enableRaids end,
        function(checked) db.enableRaids = checked end
    )
    widgets[#widgets + 1] = w

    -- Section: General --------------------------------------------------------

    y = y - 12
    local generalHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    generalHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
    generalHeader:SetText("General")
    y = y - 22

    w, y = ZaeUI_Shared.createCheckbox(content, y, "Show load message in chat",
        function() return db.showLoadMessage end,
        function(checked) db.showLoadMessage = checked end
    )
    widgets[#widgets + 1] = w

    -- Section: Notes ---------------------------------------------------------

    y = y - 12
    local notesHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    notesHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
    notesHeader:SetText("Notes")
    y = y - 22

    local browseHint = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    browseHint:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
    browseHint:SetWidth(540)
    browseHint:SetJustifyH("LEFT")
    browseHint:SetText("Open notes for any dungeon or raid you have visited, without entering the instance.")
    y = y - 22

    local browseBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    browseBtn:SetSize(200, 22)
    browseBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
    browseBtn:SetText("Browse all dungeons...")
    browseBtn:SetScript("OnClick", function()
        if ns.showBrowseDialog then ns.showBrowseDialog() end
    end)

    y = y - 30

    -- Section: Profile --------------------------------------------------------

    y = y - 12
    local profileHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    profileHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
    profileHeader:SetText("Profile")
    y = y - 22

    local profileHint = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    profileHint:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
    profileHint:SetWidth(540)
    profileHint:SetJustifyH("LEFT")
    profileHint:SetText("Export your notes as a shareable string, or import one. Notes are stored per character.")
    y = y - 22

    local exportBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    exportBtn:SetSize(150, 22)
    exportBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
    exportBtn:SetText("Export profile")
    exportBtn:SetScript("OnClick", function()
        if ns.showExportDialog then ns.showExportDialog() end
    end)

    local importBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    importBtn:SetSize(150, 22)
    importBtn:SetPoint("LEFT", exportBtn, "RIGHT", 8, 0)
    importBtn:SetText("Import profile")
    importBtn:SetScript("OnClick", function()
        if ns.showImportDialog then ns.showImportDialog() end
    end)

    y = y - 30

    local resetBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    resetBtn:SetSize(160, 22)
    resetBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
    resetBtn:SetText("Delete all notes")
    resetBtn:SetScript("OnClick", function()
        StaticPopup_Show("ZAEUI_DUNGEONNOTES_CONFIRM_RESET")
    end)

    y = y - 30

    -- Hint
    y = y - 8
    local footer = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    footer:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
    footer:SetText("Notes are stored per character in SavedVariables. No data is sent over the network.")

    content:SetHeight(-y + 40)

    ns.refreshWidgets = function()
        for i = 1, #widgets do
            if widgets[i].refresh then
                widgets[i].refresh()
            end
        end
    end

    local subCategory = Settings.RegisterCanvasLayoutSubcategory(parentCategory, panel, "DungeonNotes")
    ns.settingsCategory = subCategory
end

-- Wait for the main addon to finish loading before creating the panel.
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, addonName)
    if addonName ~= "ZaeUI_DungeonNotes" then return end
    self:UnregisterEvent("ADDON_LOADED")
    if not ZaeUI_Shared then return end

    local parentCategory = ZaeUI_Shared.ensureParentCategory()

    C_Timer.After(0, function()
        if ns.db then
            createOptionsPanel(parentCategory)
        else
            print("|cff00ccff[ZaeUI_DungeonNotes]|r Options panel failed to load: database not initialized.")
        end
    end)
end)

-- ZaeUI_Shared: Common utilities for all ZaeUI addons
-- Provides shared UI widgets, backdrop styling and helper functions

local CreateFrame = CreateFrame
local math_floor = math.floor
local string_format = string.format
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid

-- Shared backdrop definition
local SHARED_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

ZaeUI_Shared = {}

--- Check if the player is in any type of group.
--- Covers manual groups (LE_PARTY_CATEGORY_HOME) and LFG/instance groups
--- (LE_PARTY_CATEGORY_INSTANCE) so the addon works in all scenarios.
--- @return boolean
function ZaeUI_Shared.isInAnyGroup()
    return not not (IsInGroup() or IsInGroup(LE_PARTY_CATEGORY_INSTANCE) or IsInRaid())
end

--- Apply standard backdrop styling to a frame (without opacity).
--- Callers should set alpha separately since each addon uses a different db key.
--- @param frame table The frame (must inherit BackdropTemplate)
function ZaeUI_Shared.applyBackdrop(frame)
    frame:SetBackdrop(SHARED_BACKDROP)
    frame:SetBackdropColor(0, 0, 0, 0.8)
    frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
end

--- Ensure the shared ZaeUI parent settings category exists.
--- Must be called synchronously (not in a timer) to avoid race conditions.
--- @return table parentCategory The shared parent category
function ZaeUI_Shared.ensureParentCategory()
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

--- Create a checkbox control.
--- @param parent table Parent frame
--- @param y number Y offset from TOPLEFT
--- @param label string Checkbox label
--- @param get function Returns current boolean value
--- @param set function Called with new boolean value
--- @return table checkbox The created checkbox
--- @return number nextY The Y offset for the next widget
function ZaeUI_Shared.createCheckbox(parent, y, label, get, set)
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

--- Create a slider control with value display.
--- @param parent table Parent frame
--- @param y number Y offset from TOPLEFT
--- @param label string Slider label
--- @param minVal number Minimum value
--- @param maxVal number Maximum value
--- @param step number Step increment
--- @param get function Returns current value
--- @param set function Called with new value
--- @param fmt string|nil Format string for display (e.g. "%d%%"), defaults to tostring
--- @return table slider The created slider
--- @return number nextY The Y offset for the next widget
function ZaeUI_Shared.createSlider(parent, y, label, minVal, maxVal, step, get, set, fmt)
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

    if fmt then
        valueText:SetText(string_format(fmt, get()))
    else
        valueText:SetText(tostring(get()))
    end

    slider:SetScript("OnValueChanged", function(_, value)
        value = math_floor(value / step + 0.5) * step
        if fmt then
            valueText:SetText(string_format(fmt, value))
        else
            valueText:SetText(tostring(value))
        end
        set(value)
    end)
    slider.refresh = function()
        slider:SetValue(get())
        if fmt then
            valueText:SetText(string_format(fmt, get()))
        else
            valueText:SetText(tostring(get()))
        end
    end

    --- Set enabled/disabled state for the slider and its label.
    local origSetEnabled = slider.SetEnabled
    slider.SetEnabled = function(self, enabled)
        origSetEnabled(self, enabled)
        if enabled then
            sliderLabel:SetFontObject("GameFontHighlight")
        else
            sliderLabel:SetFontObject("GameFontDisable")
        end
    end

    return slider, y - 24
end

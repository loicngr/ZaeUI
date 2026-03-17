-- ZaeUI_Nameplates Options panel
-- Registers a settings panel under AddOns > ZaeUI > Nameplates

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

--- Create a color swatch button that opens ColorPickerFrame.
--- @param parent table Parent frame
--- @param y number Y offset from TOPLEFT
--- @param label string Button label
--- @param getColor function Returns r, g, b, a
--- @param setColor function Called with r, g, b, a
--- @return table swatch The created swatch frame
--- @return number nextY The Y offset for the next widget
local function createColorPicker(parent, y, label, getColor, setColor)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(200, 26)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, y)

    local swatch = CreateFrame("Button", nil, container)
    swatch:SetSize(20, 20)
    swatch:SetPoint("LEFT", 0, 0)

    local swatchBg = swatch:CreateTexture(nil, "BACKGROUND")
    swatchBg:SetAllPoints()
    swatchBg:SetColorTexture(0, 0, 0, 1)

    local swatchColor = swatch:CreateTexture(nil, "OVERLAY")
    swatchColor:SetPoint("TOPLEFT", 1, -1)
    swatchColor:SetPoint("BOTTOMRIGHT", -1, 1)
    local r, g, b, a = getColor()
    swatchColor:SetColorTexture(r, g, b, a)

    local text = container:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
    text:SetText(label)

    swatch:SetScript("OnClick", function()
        local cr, cg, cb, ca = getColor()
        ColorPickerFrame:SetupColorPickerAndShow({
            r = cr,
            g = cg,
            b = cb,
            opacity = ca,
            hasOpacity = true,
            swatchFunc = function()
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                local na = ColorPickerFrame:GetColorAlpha()
                setColor(nr, ng, nb, na)
                swatchColor:SetColorTexture(nr, ng, nb, na)
            end,
            opacityFunc = function()
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                local na = ColorPickerFrame:GetColorAlpha()
                setColor(nr, ng, nb, na)
                swatchColor:SetColorTexture(nr, ng, nb, na)
            end,
            cancelFunc = function(prev)
                setColor(prev.r, prev.g, prev.b, prev.opacity)
                swatchColor:SetColorTexture(prev.r, prev.g, prev.b, prev.opacity)
            end,
        })
    end)

    swatch.refresh = function()
        local sr, sg, sb, sa = getColor()
        swatchColor:SetColorTexture(sr, sg, sb, sa)
    end

    return swatch, y - 32
end

-- Panel creation ----------------------------------------------------------------

local function createOptionsPanel(parentCategory)
    local db = ns.db
    local C = ns.constants

    -- Sub panel: Nameplates
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

    -- Scale & Overlap section
    _, y = createHeader(content, y, "Scale & Overlap")

    local w
    w, y = ZaeUI_Shared.createSlider(content, y, "Target Scale", C.MIN_SCALE, C.MAX_SCALE, 0.1,
        function() return db.scale end,
        function(v) db.scale = v; ns.applyScale(v) end
    )
    widgets[#widgets + 1] = w

    local autoOverlapCB
    local overlapSlider

    autoOverlapCB, y = ZaeUI_Shared.createCheckbox(content, y, "Auto Overlap",
        function() return db.overlapV == nil end,
        function(checked)
            if checked then
                db.overlapV = nil
                ns.applyOverlap(db.scale)
            else
                db.overlapV = tonumber(GetCVar("nameplateOverlapV")) or 1.1
            end
            if overlapSlider then
                overlapSlider:SetEnabled(not checked)
                if not checked and overlapSlider.refresh then
                    overlapSlider.refresh()
                end
            end
        end
    )
    widgets[#widgets + 1] = autoOverlapCB

    overlapSlider, y = ZaeUI_Shared.createSlider(content, y, "Overlap Value", C.MIN_OVERLAP, C.MAX_OVERLAP, 0.1,
        function() return db.overlapV or tonumber(GetCVar("nameplateOverlapV")) or 1.1 end,
        function(v)
            db.overlapV = v
            ns.applyOverlap(db.scale)
            if autoOverlapCB then
                autoOverlapCB:SetChecked(false)
            end
        end
    )
    overlapSlider:SetEnabled(db.overlapV ~= nil)
    widgets[#widgets + 1] = overlapSlider

    -- Highlight section
    _, y = createHeader(content, y - 8, "Highlight (Border)")

    w, y = ZaeUI_Shared.createCheckbox(content, y, "Enable Border",
        function() return db.highlight end,
        function(checked)
            db.highlight = checked
            ns.hideHighlight()
            ns.showHighlight()
        end
    )
    widgets[#widgets + 1] = w

    w, y = ZaeUI_Shared.createSlider(content, y, "Border Thickness", C.MIN_BORDER, C.MAX_BORDER, 1,
        function() return db.borderSize end,
        function(v)
            db.borderSize = v
            ns.updateBorderSize()
            ns.hideHighlight()
            ns.showHighlight()
        end
    )
    widgets[#widgets + 1] = w

    -- Arrows section
    _, y = createHeader(content, y - 8, "Arrows")

    w, y = ZaeUI_Shared.createCheckbox(content, y, "Enable Arrows",
        function() return db.arrows end,
        function(checked)
            db.arrows = checked
            ns.hideHighlight()
            ns.showHighlight()
        end
    )
    widgets[#widgets + 1] = w

    w, y = ZaeUI_Shared.createSlider(content, y, "Arrow Size", C.MIN_ARROW_SIZE, C.MAX_ARROW_SIZE, 1,
        function() return db.arrowSize end,
        function(v)
            db.arrowSize = v
            ns.hideHighlight()
            ns.showHighlight()
        end
    )
    widgets[#widgets + 1] = w

    w, y = ZaeUI_Shared.createSlider(content, y, "Arrow Offset", C.MIN_ARROW_OFFSET, C.MAX_ARROW_OFFSET, 1,
        function() return db.arrowOffset end,
        function(v)
            db.arrowOffset = v
            ns.hideHighlight()
            ns.showHighlight()
        end
    )
    widgets[#widgets + 1] = w

    -- Color section
    _, y = createHeader(content, y - 8, "Color")

    w = createColorPicker(content, y, "Highlight Color",
        function()
            local c = db.highlightColor
            return c.r, c.g, c.b, c.a
        end,
        function(r, g, b, a)
            db.highlightColor.r = r
            db.highlightColor.g = g
            db.highlightColor.b = b
            db.highlightColor.a = a
            ns.hideHighlight()
            ns.showHighlight()
        end
    )
    widgets[#widgets + 1] = w

    -- Hint text
    y = y - 40
    local hint = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
    hint:SetText("Target a unit to preview changes in real time.")

    -- Set content height for scroll range
    content:SetHeight(-y + 16)

    -- Expose refresh function for /znp reset
    ns.refreshWidgets = function()
        for i = 1, #widgets do
            if widgets[i].refresh then
                widgets[i].refresh()
            end
        end
    end

    local subCategory = Settings.RegisterCanvasLayoutSubcategory(parentCategory, panel, "Nameplates")

    -- Expose for /znp options command
    ns.settingsCategory = subCategory
end

-- Wait for the main addon to finish loading before creating the panel.
-- ns.db is set during ADDON_LOADED in the main file.
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, addonName)
    if addonName ~= "ZaeUI_Nameplates" then
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
            print("|cff00ccff[ZaeUI_Nameplates]|r Options panel failed to load: database not initialized.")
        end
    end)
end)

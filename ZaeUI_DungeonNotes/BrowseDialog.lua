-- ZaeUI_DungeonNotes: Instance browser dialog
-- Lists every dungeon/raid the player has visited so notes can be opened
-- from anywhere, not only from inside the instance itself.

local _, ns = ...

local CreateFrame = CreateFrame
local UIParent = UIParent

local FONT_PATH = "Interface\\AddOns\\ZaeUI_Shared\\Fonts\\Roboto.ttf"
local ROW_HEIGHT = 22
local ROW_PADDING = 2

-- Reusable dialog and row pool
local dialog
local rowPool = {}

--- Create or reuse a list row under the scroll child.
--- @param index number 1-based index
--- @param parent table scroll child frame
--- @return table row
local function getRow(index, parent)
    local row = rowPool[index]
    if row then return row end

    row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 0)
    row.bg = bg

    local typeTag = row:CreateFontString(nil, "OVERLAY")
    typeTag:SetFont(FONT_PATH, 10, "")
    typeTag:SetPoint("LEFT", 8, 0)
    typeTag:SetWidth(18)
    typeTag:SetJustifyH("LEFT")
    row.typeTag = typeTag

    local name = row:CreateFontString(nil, "OVERLAY")
    name:SetFont(FONT_PATH, 11, "")
    name:SetPoint("LEFT", typeTag, "RIGHT", 4, 0)
    name:SetPoint("RIGHT", -70, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    row.name = name

    local status = row:CreateFontString(nil, "OVERLAY")
    status:SetFont(FONT_PATH, 10, "")
    status:SetPoint("RIGHT", -8, 0)
    status:SetJustifyH("RIGHT")
    row.status = status

    row:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(1, 1, 1, 0.08)
    end)
    row:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(1, 1, 1, 0)
    end)
    row:SetScript("OnClick", function(self)
        if not self._mapID or not ns.noteWindow_Open then return end
        ns.noteWindow_Open(self._mapID, self._name)
        if dialog then dialog:Hide() end
    end)

    rowPool[index] = row
    return row
end

--- Build the dialog frame lazily.
--- @return table frame
local function createDialog()
    local f = CreateFrame("Frame", "ZaeUI_DungeonNotesBrowseDialog", UIParent, "BackdropTemplate")
    f:SetSize(420, 380)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    ZaeUI_Shared.applyBackdrop(f)
    f:Hide()

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("Browse dungeon notes")
    f.title = title

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOP", title, "BOTTOM", 0, -6)
    hint:SetText("Click an instance to open its notes. D = dungeon, R = raid.")
    f.hint = hint

    local emptyText = f:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
    emptyText:SetPoint("CENTER", 0, 0)
    emptyText:SetText("No dungeons or raids visited yet.\nEnter an instance to start taking notes.")
    emptyText:SetJustifyH("CENTER")
    emptyText:Hide()
    f.emptyText = emptyText

    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -56)
    scroll:SetPoint("BOTTOMRIGHT", -34, 48)
    f.scroll = scroll

    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(1) -- width gets updated on refresh
    child:SetHeight(1)
    scroll:SetScrollChild(child)
    f.child = child

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    closeBtn:SetSize(90, 22)
    closeBtn:SetPoint("BOTTOMRIGHT", -16, 12)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    dialog = f
    return f
end

--- Refresh the list content from the current DB state.
local function refreshList()
    if not dialog then return end
    local child = dialog.child
    child:SetWidth(dialog.scroll:GetWidth())

    local list = ns.getBrowseList and ns.getBrowseList() or {}

    if #list == 0 then
        -- Hide every pooled row and show the empty-state text
        for i = 1, #rowPool do
            rowPool[i]:Hide()
        end
        child:SetHeight(1)
        dialog.emptyText:Show()
        return
    end
    dialog.emptyText:Hide()

    for i, entry in ipairs(list) do
        local row = getRow(i, child)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -((i - 1) * (ROW_HEIGHT + ROW_PADDING)))
        row:SetPoint("RIGHT", child, "RIGHT", 0, 0)

        row._mapID = entry.mapID
        row._name = entry.name

        if entry.type == "raid" then
            row.typeTag:SetText("|cffff8844R|r")
        else
            row.typeTag:SetText("|cff44aaffD|r")
        end

        row.name:SetText(entry.name)

        if entry.hasNote then
            row.status:SetText("|cff44ff44has note|r")
        else
            row.status:SetText("|cff888888empty|r")
        end

        row:Show()
    end

    -- Hide extra pooled rows
    for i = #list + 1, #rowPool do
        rowPool[i]:Hide()
    end

    child:SetHeight((#list * (ROW_HEIGHT + ROW_PADDING)) + ROW_PADDING)
end

--- Show the instance browser dialog.
function ns.showBrowseDialog()
    local f = dialog or createDialog()
    refreshList()
    f:Show()
end

--- Refresh the browser list if the dialog is currently visible.
--- Called by reset/import operations so the list stays in sync.
function ns.refreshBrowseDialog()
    if dialog and dialog:IsShown() then
        refreshList()
    end
end

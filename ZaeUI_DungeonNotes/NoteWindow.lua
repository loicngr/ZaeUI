-- ZaeUI_DungeonNotes: Note editing window
-- Draggable, resizable frame with a multi-line EditBox for per-dungeon notes.

local _, ns = ...

local CreateFrame = CreateFrame
local UIParent = UIParent

-- Window-local state
local window
local currentMapID
local currentInstanceName

-- Constants
local FONT_PATH = "Interface\\AddOns\\ZaeUI_Shared\\Fonts\\Roboto.ttf"
local MIN_WIDTH = 320
local MIN_HEIGHT = 220
local MAX_WIDTH = 900
local MAX_HEIGHT = 700

--- Persist the window position into the saved DB entry.
local function savePosition(self)
    local db = ns.db
    if not db then return end
    local point, _, relPoint, x, y = self:GetPoint()
    db.windowPoint = { point, nil, relPoint, x, y }
end

--- Persist the current window size into the saved DB entry.
local function saveSize(self)
    local db = ns.db
    if not db then return end
    db.windowWidth = math.floor(self:GetWidth() + 0.5)
    db.windowHeight = math.floor(self:GetHeight() + 0.5)
end

--- Restore the window position from the saved DB entry.
local function restorePosition(self)
    local db = ns.db
    local p = db and db.windowPoint
    if not p or not p[1] then
        self:SetPoint("CENTER")
        return
    end
    self:ClearAllPoints()
    self:SetPoint(p[1], UIParent, p[3], p[4], p[5])
end

--- Update the Save button appearance based on dirty state.
local function updateDirty(isDirty)
    if not window then return end
    if isDirty then
        window.saveBtn:Enable()
        window.title:SetText("Dungeon Notes — " .. (currentInstanceName or "") .. " *")
    else
        window.saveBtn:Disable()
        window.title:SetText("Dungeon Notes — " .. (currentInstanceName or ""))
    end
end

--- Commit the editor contents to the DB and clear the dirty flag.
local function commitSave()
    if not window or not currentMapID then return end
    local text = window.edit:GetText() or ""
    ns.setNote(currentMapID, text)
    updateDirty(false)
end

--- Build the window frame lazily on first open.
local function createWindow()
    local db = ns.db
    local width = (db and db.windowWidth) or 500
    local height = (db and db.windowHeight) or 400

    local f = CreateFrame("Frame", "ZaeUI_DungeonNotesWindow", UIParent, "BackdropTemplate")
    f:SetSize(width, height)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:SetResizable(true)
    f:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition(self)
    end)
    ZaeUI_Shared.applyBackdrop(f)
    f:Hide()

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont(FONT_PATH, 13, "")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetPoint("TOPRIGHT", -30, -12)
    title:SetJustifyH("LEFT")
    title:SetText("Dungeon Notes")
    f.title = title

    -- Close button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function()
        f:Hide()
    end)

    -- Scroll frame for the editor
    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -36)
    scroll:SetPoint("BOTTOMRIGHT", -34, 48)
    f.scroll = scroll

    -- Multi-line editor
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject("ChatFontNormal")
    edit:SetWidth(width - 60)
    edit:EnableMouse(true)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnTextChanged", function(_, userInput)
        if userInput then
            updateDirty(true)
        end
    end)
    scroll:SetScrollChild(edit)
    f.edit = edit

    -- Save button
    local saveBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    saveBtn:SetSize(90, 22)
    saveBtn:SetPoint("BOTTOMRIGHT", -14, 14)
    saveBtn:SetText("Save")
    saveBtn:SetScript("OnClick", commitSave)
    f.saveBtn = saveBtn

    -- Reset-this-note button
    local resetBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    resetBtn:SetSize(120, 22)
    resetBtn:SetPoint("BOTTOMLEFT", 14, 14)
    resetBtn:SetText("Clear this note")
    resetBtn:SetScript("OnClick", function()
        if not currentMapID then return end
        edit:SetText("")
        updateDirty(true)
    end)

    -- Resize handle (bottom-right)
    local resizeBtn = CreateFrame("Button", nil, f)
    resizeBtn:SetSize(14, 14)
    resizeBtn:SetPoint("BOTTOMRIGHT", -2, 2)
    resizeBtn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeBtn:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeBtn:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeBtn:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    resizeBtn:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        saveSize(f)
        edit:SetWidth(f:GetWidth() - 60)
    end)

    window = f
    return f
end

--- Load the note for a given mapID into the editor and update the UI state.
--- @param mapID number
--- @param instanceName string
local function loadNote(mapID, instanceName)
    if not window then return end
    currentMapID = mapID
    currentInstanceName = instanceName or "?"
    local text = ns.getNote(mapID) or ""
    -- Setting text from code fires OnTextChanged with userInput=false, so
    -- dirty state is correctly cleared by updateDirty below.
    window.edit:SetText(text)
    updateDirty(false)
end

--- Open the note window for a given instance.
--- Creates the frame on first call, otherwise reuses the existing one.
--- @param mapID number
--- @param instanceName string
function ns.noteWindow_Open(mapID, instanceName)
    if not mapID then return end
    local f = window or createWindow()
    restorePosition(f)
    loadNote(mapID, instanceName)
    f:Show()
    -- Give focus to the editor so the player can start typing immediately
    f.edit:SetFocus()
end

--- Close the note window. Does not save; call commitSave() first if needed.
function ns.noteWindow_Close()
    if window then window:Hide() end
end

--- Toggle the note window for the given instance.
--- @param mapID number
--- @param instanceName string
function ns.noteWindow_Toggle(mapID, instanceName)
    if window and window:IsShown() then
        window:Hide()
    else
        ns.noteWindow_Open(mapID, instanceName)
    end
end

--- Refresh the currently displayed note (used after external DB changes).
function ns.noteWindow_Refresh()
    if not window or not currentMapID then return end
    loadNote(currentMapID, currentInstanceName)
end

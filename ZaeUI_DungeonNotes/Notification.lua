-- ZaeUI_DungeonNotes: Instance-entry notification
-- A small floating button that fades out after a configurable duration and
-- opens the note window on click.

local _, ns = ...

local CreateFrame = CreateFrame
local C_Timer = C_Timer
local UIParent = UIParent
local UIFrameFadeIn = UIFrameFadeIn
local UIFrameFadeOut = UIFrameFadeOut

local FONT_PATH = "Interface\\AddOns\\ZaeUI_Shared\\Fonts\\Roboto.ttf"

-- Reusable frame; created on first show.
local button
local hideTimer

--- Cancel the pending auto-hide timer, if any.
local function cancelHideTimer()
    if hideTimer then
        hideTimer:Cancel()
        hideTimer = nil
    end
end

--- Build the notification button frame (lazy).
local function createButton()
    local f = CreateFrame("Button", "ZaeUI_DungeonNotesNotification", UIParent, "BackdropTemplate")
    f:SetSize(230, 36)
    f:SetPoint("TOP", UIParent, "TOP", 0, -120)
    f:SetFrameStrata("HIGH")
    f:EnableMouse(true)
    ZaeUI_Shared.applyBackdrop(f)
    f:Hide()

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("LEFT", 10, 0)
    icon:SetTexture("Interface\\AddOns\\ZaeUI_Shared\\Textures\\icon-star")
    icon:SetVertexColor(1, 0.85, 0.1)
    f.icon = icon

    local label = f:CreateFontString(nil, "OVERLAY")
    label:SetFont(FONT_PATH, 11, "")
    label:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    label:SetPoint("RIGHT", -24, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    f.label = label

    local closeBtn = CreateFrame("Button", nil, f)
    closeBtn:SetSize(14, 14)
    closeBtn:SetPoint("RIGHT", -6, 0)
    local closeTex = closeBtn:CreateTexture(nil, "ARTWORK")
    closeTex:SetAllPoints()
    closeTex:SetTexture("Interface\\Buttons\\UI-StopButton")
    closeTex:SetAlpha(0.5)
    closeBtn:SetScript("OnEnter", function() closeTex:SetAlpha(1) end)
    closeBtn:SetScript("OnLeave", function() closeTex:SetAlpha(0.5) end)
    closeBtn:SetScript("OnClick", function()
        ns.notification_Hide()
    end)

    -- Highlight effect on hover
    f:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.6, 0.85, 1, 1)
    end)
    f:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    end)

    -- Click opens the note window for the last-shown instance
    f:SetScript("OnClick", function(self)
        local mapID = self._mapID
        local name = self._instanceName
        if mapID and ns.noteWindow_Open then
            ns.noteWindow_Open(mapID, name)
        end
        ns.notification_Hide()
    end)

    button = f
    return f
end

--- Show the notification for a given instance.
--- @param mapID number
--- @param instanceName string
function ns.notification_Show(mapID, instanceName)
    if not ns.db then return end
    local f = button or createButton()
    cancelHideTimer()

    f._mapID = mapID
    f._instanceName = instanceName or "?"

    -- Label varies depending on whether a note already exists
    local prefix = ns.hasNoteFor(mapID) and "Notes available: " or "New instance: "
    f.label:SetText(prefix .. (instanceName or "?"))

    f:SetAlpha(0)
    f:Show()
    UIFrameFadeIn(f, 0.4, 0, 1)

    local duration = ns.db.notificationDuration or 15
    if duration < 1 then duration = 1 end
    hideTimer = C_Timer.NewTimer(duration, function()
        UIFrameFadeOut(f, 0.6, f:GetAlpha(), 0)
        C_Timer.After(0.7, function() f:Hide() end)
        hideTimer = nil
    end)
end

--- Hide the notification immediately, cancelling any pending auto-hide.
function ns.notification_Hide()
    cancelHideTimer()
    if button then button:Hide() end
end

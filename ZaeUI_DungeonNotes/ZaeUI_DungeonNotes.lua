-- ZaeUI_DungeonNotes: Personal notes per dungeon, shown on instance entry
-- Local-only storage (SavedVariablesPerCharacter), no cross-player sync

local _, ns = ...

-- Local API refs
local CreateFrame = CreateFrame
local C_Timer = C_Timer
local GetInstanceInfo = GetInstanceInfo
local strtrim = strtrim
local tonumber = tonumber
local type = type
local pairs = pairs
local ipairs = ipairs
local string_format = string.format
local string_gsub = string.gsub
local string_sub = string.sub
local string_find = string.find
local table_concat = table.concat
local table_sort = table.sort

-- Constants
local ADDON_NAME = "ZaeUI_DungeonNotes"
local PREFIX = "|cff00ccff[ZaeUI_DungeonNotes]|r "
local PROFILE_MAGIC = "ZAEDN1:"
local MAX_IMPORT_SIZE = 51200 -- 50 KB safety limit

-- Default settings merged into ZaeUI_DungeonNotesCharDB on first load
local DEFAULTS = {
    notes = {},
    -- Catalogue of instances the player has entered while the addon was loaded.
    -- Populated on PLAYER_ENTERING_WORLD regardless of notification settings,
    -- so the Options browser can list every dungeon/raid the player has visited.
    -- Shape: [mapID] = { name = "...", type = "party"|"raid" }
    knownInstances = {},
    showNotification = true,
    notificationDuration = 15,
    notifyEmptyInstances = false,
    showLoadMessage = true,
    enableRaids = true,
    enableParty = true,
    windowPoint = { "CENTER", nil, "CENTER", 0, 0 },
    windowWidth = 500,
    windowHeight = 400,
}

-- Local state
local db
local currentMapID
local currentInstanceName

--- Initialize the character database and merge defaults for missing keys.
local function initDB()
    if not ZaeUI_DungeonNotesCharDB then
        ZaeUI_DungeonNotesCharDB = {}
    end
    for key, value in pairs(DEFAULTS) do
        if ZaeUI_DungeonNotesCharDB[key] == nil then
            if type(value) == "table" then
                local copy = {}
                for k, v in pairs(value) do copy[k] = v end
                ZaeUI_DungeonNotesCharDB[key] = copy
            else
                ZaeUI_DungeonNotesCharDB[key] = value
            end
        end
    end
    db = ZaeUI_DungeonNotesCharDB
    ns.db = db
end

-- Profile serialization ----------------------------------------------------

--- Escape a note string for inclusion in the serialized profile.
--- Order matters: escape backslashes first so later escapes don't double-escape.
--- @param s string
--- @return string escaped
local function escapeString(s)
    s = string_gsub(s, "\\", "\\\\")
    s = string_gsub(s, '"', '\\"')
    s = string_gsub(s, "\n", "\\n")
    s = string_gsub(s, "\r", "\\r")
    return s
end

--- Unescape a raw string extracted from a serialized profile.
--- Order matters: reverse of escapeString, so \\ is handled last.
--- @param s string
--- @return string
local function unescapeString(s)
    -- Two-pass handling: replace \\ with a placeholder to avoid interaction
    -- with other escapes, then restore it at the end.
    local PLACEHOLDER = "\1"
    s = string_gsub(s, "\\\\", PLACEHOLDER)
    s = string_gsub(s, "\\n", "\n")
    s = string_gsub(s, "\\r", "\r")
    s = string_gsub(s, '\\"', '"')
    s = string_gsub(s, PLACEHOLDER, "\\")
    return s
end

--- Serialize a notes table into a shareable profile string.
--- Format: ZAEDN1:{[mapID]="escaped",[mapID]="escaped",...}
--- @param notes table<number, string>
--- @return string serialized
function ns.serializeNotes(notes)
    if type(notes) ~= "table" then return PROFILE_MAGIC .. "{}" end
    local keys = {}
    for mapID in pairs(notes) do
        if type(mapID) == "number" then
            keys[#keys + 1] = mapID
        end
    end
    table_sort(keys)
    local parts = {}
    for _, mapID in ipairs(keys) do
        local text = notes[mapID]
        if type(text) == "string" and text ~= "" then
            parts[#parts + 1] = string_format('[%d]="%s"', mapID, escapeString(text))
        end
    end
    return PROFILE_MAGIC .. "{" .. table_concat(parts, ",") .. "}"
end

--- Deserialize a profile string into a notes table.
--- Returns nil and an error message on failure. Rejects oversized or malformed input.
--- Hand-written parser (no loadstring) to prevent arbitrary code execution from
--- pasted profiles.
--- @param str string
--- @return table|nil notes
--- @return string|nil errMsg
function ns.deserializeNotes(str)
    if type(str) ~= "string" then
        return nil, "Input must be a string"
    end
    str = strtrim(str)
    if #str == 0 then
        return nil, "Empty input"
    end
    if #str > MAX_IMPORT_SIZE then
        return nil, "Input too large (> 50 KB)"
    end
    if string_sub(str, 1, #PROFILE_MAGIC) ~= PROFILE_MAGIC then
        return nil, "Invalid format (missing ZAEDN1: prefix)"
    end
    local body = string_sub(str, #PROFILE_MAGIC + 1)
    if string_sub(body, 1, 1) ~= "{" or string_sub(body, -1) ~= "}" then
        return nil, "Invalid format (missing braces)"
    end
    body = string_sub(body, 2, -2)
    local notes = {}
    local count = 0
    local pos = 1
    local bodyLen = #body
    while pos <= bodyLen do
        -- Skip whitespace and commas between entries.
        local wsEnd = string_find(body, "[^%s,]", pos)
        if not wsEnd then break end
        pos = wsEnd
        -- Match [mapID]
        local idStart, idEnd, idStr = string_find(body, "^%[(%d+)%]", pos)
        if not idStart then
            return nil, "Expected [mapID] at position " .. pos
        end
        pos = idEnd + 1
        -- Match =
        if string_sub(body, pos, pos) ~= "=" then
            return nil, "Expected '=' at position " .. pos
        end
        pos = pos + 1
        -- Match opening quote
        if string_sub(body, pos, pos) ~= '"' then
            return nil, "Expected '\"' at position " .. pos
        end
        pos = pos + 1
        -- Scan until unescaped closing quote
        local textStart = pos
        while pos <= bodyLen do
            local c = string_sub(body, pos, pos)
            if c == "\\" then
                pos = pos + 2
            elseif c == '"' then
                break
            else
                pos = pos + 1
            end
        end
        if pos > bodyLen then
            return nil, "Unterminated string"
        end
        local rawText = string_sub(body, textStart, pos - 1)
        local id = tonumber(idStr)
        if id then
            notes[id] = unescapeString(rawText)
            count = count + 1
        end
        pos = pos + 1 -- consume closing quote
    end
    if count == 0 then
        return nil, "No valid entries found"
    end
    return notes
end

-- Public helpers -----------------------------------------------------------

--- Get the current instance mapID and name as detected on last zone change.
--- @return number|nil mapID
--- @return string|nil instanceName
function ns.getCurrentInstance()
    return currentMapID, currentInstanceName
end

--- Check whether a note exists for the given mapID.
--- @param mapID number
--- @return boolean
function ns.hasNoteFor(mapID)
    if not db or not mapID then return false end
    local text = db.notes[mapID]
    return type(text) == "string" and text ~= ""
end

--- Return the note text for a mapID, or empty string.
--- @param mapID number
--- @return string
function ns.getNote(mapID)
    if not db or not mapID then return "" end
    return db.notes[mapID] or ""
end

--- Store (or clear) a note for a mapID. Empty / whitespace-only text clears it.
--- @param mapID number
--- @param text string
function ns.setNote(mapID, text)
    if not db or not mapID then return end
    if type(text) ~= "string" then return end
    local trimmed = strtrim(text)
    if trimmed == "" then
        db.notes[mapID] = nil
    else
        db.notes[mapID] = text
    end
end

--- Wipe all notes. Used by `/zdn reset` and the options Reset button.
function ns.clearAllNotes()
    if not db then return end
    for k in pairs(db.notes) do db.notes[k] = nil end
end

--- Remember an instance the player has visited so the Options browser can
--- list it later. Only party and raid instances are tracked. Overwrites
--- existing entries so the name stays up to date if Blizzard renames a zone.
--- @param mapID number
--- @param name string
--- @param instanceType string
local function rememberInstance(mapID, name, instanceType)
    if not db or type(mapID) ~= "number" then return end
    if instanceType ~= "party" and instanceType ~= "raid" then return end
    db.knownInstances = db.knownInstances or {}
    db.knownInstances[mapID] = {
        name = name or "Unknown",
        type = instanceType,
    }
end

--- Return a sorted array of instance entries for the Options browser.
--- Merges `db.knownInstances` with any mapID that has a note (so orphan
--- notes from an imported profile still appear). Sorted by type then name.
--- @return table list Array of { mapID, name, type, hasNote }
function ns.getBrowseList()
    local list = {}
    if not db then return list end
    local seen = {}
    if db.knownInstances then
        for mapID, info in pairs(db.knownInstances) do
            if type(mapID) == "number" and type(info) == "table" then
                seen[mapID] = true
                list[#list + 1] = {
                    mapID = mapID,
                    name = info.name or "Unknown",
                    type = info.type or "party",
                    hasNote = ns.hasNoteFor(mapID),
                }
            end
        end
    end
    -- Surface any note whose mapID is not in knownInstances (imported profile
    -- or pre-existing notes from before knownInstances was introduced).
    if db.notes then
        for mapID in pairs(db.notes) do
            if type(mapID) == "number" and not seen[mapID] then
                list[#list + 1] = {
                    mapID = mapID,
                    name = "Map " .. mapID,
                    type = "party",
                    hasNote = true,
                }
            end
        end
    end
    -- party dungeons first, then raids, then alphabetical within each group
    table_sort(list, function(a, b)
        if a.type ~= b.type then
            return a.type == "party"
        end
        return a.name < b.name
    end)
    return list
end

-- Main frame and event handling --------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")

local events = {}

function events.ADDON_LOADED(_, addonName)
    if addonName ~= ADDON_NAME then return end
    if not ZaeUI_Shared then
        local msg = "ZaeUI_Shared is required. Install it from CurseForge."
        print(PREFIX .. "Error: " .. msg .. " Addon disabled.")
        return
    end
    initDB()

    -- Expose a quick action in the shared minimap button right-click menu.
    if ZaeUI_Shared.registerMenuAction then
        ZaeUI_Shared.registerMenuAction("Open Dungeon Notes", function()
            if ns.showBrowseDialog then ns.showBrowseDialog() end
        end, 100)
    end

    frame:UnregisterEvent("ADDON_LOADED")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")

    if db.showLoadMessage then
        print(PREFIX .. "Loaded. Type /zdn help for commands.")
    end
end

function events.PLAYER_ENTERING_WORLD()
    local name, instanceType, _, _, _, _, _, mapID = GetInstanceInfo()
    if type(mapID) ~= "number" then
        currentMapID = nil
        currentInstanceName = nil
        return
    end
    currentMapID = mapID
    currentInstanceName = name
    -- Always catalogue party/raid visits so the Options browser can list them,
    -- independently of notification preferences.
    rememberInstance(mapID, name, instanceType)
    -- Filter by instance type and user preferences
    local allowed = (instanceType == "party" and db.enableParty)
                 or (instanceType == "raid" and db.enableRaids)
    if not allowed then return end
    if not db.showNotification then return end
    if not ns.hasNoteFor(mapID) and not db.notifyEmptyInstances then return end
    -- Small delay so the UI settles after zone change before showing the button
    C_Timer.After(1, function()
        if ns.notification_Show then
            ns.notification_Show(mapID, name)
        end
    end)
end

frame:SetScript("OnEvent", function(_, event, ...)
    if events[event] then
        events[event](frame, ...)
    end
end)

-- Export / Import dialog ---------------------------------------------------

local ioDialog

--- Create (or retrieve) the import/export dialog frame.
--- A single frame is reused for both flows; the title and button label change.
local function ensureIODialog()
    if ioDialog then return ioDialog end
    local f = CreateFrame("Frame", "ZaeUI_DungeonNotesIODialog", UIParent, "BackdropTemplate")
    f:SetSize(500, 320)
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
    f.title = title

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOP", title, "BOTTOM", 0, -6)
    f.hint = hint

    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -56)
    scroll:SetPoint("BOTTOMRIGHT", -36, 48)
    f.scroll = scroll

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(true)
    edit:SetFontObject("ChatFontNormal")
    edit:SetWidth(440)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scroll:SetScrollChild(edit)
    f.edit = edit

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    closeBtn:SetSize(90, 22)
    closeBtn:SetPoint("BOTTOMRIGHT", -16, 12)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local actionBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    actionBtn:SetSize(110, 22)
    actionBtn:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
    f.actionBtn = actionBtn

    ioDialog = f
    return f
end

--- Show the export dialog pre-filled with the serialized profile string.
local function showExportDialog()
    local f = ensureIODialog()
    f.title:SetText("Export profile")
    f.hint:SetText("Select all (Ctrl+A) and copy (Ctrl+C) to share this profile.")
    local payload = ns.serializeNotes(db.notes)
    f.edit:SetText(payload)
    f.edit:HighlightText()
    f.actionBtn:SetText("Copy shown")
    f.actionBtn:SetScript("OnClick", function()
        f.edit:SetFocus()
        f.edit:HighlightText()
    end)
    f:Show()
end

--- Show the import dialog with an empty editor and an Import action button.
local function showImportDialog()
    local f = ensureIODialog()
    f.title:SetText("Import profile")
    f.hint:SetText("Paste a ZAEDN1: profile string and click Import. Existing notes are replaced.")
    f.edit:SetText("")
    f.actionBtn:SetText("Import")
    f.actionBtn:SetScript("OnClick", function()
        local input = f.edit:GetText()
        local imported, err = ns.deserializeNotes(input)
        if not imported then
            print(PREFIX .. "Import failed: " .. (err or "unknown error"))
            return
        end
        local count = 0
        for k in pairs(db.notes) do db.notes[k] = nil end
        for id, text in pairs(imported) do
            db.notes[id] = text
            count = count + 1
        end
        print(PREFIX .. "Imported " .. count .. " note(s).")
        if ns.noteWindow_Refresh then ns.noteWindow_Refresh() end
        if ns.refreshBrowseDialog then ns.refreshBrowseDialog() end
        f:Hide()
    end)
    f:Show()
end

ns.showExportDialog = showExportDialog
ns.showImportDialog = showImportDialog

-- Reset confirmation via StaticPopup
StaticPopupDialogs["ZAEUI_DUNGEONNOTES_CONFIRM_RESET"] = {
    text = "Delete all dungeon notes for this character? This cannot be undone.",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function()
        ns.clearAllNotes()
        print(PREFIX .. "All notes deleted.")
        if ns.noteWindow_Refresh then ns.noteWindow_Refresh() end
        if ns.refreshBrowseDialog then ns.refreshBrowseDialog() end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Slash command handler ----------------------------------------------------

SLASH_ZAEUIDUNGEONNOTES1 = "/zdn"

SlashCmdList["ZAEUIDUNGEONNOTES"] = function(msg)
    msg = strtrim(msg or "")

    if msg == "help" then
        print(PREFIX .. "Usage:")
        print(PREFIX .. "  /zdn - Open the note window for the current instance")
        print(PREFIX .. "  /zdn browse - Browse notes for any visited instance")
        print(PREFIX .. "  /zdn options - Open the options panel")
        print(PREFIX .. "  /zdn export - Export your profile to a shareable string")
        print(PREFIX .. "  /zdn import - Import a profile string")
        print(PREFIX .. "  /zdn reset - Delete all notes (with confirmation)")
        print(PREFIX .. "  /zdn help - Show this help")
        return
    end

    if msg == "browse" then
        if ns.showBrowseDialog then
            ns.showBrowseDialog()
        else
            print(PREFIX .. "Browser not yet loaded.")
        end
        return
    end

    if msg == "options" then
        if ns.settingsCategory then
            Settings.OpenToCategory(ns.settingsCategory.ID)
        else
            print(PREFIX .. "Options panel not yet loaded.")
        end
        return
    end

    if msg == "export" then
        showExportDialog()
        return
    end

    if msg == "import" then
        showImportDialog()
        return
    end

    if msg == "reset" then
        StaticPopup_Show("ZAEUI_DUNGEONNOTES_CONFIRM_RESET")
        return
    end

    -- Default: open the note window for the current instance
    if not ns.noteWindow_Open then
        print(PREFIX .. "Note window not yet loaded.")
        return
    end
    if not currentMapID then
        print(PREFIX .. "Not in a dungeon or raid. Enter an instance first.")
        return
    end
    ns.noteWindow_Open(currentMapID, currentInstanceName)
end

-- Expose to namespace ------------------------------------------------------

ns.ADDON_NAME = ADDON_NAME
ns.PREFIX = PREFIX
ns.constants = { DEFAULTS = DEFAULTS }

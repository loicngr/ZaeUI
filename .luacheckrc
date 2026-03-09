std = "lua51"
max_line_length = false

globals = {
    -- SavedVariables (writable)
    "ZaeUI_NameplatesDB",
    "ZaeUI_NameplateScaleDB", -- migration only, remove in a future version

    -- Slash command system (assigned in addon code)
    "SlashCmdList",
    "SLASH_ZAEUINAMEPLATES1",
}

read_globals = {
    -- Lua globals available in WoW
    "strtrim",

    -- WoW API
    "C_NamePlate",
    "C_Timer",
    "ColorPickerFrame",
    "CreateFrame",
    "GetCVar",
    "SetCVar",
    "Settings",
    "UnitIsUnit",
}

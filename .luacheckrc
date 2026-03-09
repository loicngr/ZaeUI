std = "lua51"
max_line_length = false

globals = {
    -- SavedVariables (writable)
    "ZaeUI_NameplatesDB",
    "ZaeUI_NameplateScaleDB", -- migration only, remove in a future version
    "ZaeUI_InterruptsDB",

    -- Shared settings category (writable, used by multiple addons)
    "ZaeUI_SettingsCategory",

    -- Slash command system (assigned in addon code)
    "SlashCmdList",
    "SLASH_ZAEUINAMEPLATES1",
    "SLASH_ZAEUIINTERRUPTS1",
}

read_globals = {
    -- Lua globals available in WoW
    "strsplit",
    "strtrim",

    -- WoW API
    "C_ChatInfo",
    "C_NamePlate",
    "C_Spell",
    "C_Timer",
    "ColorPickerFrame",
    "CreateFrame",
    "GetCVar",
    "GetNumGroupMembers",
    "GetTime",
    "IsInGroup",
    "IsInInstance",
    "IsInRaid",
    "IsSpellKnown",
    "RAID_CLASS_COLORS",
    "SetCVar",
    "Settings",
    "UIParent",
    "UnitClass",
    "UnitIsUnit",
    "UnitName",
}

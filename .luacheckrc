std = "lua51"
max_line_length = false

globals = {
    -- SavedVariables (writable)
    "ZaeUI_NameplatesDB",
    "ZaeUI_NameplateScaleDB", -- migration only, remove in a future version
    "ZaeUI_InterruptsDB",
    "ZaeUI_ActionBarsDB",
    "ZaeUI_FriendlyPlatesDB",
    "ZaeUI_DefensivesDB",

    -- Shared library (writable in ZaeUI_Shared, read by other addons)
    "ZaeUI_Shared",

    -- Shared settings category (writable, used by multiple addons)
    "ZaeUI_SettingsCategory",

    -- Slash command system (assigned in addon code)
    "SlashCmdList",
    "SLASH_ZAEUINAMEPLATES1",
    "SLASH_ZAEUIINTERRUPTS1",
    "SLASH_ZAEUIACTIONBARS1",
    "SLASH_ZAEUIFRIENDLYPLATES1",
    "SLASH_ZAEUIDEFENSIVES1",
}

read_globals = {
    -- Lua globals available in WoW
    "strsplit",
    "strtrim",
    "wipe",

    -- WoW API
    "C_ChatInfo",
    "CombatLogGetCurrentEventInfo",
    "C_NamePlate",
    "C_Spell",
    "C_Timer",
    "ColorPickerFrame",
    "CreateFrame",
    "GetCVar",
    "GetNumGroupMembers",
    "GetSpecialization",
    "GetSpecializationInfo",
    "GetTime",
    "GameTooltip",
    "IsInGroup",
    "IsInInstance",
    "IsInRaid",
    "LE_PARTY_CATEGORY_INSTANCE",
    "IsPlayerSpell",
    "IsSpellKnown",
    "RAID_CLASS_COLORS",
    "EditModeManagerFrame",
    "InCombatLockdown",
    "RegisterStateDriver",
    "SetCVar",
    "Settings",
    "UIErrorsFrame",
    "UIParent",
    "UnitClass",
    "UnitGroupRolesAssigned",
    "UnitIsGroupLeader",
    "UnitIsUnit",
    "UnitName",

    -- WoW global objects
    "hooksecurefunc",
    "NamePlateDriverFrame",
    "NamePlateFriendlyFrameOptions",
    "NamePlateUnitFrameMixin",
    "SystemFont_NamePlate_Outlined",
    "SystemFont_NamePlate",
    "TableUtil",
    "TextureLoadingGroupMixin",
}

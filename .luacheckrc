std = "lua51"
max_line_length = false

-- Third-party libraries vendored in ZaeUI_Shared/Libs are out of scope:
-- they ship with their own style and naming and we don't modify them.
exclude_files = {
    "**/Libs/**",
    "ZaeUI_Shared/Libs/",
}

globals = {
    -- SavedVariables (writable)
    "ZaeUI_NameplatesDB",
    "ZaeUI_NameplateScaleDB", -- migration only, remove in a future version
    "ZaeUI_InterruptsDB",
    "ZaeUI_ActionBarsDB",
    "ZaeUI_FriendlyPlatesDB",
    "ZaeUI_DefensivesDB",
    "ZaeUI_DefensivesSpellData", -- debug helper: /dump ZaeUI_DefensivesSpellData
    "ZaeUI_DungeonNotesCharDB",
    "ZaeUI_SharedDB",

    -- Shared library (writable in ZaeUI_Shared, read by other addons)
    "ZaeUI_Shared",

    -- Shared settings category (writable, used by multiple addons)
    "ZaeUI_SettingsCategory",

    -- Blizzard StaticPopup system (addons register dialogs by assigning into it)
    "StaticPopupDialogs",

    -- Slash command system (assigned in addon code)
    "SlashCmdList",
    "SLASH_ZAEUINAMEPLATES1",
    "SLASH_ZAEUIINTERRUPTS1",
    "SLASH_ZAEUIACTIONBARS1",
    "SLASH_ZAEUIFRIENDLYPLATES1",
    "SLASH_ZAEUIDEFENSIVES1",
    "SLASH_ZAEUIDUNGEONNOTES1",
}

read_globals = {
    -- Lua globals available in WoW
    "format",
    "strsplit",
    "strtrim",
    "wipe",
    "unpack",
    "debugstack",

    -- WoW API
    "C_ClassTalents",
    "C_ChallengeMode",
    "C_ChatInfo",
    "CombatLogGetCurrentEventInfo",
    "C_NamePlate",
    "C_Spell",
    "C_Timer",
    "C_Traits",
    "Constants",
    "CreateAndInitFromMixin",
    "C_TooltipInfo",
    "C_UnitAuras",
    "CanInspect",
    "ClearInspectPlayer",
    "issecretvalue",
    "UnitGUID",
    "UnitNameUnmodified",
    "ColorPickerFrame",
    "CreateFrame",
    "GetCVar",
    "GetClassInfo",
    "GetInspectSpecialization",
    "GetNumClasses",
    "GetNumGroupMembers",
    "GetNumSpecializationsForClassID",
    "GetSpecialization",
    "GetSpecializationInfo",
    "GetSpecializationInfoForClassID",
    "GetTime",
    "GameTooltip",
    "IsInGroup",
    "IsInInstance",
    "IsInRaid",
    "LE_PARTY_CATEGORY_INSTANCE",
    "IsPlayerSpell",
    "IsSpellKnown",
    "NotifyInspect",
    "RAID_CLASS_COLORS",
    "EditModeManagerFrame",
    "InCombatLockdown",
    "RegisterStateDriver",
    "SetCVar",
    "Settings",
    "UIErrorsFrame",
    "UIParent",
    "UnitClass",
    "UnitIsFeignDeath",
    "UnitGroupRolesAssigned",
    "GetServerTime",
    "UnitIsGroupLeader",
    "UnitIsConnected",
    "UnitCanAttack",
    "UnitIsFriend",
    "UnitInParty",
    "UnitInRaid",
    "UnitIsUnit",
    "UnitExists",
    "Enum",
    "FindSpellOverrideByID",
    "ImportDataStreamMixin",
    "UnitName",
    "UnitRace",
    "AuraUtil",
    "GetInstanceInfo",
    "StaticPopup_Show",
    "StaticPopup_Hide",
    "UIFrameFadeIn",
    "UIFrameFadeOut",
    "GetCursorPosition",
    "IsShiftKeyDown",
    "Minimap",
    "LibStub",

    -- WoW global objects
    "CompactPartyFrame",
    "CompactRaidFrameContainer",
    "CompactRaidGroup_UpdateAll",
    "CompactUnitFrame_UpdateAll",
    "PartyFrame",
    "STANDARD_TEXT_FONT",
    "MenuUtil",
    "hooksecurefunc",
    "NamePlateDriverFrame",
    "NamePlateFriendlyFrameOptions",
    "NamePlateUnitFrameMixin",
    "SystemFont_NamePlate_Outlined",
    "SystemFont_NamePlate",
    "TableUtil",
    "TextureLoadingGroupMixin",
    "CreateColor",
    "ReloadUI",

    -- WoW localization globals (default text for standard dialogs)
    "ACCEPT",
    "CANCEL",
}

std = "lua51"
max_line_length = false

globals = {
    -- SavedVariables (writable)
    "ZaeUI_NameplateScaleDB",

    -- Slash command system (assigned in addon code)
    "SlashCmdList",
    "SLASH_ZAEUINAMEPLATESSCALE1",
}

read_globals = {
    -- Lua globals available in WoW
    "strtrim",

    -- WoW API
    "CreateFrame",
    "GetCVar",
    "SetCVar",
}

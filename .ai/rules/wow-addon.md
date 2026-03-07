# WoW Addon Rules

## Target

- **Version**: Retail / Midnight (12.0.0+)
- **Interface TOC**: `120000`
- **Lua**: 5.1 (embedded runtime in WoW client)

## Addon Structure

Each addon is a self-contained folder at the repository root.
The folder name MUST match the `.toc` file name exactly.

### Simple addon (< 200 lines)

```
AddonName/
├── AddonName.toc
└── AddonName.lua
```

### Complex addon

```
AddonName/
├── AddonName.toc
├── AddonName.lua          -- Entry point, initialization
├── Core/
│   ├── Constants.lua      -- Shared constants
│   ├── Utils.lua          -- Utility functions
│   └── Events.lua         -- Centralized event handling
├── Modules/
│   ├── FeatureA.lua
│   └── FeatureB.lua
└── Libs/                  -- External libraries (Ace3, LibStub, etc.)
```

Only switch to the complex structure when the single file exceeds 200 lines
or contains more than 3 distinct features.

## TOC File

Required fields:

```toc
## Interface: 120000
## Title: AddonName
## Notes: Short description in English.
## Author: loicngr
## Version: 1.0.0
```

Optional fields as needed:

```toc
## SavedVariables: AddonNameDB
## SavedVariablesPerCharacter: AddonNameCharDB
## Dependencies: RequiredAddon
## OptionalDeps: OptionalAddon
```

## WoW Events

### Lifecycle

1. `ADDON_LOADED`: Initialize SavedVariables, configure the addon
2. `PLAYER_LOGIN`: Player is in-game, all APIs are available
3. `PLAYER_LOGOUT`: Cleanup if necessary (WoW saves SavedVariables automatically)

### Rules

- Always check `addonName == ADDON_NAME` in `ADDON_LOADED`
- `UnregisterEvent` after a one-shot event
- Do not register unnecessary events (performance impact)

## WoW API

- Reference source: https://warcraft.wiki.gg
- Never guess an API function name: verify in the documentation
- Check function availability for the target version (Midnight may deprecate APIs)
- Prefer C_* namespaces (newer API) when available

## Compatibility

- Do not modify default Blizzard frames unless that is the addon's purpose
- Prefer native CVars and systems
- Test non-interference with: Plater, ElvUI, WeakAuras, Details
- Do not use deprecated functions

## Slash Commands

- Format: `/shortcmd` (3-4 letters)
- Always provide a help message when the command is called without arguments or with invalid input
- Slash global: `SLASH_ADDONNAME1 = "/cmd"`
- Handler: `SlashCmdList["ADDONNAME"] = function(msg) end`

## Player Messages

- Colored prefix: `|cff00ccff[AddonName]|r`
- Language: English
- Concise and actionable

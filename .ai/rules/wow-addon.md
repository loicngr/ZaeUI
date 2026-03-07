# WoW Addon Rules

## Target

- **Version**: Retail / Midnight (12.0.0+)
- **Interface TOC**: `120000`
- **Lua**: 5.1 (embedded runtime in WoW client)

## Addon Naming

All addons use the `ZaeUI_` prefix: `ZaeUI_<FeatureName>`.
Examples: `ZaeUI_NameplateScale`, `ZaeUI_ActionBars`.

## Addon Structure

Each addon is a self-contained folder at the repository root.
The folder name MUST match the `.toc` file name exactly.

### Simple addon (< 200 lines)

```
ZaeUI_FeatureName/
├── ZaeUI_FeatureName.toc
└── ZaeUI_FeatureName.lua
```

### Complex addon

```
ZaeUI_FeatureName/
├── ZaeUI_FeatureName.toc
├── ZaeUI_FeatureName.lua  -- Entry point, initialization
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
## Title: ZaeUI_FeatureName
## Notes: Short description in English.
## Author: loicngr
## Version: 1.0.0
```

Optional fields as needed:

```toc
## SavedVariables: ZaeUI_FeatureNameDB
## SavedVariablesPerCharacter: ZaeUI_FeatureNameCharDB
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

## Versioning

- Before pushing changes to an addon, **always ask the user** if the `## Version` in the `.toc` file should be bumped
- Use semantic versioning: `MAJOR.MINOR.PATCH`
  - `PATCH`: bug fix, minor tweak
  - `MINOR`: new feature, new command
  - `MAJOR`: breaking change, full rewrite
- The version bump commit should be the last commit before pushing
- A pre-push git hook enforces this: if `.lua` or `.toc` files changed in a `ZaeUI_*/` folder, the `.toc` version line must also be modified

## Player Messages

- Colored prefix: `|cff00ccff[AddonName]|r`
- Language: English
- Concise and actionable

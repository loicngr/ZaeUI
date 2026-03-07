# ZaeUI

[![Lint](https://github.com/loicngr/ZaeUI/actions/workflows/lint.yml/badge.svg)](https://github.com/loicngr/ZaeUI/actions/workflows/lint.yml)

A collection of lightweight World of Warcraft addons for Retail / Midnight.

## Addons

| Addon | Description | Command | Download |
|-------|-------------|---------|----------|
| [ZaeUI_NameplateScale](ZaeUI_NameplateScale/) | Scale up the nameplate of your current target | `/znps` | [CurseForge](https://www.curseforge.com/wow/addons/zaeui-nameplateescale) |

## Installation

1. Download the addon zip from [CurseForge](https://www.curseforge.com/wow/addons/zaeui-nameplateescale) or [GitHub Releases](https://github.com/loicngr/ZaeUI/releases)
2. Extract the folder into:
   ```
   World of Warcraft/_retail_/Interface/AddOns/
   ```
3. Restart WoW or `/reload`

## Project Structure

```
ZaeUI/
├── ZaeUI_<Feature>/      -- One self-contained folder per addon
│   ├── ZaeUI_<Feature>.toc
│   └── ZaeUI_<Feature>.lua
├── docs/plans/           -- Design documents
└── .ai/rules/            -- Code conventions
```

## Tech Stack

- **Lua 5.1** (WoW embedded runtime)
- **WoW API** Retail / Midnight (Interface 12.0.0+)

## License

[GPL-3.0](LICENSE)

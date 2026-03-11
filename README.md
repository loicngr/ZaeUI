# ZaeUI

[![Lint](https://github.com/loicngr/ZaeUI/actions/workflows/lint.yml/badge.svg)](https://github.com/loicngr/ZaeUI/actions/workflows/lint.yml)
[![Release](https://img.shields.io/github/v/release/loicngr/ZaeUI)](https://github.com/loicngr/ZaeUI/releases/latest)

A collection of lightweight World of Warcraft addons for Retail / Midnight.

## Addons

| Addon | Description | Command | Download |
|-------|-------------|---------|----------|
| [ZaeUI_Nameplates](ZaeUI_Nameplates/) | Enhance your target nameplate with scaling, overlap adjustment, arrow indicators, highlight and options panel | `/znp` | [CurseForge](https://www.curseforge.com/wow/addons/zaeui-nameplates) |
| [ZaeUI_Interrupts](ZaeUI_Interrupts/) | Track interrupt, stun and knockback cooldowns for your group with kick marker assignments | `/zint` | [CurseForge](https://www.curseforge.com/wow/addons/zaeui-interrupts) |

## Installation

1. Download the addon zip from [CurseForge](https://www.curseforge.com/wow/addons/zaeui-nameplates) or [GitHub Releases](https://github.com/loicngr/ZaeUI/releases)
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

# ZaeUI

A collection of lightweight World of Warcraft addons for Retail / Midnight.

## Addons

| Addon | Description | Command |
|-------|-------------|---------|
| [ZaeUI_NameplateScale](ZaeUI_NameplateScale/) | Scale up the nameplate of your current target | `/znps` |

## Installation

1. Download the addon zip from [Releases](https://github.com/loicngr/ZaeUI/releases)
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

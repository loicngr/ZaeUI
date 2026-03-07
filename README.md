# ZaeUI

A collection of lightweight World of Warcraft addons for Retail / Midnight.

## Addons

| Addon | Description | Status |
|-------|-------------|--------|
| [NameplateScale](NameplateScale/) | Scale up the nameplate of your current target | Planned |

## Project Structure

```
ZaeUI/
├── <AddonName>/          -- One self-contained folder per addon
│   ├── <AddonName>.toc
│   └── <AddonName>.lua
├── docs/plans/           -- Design documents
└── .ai/rules/            -- Code conventions
```

## Installation

1. Download or clone this repository
2. Copy the desired addon folder (e.g. `NameplateScale/`) into:
   ```
   World of Warcraft/_retail_/Interface/AddOns/
   ```
3. Restart WoW or `/reload`

## Tech Stack

- **Lua 5.1** (WoW embedded runtime)
- **WoW API** Retail / Midnight (Interface 12.0.0+)

## License

[GPL-3.0](LICENSE)

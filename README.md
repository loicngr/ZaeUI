# ZaeUI

[![Lint](https://github.com/loicngr/ZaeUI/actions/workflows/lint.yml/badge.svg)](https://github.com/loicngr/ZaeUI/actions/workflows/lint.yml)
[![Release](https://img.shields.io/github/v/release/loicngr/ZaeUI)](https://github.com/loicngr/ZaeUI/releases/latest)

A collection of lightweight World of Warcraft addons for Retail / Midnight.

## Addons

| Addon | Description | Command | Download |
|-------|-------------|---------|----------|
| [ZaeUI_Shared](ZaeUI_Shared/) | Shared utilities required by all ZaeUI addons | — | [CurseForge](https://www.curseforge.com/wow/addons/zaeui-shared) |
| [ZaeUI_ActionBars](ZaeUI_ActionBars/) | Hide action bars with mouse hover fade in/out | `/zab` | [CurseForge](https://www.curseforge.com/wow/addons/zaeui-actionbars) |
| [ZaeUI_Defensives](ZaeUI_Defensives/) | Track defensive cooldowns for your group in a floating tracker window | `/zdef` | [CurseForge](https://www.curseforge.com/wow/addons/zaeui-defensives) |
| [ZaeUI_FriendlyPlates](ZaeUI_FriendlyPlates/) | Friendly nameplates with name-only mode, class colors and custom font size | `/zfp` | [CurseForge](https://www.curseforge.com/wow/addons/zaeui-friendly-plates) |
| [ZaeUI_Interrupts](ZaeUI_Interrupts/) | Track interrupt, stun and knockback cooldowns for your group with kick marker assignments | `/zint` | [CurseForge](https://www.curseforge.com/wow/addons/zaeui-interrupts) |
| [ZaeUI_Nameplates](ZaeUI_Nameplates/) | Enhance your target nameplate with scaling, overlap adjustment, arrow indicators, highlight and options panel | `/znp` | [CurseForge](https://www.curseforge.com/wow/addons/zaeui-nameplates) |

> ⚠️ **Group sync limitation (ZaeUI_Defensives & ZaeUI_Interrupts)** — Since the Midnight pre-patch (12.0, January 2026), Blizzard silently blocks addon-to-addon communication inside **active Mythic+ runs, PvP matches and raid boss encounters**. Cross-player cooldown sync therefore does not work in those contexts — this affects every cooldown-sharing addon, not just ZaeUI. Everything still works in the open world, in dungeons before the keystone is activated, in raids between pulls, and in solo play. Your own cooldowns always display correctly. See the individual addon READMEs for details.

## Installation

1. Download the addon(s) from [CurseForge](https://www.curseforge.com/wow/addons/search?search=ZaeUI) or [GitHub Releases](https://github.com/loicngr/ZaeUI/releases)
2. **ZaeUI_Shared is required** — install it alongside any other ZaeUI addon
3. Extract the folders into:
   ```
   World of Warcraft/_retail_/Interface/AddOns/
   ```
4. Restart WoW or `/reload`

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

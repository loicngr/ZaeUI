# ZaeUI_Nameplates

Enhance your target nameplate with scaling, automatic overlap adjustment and a colored border — making it easy to spot in large mob packs.

Works with **Midnight (12.0.0+)** and fully compatible with Blizzard's revamped nameplate system.

## How it works

- **Scale & Overlap**: Uses the native `nameplateSelectedScale` and `nameplateOverlapV` CVars
- **Highlight**: Adds a colored border tightly around the target health bar

## Commands

| Command | Description |
|---------|-------------|
| `/znp` | Show current settings |
| `/znp 2.0` | Set target nameplate scale (0.5 - 3.0) |
| `/znp reset` | Reset all settings to defaults |
| `/znp overlap 1.8` | Manually override overlap (0.5 - 5.0) |
| `/znp overlap auto` | Reset overlap to automatic |
| `/znp highlight` | Toggle highlight on/off |
| `/znp border 3` | Set border thickness (1 - 10) |
| `/znp help` | Show help |

## Download

- [GitHub Releases](https://github.com/loicngr/ZaeUI/releases)
- [CurseForge](https://www.curseforge.com/wow/addons/zaeui-nameplates)

## Features

- Scale your target's nameplate to easily spot it in combat
- Colored border hugging the target health bar (customizable thickness)
- Automatic overlap adjustment — nameplates spread out proportionally to the scale
- Settings persist across sessions (automatic migration from ZaeUI_NameplateScale)
- Compatible with Midnight's new nameplate overhaul
- No dependencies

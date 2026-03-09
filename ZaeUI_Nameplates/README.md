# ZaeUI_Nameplates

Enhance your target nameplate with scaling, overlap adjustment, arrow indicators and an optional colored border — making it easy to spot in large mob packs.

Works with **Midnight (12.0.0+)** and fully compatible with Blizzard's revamped nameplate system.

## How it works

- **Scale & Overlap**: Uses the native `nameplateSelectedScale` and `nameplateOverlapV` CVars
- **Arrows**: Two triangle indicators (◀ ▶) on each side of the target health bar
- **Highlight**: Optional colored border tightly around the target health bar
- **Options Panel**: Full UI configuration via Escape → Options → AddOns → ZaeUI → Nameplates

## Commands

| Command | Description |
|---------|-------------|
| `/znp` | Show current settings |
| `/znp options` | Open the options panel |
| `/znp 1.6` | Set target nameplate scale (0.5 - 3.0) |
| `/znp reset` | Reset all settings to defaults |
| `/znp overlap 1.3` | Manually override overlap (0.5 - 5.0) |
| `/znp overlap auto` | Reset overlap to automatic |
| `/znp highlight` | Toggle border on/off |
| `/znp border 3` | Set border thickness (1 - 10) |
| `/znp arrows` | Toggle arrows on/off |
| `/znp arrows size 15` | Set arrow indicator size (4 - 24) |
| `/znp arrows offset 5` | Set arrow offset from health bar (0 - 20) |
| `/znp help` | Show help |

## Download

- [GitHub Releases](https://github.com/loicngr/ZaeUI/releases)
- [CurseForge](https://www.curseforge.com/wow/addons/zaeui-nameplates)

## Features

- Scale your target's nameplate to easily spot it in combat
- Arrow indicators pointing at target nameplate (configurable size and offset)
- Optional colored border hugging the target health bar (customizable thickness)
- Full options panel with color picker (Escape → Options → AddOns → ZaeUI)
- Overlap adjustment — automatic or manual override
- Settings persist across sessions (automatic migration from ZaeUI_NameplateScale)
- Compatible with Midnight's new nameplate overhaul
- No dependencies

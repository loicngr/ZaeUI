# ZaeUI_NameplateScale

A lightweight addon that scales up the nameplate of your current target, making it stand out from the crowd — with automatic overlap adjustment for large mob packs.

Works with **Midnight (12.0.0+)** and fully compatible with Blizzard's revamped nameplate system.

## How it works

Uses the native `nameplateSelectedScale` and `nameplateOverlapV` CVars — no frame hooking, no conflicts with other nameplate addons (Plater, TidyPlates, KUI, ElvUI).

## Commands

| Command | Description |
|---------|-------------|
| `/znps` | Show current scale and overlap |
| `/znps 2.0` | Set target nameplate scale (0.5 - 3.0) |
| `/znps reset` | Reset scale and overlap to defaults |
| `/znps overlap 1.8` | Manually override overlap (0.5 - 5.0) |
| `/znps overlap auto` | Reset overlap to automatic |
| `/znps help` | Show help |

## Download

- [GitHub Releases](https://github.com/loicngr/ZaeUI/releases)
- [CurseForge](https://www.curseforge.com/wow/addons/zaeui-nameplateescale)

## Features

- Scale your target's nameplate to easily spot it in combat
- Automatic overlap adjustment — nameplates spread out proportionally to the scale
- Settings persist across sessions
- Zero performance impact — uses Blizzard's built-in CVar system
- Compatible with Midnight's new nameplate overhaul
- No dependencies

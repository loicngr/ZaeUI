# ZaeUI_NameplateScale

A lightweight addon that scales up the nameplate of your current target, making it stand out from the crowd.

Works with **Midnight (12.0.0+)** and fully compatible with Blizzard's revamped nameplate system.

## How it works

Uses the native `nameplateSelectedScale` CVar — no frame hooking, no conflicts with other nameplate addons (Plater, TidyPlates, KUI, ElvUI).

## Commands

| Command | Description |
|---------|-------------|
| `/znps` | Show current scale |
| `/znps 2.0` | Set target nameplate scale (0.5 - 3.0) |
| `/znps reset` | Reset to default (1.2) |
| `/znps help` | Show help |

## Features

- Scale your target's nameplate to easily spot it in combat
- Settings persist across sessions
- Zero performance impact — uses Blizzard's built-in CVar system
- Compatible with Midnight's new nameplate overhaul
- No dependencies

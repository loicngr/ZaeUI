# ZaeUI_Defensives

Track defensive cooldowns for all group members — displayed in a floating tracker window with real-time cooldown timers, sorted by role.

Works with **Midnight (12.0.0+)** and requires all group members to have the addon for cooldown tracking.

## How it works

- **Addon Messaging**: Players broadcast their available defensive spells and cooldown usage via addon-to-addon communication
- **Floating Tracker**: Draggable frame showing all tracked defensives with real-time cooldown timers, sorted by role (Tank > Healer > DPS)
- **Talent-Aware Cooldowns**: Uses actual spell cooldown durations (respects talent modifiers) instead of static values
- **Three Categories**: Externals (Pain Suppression, Ironbark…), Personal (Fortifying Brew, Astral Shift…), Raidwide (Rallying Cry, Aura Mastery…)
- **Category Filters**: Show or hide externals, personal and raidwide defensives independently
- **Lock Window**: Prevent accidental dragging once positioned
- **Window Opacity**: Adjustable background opacity (30%–100%)
- **Options Panel**: Configuration via Escape → Options → AddOns → ZaeUI → Defensives

## Commands

| Command | Description |
|---------|-------------|
| `/zdef` | Open the options panel |
| `/zdef tracker` | Toggle the floating tracker on/off |
| `/zdef reset` | Reset all settings to defaults |
| `/zdef help` | Show help |

## Features

- Floating tracker window with real-time defensive cooldown timers
- Tracks externals, personal defensives and raid-wide cooldowns
- Talent-aware cooldown durations via C_Spell.GetSpellCooldown
- Works in M+ (5-man) and raids (10-20+)
- Role-based sorting (Tank > Healer > DPS)
- Category filters to show only what matters to you
- Settings persist across sessions
- Compatible with Midnight's group frame system
- No dependencies

## Download

- [GitHub Releases](https://github.com/loicngr/ZaeUI/releases)
- [CurseForge](https://www.curseforge.com/wow/addons/zaeui-defensives)

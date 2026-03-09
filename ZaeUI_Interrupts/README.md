# ZaeUI_Interrupts

Track interrupt, stun and knockback cooldowns for all group members running the addon — displayed in a floating tracker window.

Works with **Midnight (12.0.0+)** and requires all group members to have the addon for full cooldown tracking.

## How it works

- **Addon Messaging**: Players broadcast their available spells and cooldown usage via addon-to-addon communication
- **Floating Tracker**: Draggable frame showing all tracked spells with real-time cooldown timers
- **Two Categories**: "Interrupts" at the top, "Stuns & Others" below
- **Category Filters**: Show or hide interrupts, stuns, and other CC independently
- **Hide Ready Spells**: Option to only display spells currently on cooldown
- **Sort by Cooldown**: Spells on CD shown first, sorted by remaining time
- **Spell Counter**: Tracks how many times each spell was used per player (auto-resets on dungeon entry)
- **Lock Window**: Prevent accidental dragging once positioned
- **Window Opacity**: Adjustable background opacity (10%–100%)
- **Pet Spells**: Supports pet abilities like Spell Lock (Felhunter) and Axe Toss (Felguard)
- **Options Panel**: Configuration via Escape → Options → AddOns → ZaeUI → Interrupts

## Commands

| Command | Description |
|---------|-------------|
| `/zint` | Toggle the tracker window |
| `/zint options` | Open the options panel |
| `/zint resetcount` | Reset spell use counters |
| `/zint reset` | Reset all settings to defaults |
| `/zint help` | Show help |

## Options

- **Show tracker window** — Toggle the floating frame on/off
- **Auto-hide when not in a group** — Automatically hide the tracker when solo
- **Show spell use counter** — Display usage count per spell
- **Auto-reset counters on instance entry** — Reset counters when entering a dungeon or raid
- **Hide ready spells** — Only show spells currently on cooldown
- **Sort by cooldown** — Display spells on CD first, sorted by remaining time
- **Lock tracker window position** — Prevent dragging the tracker
- **Window opacity** — Adjust background transparency (10%–100%)
- **Show Interrupts / Show Stuns / Show Others** — Filter which spell categories are displayed

## Tracked Spells

Covers all classes with 55 spells: interrupts, stuns, knockbacks, disorients and incapacitates. Users can add or remove spells via the `customSpells` and `removedSpells` saved variables.

## Download

- [GitHub Releases](https://github.com/loicngr/ZaeUI/releases)

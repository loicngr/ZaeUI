# ZaeUI_ActionBars

Hide action bars by default and reveal them on mouse hover with configurable fade in/out animations.

## Features

- Hide any of the 10 action bars (Action Bar 1–8, Stance Bar, Pet Bar)
- Smooth fade in on mouse hover, fade out when mouse leaves
- Per-bar configuration: enable/disable, fade in/out duration, delay before fade out
- Show bars automatically during combat (configurable per bar)
- Options panel under AddOns > ZaeUI > ActionBars
- Compatible with WoW Retail / Midnight (Interface 12.0.0+)

## Commands

| Command | Description |
|---------|-------------|
| `/zab` | Open the options panel |
| `/zab help` | Show help |
| `/zab reset` | Reset all settings to defaults |

## Settings (per bar)

| Setting | Range | Default |
|---------|-------|---------|
| Enable | on/off | off |
| Show in combat | on/off | on |
| Fade In | 0.1 – 1.0s | 0.3s |
| Fade Out | 0.1 – 1.0s | 0.3s |
| Delay | 0.0 – 3.0s | 1.0s |

## Compatibility

- Detects ElvUI / Bartender and warns if action bars are replaced
- Suspends fade behavior while Edit Mode is active
- Uses taint-free alpha manipulation (no UIFrameFadeIn/Out on secure frames)

## Installation

1. Copy `ZaeUI_ActionBars/` into `World of Warcraft/_retail_/Interface/AddOns/`
2. Restart WoW or `/reload`

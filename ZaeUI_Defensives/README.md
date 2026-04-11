# ZaeUI_Defensives

Track defensive cooldowns for all group members — displayed in a floating tracker window or anchored to unit frames with real-time cooldown timers, sorted by role.

Works with **Midnight (12.0.0+)** and requires all group members to have the addon for cooldown tracking.

> ⚠️ **Group sync does not work in Mythic+, Arenas, or while a raid boss encounter is in progress.**
>
> Since the Midnight pre-patch (12.0, January 2026), Blizzard restricts addon-to-addon communication during active instanced competitive content: once a Mythic+ keystone is activated, a PvP match has started, or a raid encounter is in progress, addon messages between party members are silently blocked by the game. This affects every cooldown-sharing addon, not just ZaeUI_Defensives.
>
> **What still works:** open world, dungeons before the keystone is activated, raids between pulls, solo play, and any non-instanced group content. Your own cooldowns always display correctly — only the real-time broadcast *to* and *from* other players is affected inside active M+ / Arena / encounters.

## Display Modes

### Floating Tracker (Default)
- **Floating Tracker**: Draggable frame showing all tracked defensives with real-time cooldown timers, sorted by role (Tank > Healer > DPS)
- **Lock Window**: Prevent accidental dragging once positioned
- **Window Opacity**: Adjustable background opacity (30%–100%)

### Anchored to Unit Frames
- **Icon Grids**: Shows cooldown icon grids under or beside Blizzard party/raid frames
- **Configurable Layout**: Icon size, spacing, icons per row, anchor side, and offset adjustments
- **Seamless Integration**: Anchors directly to Blizzard's native unit frames

## How it works

- **Addon Messaging**: Players broadcast their available defensive spells and cooldown usage via addon-to-addon communication (blocked by Blizzard inside active M+ / Arena / raid encounters — see warning above)
- **Talent-Aware Cooldowns**: Automatically adjusts cooldown durations based on active talents and specialization
- **Three Categories**: Externals (Pain Suppression, Ironbark…), Personal (Fortifying Brew, Astral Shift…), Raidwide (Rallying Cry, Aura Mastery…)
- **Category Filters**: Show or hide externals, personal and raidwide defensives independently
- **Options Panel**: Configuration via `/zdef` or Escape → Options → AddOns → ZaeUI → Defensives

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
- Talent-aware cooldowns: automatically adjusts cooldown durations based on active talents and specialization
- Works in M+ (5-man) and raids (10-20+)
- Role-based sorting (Tank > Healer > DPS)
- Category filters to show only what matters to you
- Settings persist across sessions
- Compatible with Midnight's group frame system
- Requires [ZaeUI_Shared](../ZaeUI_Shared/)

## Download

- [GitHub Releases](https://github.com/loicngr/ZaeUI/releases)
- [CurseForge](https://www.curseforge.com/wow/addons/zaeui-defensives)

# ZaeUI_Defensives

Track defensive cooldowns for all group members — displayed in a floating tracker window or anchored to unit frames with real-time cooldown timers, sorted by role.

Works with **Midnight (12.0.0+)**. Only you need the addon installed — allied cooldowns are inferred locally from observable events.

## Display Modes

### Floating Tracker (Default)
- **Floating Tracker**: Draggable frame showing all tracked defensives with real-time cooldown timers, sorted by role (Tank > Healer > DPS)
- **Lock Window**: Prevent accidental dragging once positioned
- **Window Opacity**: Adjustable background opacity (30%–100%)

### Anchored to Unit Frames
- **Icon Grids**: Shows cooldown icon grids under or beside Blizzard party frames (party only — raids always use the floating list)
- **Configurable Layout**: Icon size, spacing, icons per row, anchor side, and offset adjustments
- **Seamless Integration**: Anchors directly to Blizzard's native party unit frames

> ℹ️ In raid (>5 players), the addon automatically switches to the floating
> list view. Per-unit icon grids are too cramped to be useful under Blizzard
> compact raid frames.

## How it works

ZaeUI_Defensives v3 infers allied cooldowns locally from observable aura
events. It does **not** rely on addon-to-addon messaging, which means it
works in every context — including active Mythic+ keystones, raid
encounters, and arenas — where Blizzard blocks addon communication since
the Midnight pre-patch (12.0).

- **Detection sources**: `UNIT_AURA` for visible buffs, `UNIT_FLAGS` for
  immune/combat flag changes (e.g. Aspect of the Turtle), local player
  `UNIT_SPELLCAST_SUCCEEDED` for externals cast by yourself.
- **Group awareness**: only you need the addon installed. Allied specs and
  talents are resolved via LibSpecialization and Blizzard's native inspect
  API.
- **Talent-aware (your cooldowns)**: your own cooldowns and charges are
  adjusted from your active talents. For allies, v3.0.0 uses the catalog
  base cooldown (slight overestimate when the ally has a cooldown
  reduction talent) — decoding allied talent strings into per-talent
  adjustments is planned for a later release.
- **Categories**: Externals (Pain Suppression, Ironbark…), Personal
  (Fortifying Brew, Astral Shift…), Raidwide (Rallying Cry, Aura Mastery…).
- **Category and role filters**: show or hide each category and each role
  (tank/healer/DPS) independently.
- **Active glow**: while a defensive aura is up on an ally, the icon glows
  with a colour matching its category.
- **Options panel**: `/zdef` or Escape → Options → AddOns → ZaeUI → Defensives.

## Commands

| Command | Description |
|---------|-------------|
| `/zdef` | Open the options panel |
| `/zdef tracker` | Toggle the tracker on/off |
| `/zdef reset` | Reset all settings to defaults |
| `/zdef test` | Start test mode (fake party group) |
| `/zdef test raid` | Start test mode (fake raid group of 20) |
| `/zdef test force` | Test mode that keeps running in combat |
| `/zdef test stop` | Stop test mode |
| `/zdef debug` | Toggle debug prints |
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

## Changelog

### 3.0.0

- Complete rewrite: cooldown detection is now local. No more addon messaging.
- Works in Mythic+, arena, and raid encounters (previously blocked since
  Midnight 12.0).
- Active buff glow on icons while a defensive aura is up.
- Role filters: show only Tank / Healer / DPS cooldowns.
- Context toggles: disable the addon in raids or Mythic+ keystones
  individually (both enabled by default).
- Test mode: `/zdef test`, `/zdef test raid`, `/zdef test force`, `/zdef test stop`.
- Classic display style retired; a unified visual style is now used.
  Users on classic auto-migrate on first load.
- LibCustomGlow-1.0 and LibSpecialization embedded in ZaeUI_Shared.
- Raids (>5 players) now always use the floating list, regardless of the
  selected display mode. Anchored grids under compact raid frames were too
  cramped to be practical — the toggle that allowed keeping anchored in
  raids has been removed.

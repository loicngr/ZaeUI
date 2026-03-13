# ZaeUI_Interrupts

Track interrupt, stun and knockback cooldowns for all group members running the addon — displayed in a floating tracker window.

Works with **Midnight (12.0.0+)** and requires all group members to have the addon for full cooldown tracking.

## How it works

- **Addon Messaging**: Players broadcast their available spells and cooldown usage via addon-to-addon communication
- **Floating Tracker**: Draggable frame showing all tracked spells with real-time cooldown timers
- **Kick Marker Assignments**: The group leader can assign raid markers (Star, Circle, Diamond, Triangle, Moon) to group members — markers display in the tracker so everyone knows who kicks which mob. Use `/zint assign` to open the panel (leader only).
- **Separate Marker Window**: Option to show markers in their own floating window instead of inline in the tracker
- **Two Categories**: "Interrupts" at the top, "Stuns & Others" below
- **Category Filters**: Show or hide interrupts, stuns, and other CC independently
- **Hide Ready Spells**: Option to only display spells currently on cooldown
- **Spell Counter**: Tracks how many times each spell was used per player (auto-resets on dungeon entry)
- **Lock Window**: Prevent accidental dragging once positioned
- **Window Opacity**: Adjustable background opacity (10%–100%)
- **Pet Spells**: Supports pet abilities like Spell Lock (Felhunter) and Axe Toss (Felguard)
- **Options Panel**: Configuration via Escape → Options → AddOns → ZaeUI → Interrupts

## Commands

| Command | Description |
|---------|-------------|
| `/zint` | Open the options panel |
| `/zint resetcount` | Reset spell use counters |
| `/zint reset` | Reset all settings to defaults |
| `/zint assign` | Open kick marker assignment panel (leader only) |
| `/zint help` | Show help |

## Options

- **Show tracker window** — Toggle the floating frame on/off
- **Auto-hide when not in a group** — Automatically hide the tracker when solo
- **Show spell use counter** — Display usage count per spell
- **Auto-reset counters on instance entry** — Reset counters when entering a dungeon or raid
- **Hide ready spells** — Only show spells currently on cooldown
- **Lock tracker window position** — Prevent dragging the tracker
- **Show Interrupts / Show Stuns / Show Others** — Filter which spell categories are displayed
- **Kick marker assignments** — Use `/zint assign` to assign raid markers to group members for kick coordination (leader only)
- **Show markers in a separate window** — Display markers in their own floating window instead of inline in the tracker (off by default)
- **Window opacity** — Adjust background transparency for all windows (10%–100%)

## Addon Messaging Protocol

All messages are sent via `C_ChatInfo.SendAddonMessage` with prefix `ZaeInt` on `PARTY`, `RAID` or `INSTANCE_CHAT` channel.

| Message | Direction | Format | Description |
|---------|-----------|--------|-------------|
| `SYNC` | Send & Receive | `SYNC:<spellID>,<spellID>,...` | Broadcast the list of tracked spell IDs the player knows. Sent on login, spec change, pet summon, and every 10s heartbeat. |
| `USED` | Send & Receive | `USED:<spellID>:<cooldown>` | A tracked spell was cast. `cooldown` is the duration in seconds. |
| `READY` | Send & Receive | `READY:<spellID>` | A tracked spell's cooldown has ended and is available again. |
| `MARKS` | Send & Receive | `MARKS:<name>=<index>,<name>=<index>,...` | Kick marker assignments. `index` is the raid marker (1=Star, 2=Circle, 3=Diamond, 4=Triangle, 5=Moon). `MARKS:_` clears all assignments. |

## Tracked Spells

Covers all classes with 55 spells: interrupts, stuns, knockbacks, disorients and incapacitates. Users can add or remove spells via the `customSpells` and `removedSpells` saved variables.

## Download

- [GitHub Releases](https://github.com/loicngr/ZaeUI/releases)

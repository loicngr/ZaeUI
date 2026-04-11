# ZaeUI_Shared

Shared library used by every ZaeUI addon. Provides reusable UI widgets, a standard backdrop style, the **ZaeUI** parent category for Blizzard Settings, and a **minimap button** backed by `LibDBIcon-1.0` that gives one-click access to all ZaeUI settings.

All other ZaeUI addons have `ZaeUI_Shared` as a hard dependency — install it alongside any ZaeUI addon you use.

## Features

- **Parent settings category** — every ZaeUI addon registers itself under `AddOns > ZaeUI > <Addon>` in the Blizzard options
- **Global options panel** — hosted inside the parent category, exposing shared preferences (e.g. the minimap button toggle)
- **Minimap button** — LibDBIcon-1.0 launcher showing the ZaeUI logo next to the minimap; click to open the settings, drag to reposition
- **Shared UI widgets** — `createCheckbox`, `createSlider`, `createDropdown` with consistent styling used by every sub-addon's options panel
- **Standard backdrop** — `applyBackdrop(frame)` for uniform dark panels across the suite
- **`isInAnyGroup()`** helper covering HOME and INSTANCE party categories plus raids

## Minimap button

The minimap button lets you open the ZaeUI settings from anywhere without typing a slash command:

- **Left-click** — opens `AddOns > ZaeUI` in the Blizzard Settings
- **Drag** — reposition around the minimap (position is saved)
- **Hover** — tooltip with quick actions

The button is compatible with minimap button managers (Minimap Button Bag, SexyMap, Titan Panel, Bartender, etc.) because it is registered through the standard LibDBIcon-1.0 / LibDataBroker-1.1 ecosystem.

You can hide the button via **AddOns > ZaeUI > Global → Show minimap button**. The preference is persisted in `ZaeUI_SharedDB` and survives `/reload`.

## Public API

Available to every ZaeUI addon via the `ZaeUI_Shared` global:

| Function | Purpose |
|---|---|
| `isInAnyGroup()` | Returns true if in a party, raid or instance group |
| `applyBackdrop(frame)` | Apply the ZaeUI backdrop style to a frame (must inherit `BackdropTemplate`) |
| `ensureParentCategory()` | Create/return the shared ZaeUI parent Settings category |
| `createCheckbox(parent, y, label, get, set)` | Checkbox widget — returns `(frame, nextY)` |
| `createSlider(parent, y, label, min, max, step, get, set, fmt?)` | Slider widget — returns `(frame, nextY)` |
| `createDropdown(parent, y, label, options, get, set)` | Dropdown widget — returns `(frame, nextY)` |
| `setMinimapButtonShown(shown)` | Show or hide the minimap button (persisted) |
| `isMinimapButtonShown()` | Return whether the minimap button is currently visible |

## Bundled libraries

The `Libs/` folder ships with the standard LibStub ecosystem used by the minimap button. These libraries are **vendored** (copied in) from upstream and are not modified:

| Library | Version | Purpose |
|---|---|---|
| `LibStub` | 2 | Version manager for other libs |
| `CallbackHandler-1.0` | — | Dependency of LibDataBroker |
| `LibDataBroker-1.1` | 4 | Broker object registry |
| `LibDBIcon-1.0` | — | Minimap button standard |

The `Libs/` folder is excluded from the project's `luacheck` to respect upstream code style.

## SavedVariables

```lua
ZaeUI_SharedDB = {
    minimapButton = {
        hide = false,       -- true to hide the button
        minimapPos = 225,   -- angle in degrees around the minimap
    },
}
```

## Installation

1. Install `ZaeUI_Shared` alongside any other ZaeUI addon
2. Extract into `World of Warcraft/_retail_/Interface/AddOns/`
3. Restart WoW or `/reload`

## Download

- [GitHub Releases](https://github.com/loicngr/ZaeUI/releases)
- [CurseForge](https://www.curseforge.com/wow/addons/zaeui-shared)

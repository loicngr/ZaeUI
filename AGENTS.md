# ZaeUI - Agent Instructions

## Project

ZaeUI is a World of Warcraft addon(s) project (Retail / Midnight) written in Lua.
Each addon is a self-contained subfolder at the repository root, with its own `.toc` and `.lua` files.

## Architecture

```
ZaeUI/
├── AGENTS.md
├── CLAUDE.md
├── README.md
├── LICENSE
├── .ai/
│   └── rules/            -- Code rules and conventions
├── docs/
│   └── plans/            -- Design documents and implementation plans
├── ZaeUI_<Feature>/      -- One folder per addon (ZaeUI_ prefix)
│   ├── ZaeUI_<Feature>.toc  -- TOC file (metadata, SavedVariables, file list)
│   ├── ZaeUI_<Feature>.lua  -- Main entry point
│   ├── Core/             -- Business logic (if needed)
│   ├── Modules/          -- Feature modules (if needed)
│   └── Libs/             -- Embedded libraries (if needed)
```

## Tech Stack

- **Language**: Lua 5.1 (WoW runtime)
- **API**: WoW API (Retail / Midnight - Interface 12.0.0+)
- **Persistence**: SavedVariables (Lua tables serialized by WoW)
- **UI**: Blizzard XML or pure Lua (CreateFrame, native widgets)

## Conventions

- Read and follow the rules in `.ai/rules/` before any code change
- Always read a file before modifying it
- Do not create unnecessary files: favor simplicity
- A simple addon = a single `.lua` file + a `.toc`
- Do not over-engineer: add modules/folders only when complexity justifies it
- Validate Lua syntax with `luac -p` after each change if available
- Run `luacheck ZaeUI_<AddonName>/` before committing — must pass with 0 warnings / 0 errors
- Addon folder names must match the `.toc` file name exactly

## WoW API

- Always use WoW API functions documented at https://warcraft.wiki.gg
- Never invent or guess API function names
- Prefer native CVars and existing Blizzard systems when possible
- Test compatibility with popular addons (Plater, ElvUI, WeakAuras)

### WoW 11.0+ "secret" / taint pitfalls (Midnight)

Blizzard now marks many UI values as *secret* / tainted. Reading them in a boolean test or comparison throws an error and can blacklist the addon from protected calls. Use the official tools, not `pcall`:

- **`issecretvalue(v)` (global)** — returns true if `v` is a tainted value. Always test *before* using a value in `if`, `==`, `..`, or as a table key. Many aura fields (`spellId`, `sourceUnit`, `duration`, `auraInstanceID`, `isHarmful`) can be secret on private/hidden auras.
- **`C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, auraInstanceID, filter)`** — lets you probe aura properties (`"HARMFUL"`, `"HELPFUL"`, `"HELPFUL|EXTERNAL_DEFENSIVE"`, `"HELPFUL|IMPORTANT"`, etc.) *without* reading the aura's tainted fields. Returns true if the aura is filtered OUT by that mask; negate to test membership.
- **`COMBAT_LOG_EVENT_UNFILTERED`** — blocked under ADDON_ACTION_FORBIDDEN in current protection rules. Do not register. Derive information from `UNIT_AURA` + `UNIT_SPELLCAST_SUCCEEDED` + `UNIT_FLAGS` + `UNIT_ABSORB_AMOUNT_CHANGED` instead.
- **Remote `UNIT_SPELLCAST_SUCCEEDED` spell IDs are secret.** Only the `player` unit yields a non-secret ID usable for matching. Snapshot locally, never cross-match against a remote unit's cast ID.
- **Guard concatenation and table keys**: `secret .. "x"` silently produces another secret value, but using it as a table key throws. Always `IsSecret(x)`-guard before building keys like `aid .. "|" .. name`.

### Cooldown swipe animations

`CooldownFrameTemplate:SetCooldown(start, duration)` *restarts* the swipe each call. Do not invoke it every frame with `(GetTime(), remaining)` — the animation will loop forever and the icon will stay dark. Pass the real `startedAt` and total `duration`, and only call `SetCooldown` when those values change.

## Git Policy

- **Never commit or push without explicit user confirmation first**
- Always ask the user before running `git commit`, `git push`, or creating a pull request
- Wait for a clear "yes" / approval before proceeding with any git write operation

## Workflow

1. **Design**: Create a document in `docs/plans/` before any non-trivial implementation
2. **Implementation**: Follow the plan, commit in logical steps
3. **Validation**: Verify Lua syntax, review the code
4. **Documentation**: Comment code clearly and usefully

## Sync Rule

- When changing an addon's features or behavior, always keep its slash command help text (e.g. `/znp help`) up to date
- When adding or changing a slash command, also update the UI options panel if one exists
- When changing a setting or its range, update: DEFAULTS table, slash command validation, UI control, help text, README
- When adding or removing an addon, update the addon dropdown lists in `.github/ISSUE_TEMPLATE/bug_report.yml`, `.github/ISSUE_TEMPLATE/feature_request.yml`, and the `addonMap` in `.github/workflows/issue-labeler.yml`

## Language

- Code (variables, functions, inline comments) is in **English**
- Project documentation (plans, README) can be in **French**
- In-game messages displayed to the player are in **English**

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

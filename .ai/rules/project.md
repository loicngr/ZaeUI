# Project Rules

## Language

- **Code** (variables, functions, inline comments): English
- **Documentation** (plans, specs, README): French allowed
- **In-game messages**: English

## File Organization

- `docs/plans/`: Design documents and implementation plans
- `.ai/rules/`: Code rules and conventions for agents
- `<AddonName>/`: One folder per addon at the root

## Principles

- **Simplicity**: Do not create unnecessary files or abstractions
- **Autonomy**: Each addon is independent and deployable on its own
- **Readability**: Code must be understandable without external context
- **Documentation**: Comment what is not obvious, skip the rest
- **Plans before code**: Any non-trivial feature starts with a doc in `docs/plans/`

## Ignored Files

Ensure `.gitignore` excludes:
- `docs/plans` (internal working documents)
- `.ai/artifacts` (generated artifacts)
- IDE files (`.idea/`, `.vscode/`)

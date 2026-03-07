# Commit Rules

## Message Format

```
<type>: <short description>

<optional body>
```

### Allowed Types

- `feat`: New feature
- `fix`: Bug fix
- `refactor`: Refactoring without behavior change
- `docs`: Documentation only
- `chore`: Maintenance, config, CI
- `style`: Formatting, whitespace, semicolons (no logic change)

### Rules

- Description in English, lowercase, no trailing period
- First line < 72 characters
- Optional body separated by a blank line

## Co-Author

**NEVER add a Claude Code co-author (or any other AI) in commits.**

No `Co-Authored-By` line referring to Claude, Anthropic, or any AI assistant.
Commits must be attributed solely to the human author of the project.

## Best Practices

- One commit = one logical change
- Do not commit generated or temporary files
- Do not commit secrets or credentials
- Prefer atomic and frequent commits
- Always review `git diff` before committing

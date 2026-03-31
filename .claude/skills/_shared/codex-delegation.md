Delegate only small, bounded tasks that require reading and understanding the code — not tasks a single command can handle. Good fits:

- **Small coding**: 1–3 functions, self-contained, no architectural decisions
- **Small tests**: 1–3 test cases for a specific, well-specified function or behaviour
- **Complex linting**: ruff or mypy violations that require non-trivial code changes (not auto-fixable with `--fix`)
- **Typing/mypy resolution**: type annotation fixes that require understanding the function contract

For each qualifying task, read the target code, form an accurate brief, then spawn:

```
Agent(
  subagent_type="codex:codex-rescue",
  prompt="<specific task with accurate description of what the code does>. Target: <file>."
)
```

The plugin agent writes directly to the working tree. Inspect changes via `git diff HEAD` after it returns. If the plugin is unavailable it reports gracefully — do not block on this step.

**Do not delegate to Codex:**

- Any task where you cannot write a precise description without guessing
- Anything executable as a single shell command (e.g. `ruff check --fix`, `pytest tests/foo.py`) — run it directly
- Formatting-only changes (black, isort, trailing whitespace) already handled by `pre-commit` — run `pre-commit` instead

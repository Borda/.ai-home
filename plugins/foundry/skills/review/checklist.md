# Review Checklist

## CRITICAL Patterns (must block merge)

- `pickle.load` / `torch.load` without `weights_only=True` on external data → arbitrary code execution via insecure deserialization
- Hardcoded secret in source (password, API key, token)
- `debug=True` in production web server entry point

## HIGH Patterns

- Missing input validation on external HTTP input (not MEDIUM)
- Non-atomic registry/store update: in-memory index + filesystem op without temp-then-rename pattern. Look for: `save_index()` + `shutil.copytree()`, `delete from dict` + `os.remove()`, or any two-phase commit without temp-then-rename
- PR linked to issue but code changes don't address the identified root cause — root cause misalignment
- PR description diverges from linked issue's stated problem — scope divergence (solving something different than reported)

## Consolidation Rules

- Signal-to-noise filter: classify each finding as (a) genuine defect or architectural issue or (b) style/completeness observation (unused import, print-vs-logging, missing class-level docstring on a class that has method-level docstrings)
- For well-scoped modules (≤5 public APIs): max 1 style item per section
- Target: GT+2 findings total per module — a review with 10 nits obscures the 2 critical fixes
- Pre-flight check: before writing any section, count total findings; if count exceeds clearly CRITICAL/HIGH issues plus 2, drop the lowest-severity items first; prefer depth over breadth
- Annotation completeness rule: if ≥1 HIGH/CRITICAL present, omit ALL LOW type annotation and docstring nits — they will be handled by `linting-expert` or pre-commit hooks
- Cap each non-critical section at 5 items; note "N additional lower-priority findings omitted" if more are found

## Actionable Findings Format

For findings that require a human decision (blocking issues, architectural trade-offs, deprecation choices):

- **[SEVERITY] Finding title** — `file:line` context
  - **Issue**: one-sentence description of what is wrong or uncertain
  - **Recommendation**: what to do and why (lead with the action, not the analysis)
  - **Options**:
    - A) [recommended] — description, effort/risk
    - B) alternative — description, effort/risk
    - C) No action — what risk you accept

Rules: lead with the recommendation; one finding per block; skip options for obvious fixes; always include a "no action" option.

## Suppressions (DO NOT flag these)

- `print()` in CLI tools and scripts (not a logging violation)
- Missing docstrings on private functions (underscore-prefixed)
- `# type: ignore[specific-code]` with specific error code (intentional)
- `# noqa: RULE` with explicit rule code (intentional)
- `Any` type in test fixtures and conftest.py
- Single-use helper functions without docstrings (self-documenting by name)

Write for the reader, not the commit author.

| Element                      | Rule                                                                       |
| ---------------------------- | -------------------------------------------------------------------------- |
| Feature heading              | Bold title, period, then plain-English description — no jargon             |
| PR numbers (CHANGELOG)       | Full Markdown link — `([#947](https://github.com/owner/repo/pull/947))`    |
| PR numbers (PUBLIC-NOTES.md) | Short inline ref — `(#947)`                                                |
| Issue refs                   | Never include `closes #N` / `fixes #N` in CHANGELOG or PUBLIC-NOTES.md     |
| Code examples                | Real usage showing the new surface; not pseudocode                         |
| Tables                       | Use for option/preset comparisons; skip for single-item features           |
| Breaking changes             | Rare — use sparingly; false alarms scare users more than the change itself |
| Fix items                    | Say what was broken and under what condition — not just "fixed X"          |
| Changed items                | Behaviour changes only — old behaviour → new behaviour                     |
| Deprecated items             | Name old API and its replacement; omit removal version if unknown          |
| Removed items                | State deprecated-since version and migration target                        |

> **Breaking vs Deprecated**: Normal flow is deprecate → announce removal version → Removed. Breaking Changes is for the rare case where **public API or user-facing behaviour** breaks **immediately** on upgrade with no prior warning and no fallback — including dependency version incompatibilities that affect users directly. Private API and test changes are never Breaking Changes. If the old behaviour still works — even with a deprecation warning — it belongs in Deprecated, not here. When in doubt, it is not Breaking Changes.

Bad/good examples:

- Bad: `"refactor: extract UserService from monolith"` → Good: `"User management is now ~40% faster"`
- Bad: `"Fix auth bug"` → Good: `"Fixed login failure for email addresses containing special characters"`

**Contributors rules:**

- List **every** PR author in the range — human and bot alike; community acknowledgement is essential for growth
- **Bots**: collect all bot handles (accounts ending in `[bot]` or known bots like `dependabot`, `renovate`, `github-actions`) and render them as a single italic line at the bottom of the section: `*Automated contributions: @bot1, @bot2*` — never list bots individually
- **NEVER guess or hallucinate a real name.** A wrong name in public release notes is a serious error. When in doubt, omit the name entirely.
- **Name lookup protocol** — run for every human contributor @handle before writing their entry:
  1. `gh api /users/<handle> --jq '.name'` — if non-null and non-empty, use as the real name (high confidence)
  2. If empty: spawn `web-explorer` to search `site:linkedin.com "<handle>" developer` — use the name only if the profile clearly matches (same avatar, repos, or employer). Note the LinkedIn URL for inclusion.
  3. If still uncertain: use `@handle` only — no name field at all
- Format when name is confirmed: `* **Full Name** (@handle) ([LinkedIn](url)) – *noun phrase*`
- Format when name is not confirmed: `* @handle – *noun phrase*`
- LinkedIn is optional — include only if found via lookup; never construct a URL by guessing
- New contributors get a welcome sentence above the list
- Maintainer always listed last with infra / CI / docs scope

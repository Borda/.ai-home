# Plugin Authoring Rules

Plugins under `plugins/`. See plugin `README.md` for user-facing detail.

## Writing Style

Use `/caveman` compression for all agent, skill, rule file edits — drop articles, filler, hedging; keep full technical substance.

## File Layout

- `.claude-plugin/plugin.json` — version + metadata
- `agents/`, `skills/`, `README.md`, `CLAUDE.md` (optional)
- `rules/`, `hooks/` — foundry only

## Installability

- Every file must be installable via `claude plugin install <name>@borda-ai-rig`
- No file may depend on source tree being present — assume installed path only
- No hardcoded paths to sibling plugins or `plugins/<name>/` directories
- Validate: after `claude plugin install`, all agents/skills/rules/hooks resolve without local `plugins/` tree

## Naming

- Plugin-prefixed refs always: `foundry:sw-engineer`, `oss:review` — never bare names
- Agent `subagent_type` must match filename (e.g. `sw-engineer.md` → `foundry:sw-engineer`)

## Cross-References

- `description` field = routing signal; calibrated threshold `routing accuracy ≥90%`
- NOT-for lines mandatory in every agent; `/audit` Check 16 flags ≥40% overlap
- **Independent instances** — each plugin is independent install; treat as if source tree absent
  - Never cross-ref via local/relative path (e.g. `../foundry/agents/foo.md`) — breaks after install
  - Reference only via installed plugin-prefixed name (e.g. `foundry:sw-engineer`)
- **Opt-in gating required** — plugins opt-in; user may have only subset installed
  - Any cross-plugin usage **must** check availability first
  - Degrade gracefully if dependency plugin absent
  - Unchecked cross-plugin call = broken UX for users without that plugin

## README Sync

**Edit agents/skills/rules/hooks → update plugin `README.md` before done.**

- Added/removed → update README table
- Changed trigger/scope/NOT-for/hook behaviour → update README description

Unsynced change = incomplete.

## Versioning

Per-plugin version in `.claude-plugin/plugin.json`. Space: `0.X.Y`.

| Change type | Bump |
| --- | --- |
| Fix, wording, refactor, cleanup, or restoring behaviour to original design intent | `Y` |
| New capability, new agent/skill, new designed behaviour (not intended before) | `X` |

> **Rule**: Ask "was this *supposed* to work this way?" Yes + it didn't → `Y` (fix). No, this is new intent → `X` (feature). Internal restructuring always `Y` regardless of size or visibility.

**Bump at commit, not per edit** — single bump per commit, highest-magnitude change wins:

- Session has both `Y`- and `X`-class changes → bump `X` only, reset `Y` to `0`
- **Baseline = HEAD, not disk** — always get current version via:
  `git show HEAD:<plugin-path>/.claude-plugin/plugin.json | grep version`
- Bump `X` → reset `Y` to `0` (e.g. `0.2.3` → `0.3.0`)

**Example**: start `0.2.0`, session: wording fix + feature add → commit as `0.3.0` (not `0.2.1`).

## Edit Quality Gate

Before any edit, delete, or addition to plugin files — self-challenge:

- **Best approach?** Simpler path exists → take it; no unnecessary complexity or speculative abstractions
- **No side effects?** Cross-refs still resolve, existing callers unaffected, no behavior regression introduced
- **Complete and clean?** No gaps/TODOs, no dead instructions, no orphaned cross-refs, no leftover stubs
- **Verified?** Every claim backed by code/disk evidence — no hypothesis or assumption stated as fact

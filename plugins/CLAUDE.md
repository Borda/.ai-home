# Plugin Authoring Rules

Plugins under `plugins/`. See plugin `README.md` for user-facing detail.

## Writing Style

Use `/caveman` compression for all agent, skill, rule file edits — drop articles, filler, hedging; keep full technical substance.

## File Layout

- `.claude-plugin/plugin.json` — version + metadata
- `agents/`, `skills/`, `README.md`, `CLAUDE.md` (optional)
- `rules/`, `hooks/` — foundry only

## Naming

- Plugin-prefixed refs always: `foundry:sw-engineer`, `oss:review` — never bare names
- Agent `subagent_type` must match filename (e.g. `sw-engineer.md` → `foundry:sw-engineer`)

## Cross-References

- `description` field = routing signal; calibrated threshold `routing accuracy ≥90%`
- NOT-for lines mandatory in every agent; `/audit` Check 16 flags ≥40% overlap

## README Sync

**Edit agents/skills/rules/hooks → update plugin `README.md` before done.**

- Added/removed → update README table
- Changed trigger/scope/NOT-for/hook behaviour → update README description

Unsynced change = incomplete.

## Versioning

Per-plugin version in `.claude-plugin/plugin.json`. Space: `0.X.Y`.

| Change type | Bump |
| --- | --- |
| Fix, wording, small tweak, minor refactor (no behaviour change) | `Y` |
| Small addition or adjustment to existing agent/skill/rule | `Y` |
| Significant new capability, new agent/skill, major behaviour change, breaking workflow edit | `X` |

**Bump at commit, not per edit** — single bump per commit, highest-magnitude change wins:

- Session has both `Y`- and `X`-class changes → bump `X` only, reset `Y` to `0`
- Read current version from `plugin.json` before bumping — base off last committed version, not mid-session value
- Bump `X` → reset `Y` to `0` (e.g. `0.2.3` → `0.3.0`)

**Example**: start `0.2.0`, session: wording fix + feature add → commit as `0.3.0` (not `0.2.1`).

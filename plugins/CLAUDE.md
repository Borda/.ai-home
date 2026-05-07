# Plugin Authoring Rules

Plugins under `plugins/`. See plugin `README.md` for user-facing detail.

## Writing Style

Use `/caveman` compression for all agent, skill, rule file edits — drop articles, filler, hedging; keep full technical substance.

## File Layout

- `.claude-plugin/plugin.json` — version + metadata
- `agents/`, `skills/`, `README.md`, `CLAUDE.md` (optional)
- `bin/` — optional: standalone executables (`.sh`, `.py`) auto-added to Bash `PATH` by Claude Code; invoked via `${CLAUDE_PLUGIN_ROOT}/bin/<script>` inside skills
- `rules/`, `hooks/` — foundry only

## Installability

- Every file must be installable via `claude plugin install <name>@borda-ai-rig`
- No file may depend on source tree being present — assume installed path only
- No hardcoded paths to sibling plugins or `plugins/<name>/` directories
- Validate: after `claude plugin install`, all agents/skills/rules/hooks resolve without local `plugins/` tree
- **Bare `plugins/` path = only valid as final fallback** after cache-path resolution: `VAR="$(ls -td ~/.claude/plugins/cache/borda-ai-rig/<plugin>/*/skills/_shared 2>/dev/null | head -1)"; [ -z "$VAR" ] && VAR="plugins/<plugin>/skills/_shared"`. Never use bare `plugins/` as primary path. Check C32 flags violations.
- **Health monitoring mandatory for background agents**: any skill spawning `Agent(..., run_in_background=true)` must implement CLAUDE.md §8 (sentinel + 5-min poll + 15-min cutoff). Reference `_FOUNDRY_SHARED/agent-spawn-protocol.md` rather than reproducing inline. Check C35 flags violations.

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
- **Prose references too**: any mention of `/plugin:skill` in `<notes>`, follow-up chains, or documentation prose (not just dispatch calls) must include `(requires \`<plugin>\` plugin)` inline caveat. Check 28c flags unguarded prose refs.

## Fallback / Resilience Infrastructure

**The self-defeating plugin trap** — hook or skill whose job is "handle plugin `foo` being absent" cannot live inside plugin `foo`. If `foo` absent, hook never runs.

- **General rule: resilience code lives in the plugin whose users need protecting, not the plugin being protected against**
- Examples: fallback for missing `foundry` agents → cannot live in `foundry`; fallback for missing `oss` agents → cannot live in `oss`; same applies to any plugin pair

Correct placement: every plugin that dispatches agents from other plugins ships own fallback hook. Source of truth lives in one plugin; `sync.sh` copies to others at release.

No plugin dependency system exists in Claude Code — never propose "install `foo` as prerequisite" or "register globally via `foo` init" as solution to missing-plugin resilience. Circular: requires thing that might be absent.

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

**Pre-bump checklist** — run before writing any version change to disk:

1. Read HEAD baseline: `git show HEAD:<plugin-path>/.claude-plugin/plugin.json | grep version`
2. Classify highest-magnitude change in session (`X` or `Y`) — do NOT read on-disk version; disk may already differ from HEAD
3. Calculate new version from HEAD baseline: `X` → bump minor, reset patch to `0`; `Y` → bump patch only
4. Write calculated version to `<plugin-path>/.claude-plugin/plugin.json` — if on-disk version already equals or exceeds calculated, skip write

## Edit Quality Gate

Before any edit, delete, or addition to plugin files — self-challenge:

- **Best approach?** Simpler path exists → take it; no unnecessary complexity or speculative abstractions
- **No side effects?** Cross-refs still resolve, existing callers unaffected, no behavior regression introduced
- **Complete and clean?** No gaps/TODOs, no dead instructions, no orphaned cross-refs, no leftover stubs
- **Verified?** Every claim backed by code/disk evidence — no hypothesis or assumption stated as fact

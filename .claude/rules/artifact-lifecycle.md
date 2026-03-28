---
description: Artifact directory layout, naming convention, TTL policy, and cleanup hook
---

## Canonical artifact layout

All runtime artifacts live at the **project root** in `_<skill>/` directories, not inside `.claude/`. The underscore prefix sorts them together and signals "generated output, not source config".

```
_calibrate/          ← /calibrate skill runs
_resolve/            ← /resolve lint+QA gate runs
_audit/              ← /audit skill runs
_review/             ← /review skill runs
_optimize/           ← /optimize skill runs (perf + campaign modes)
_develop/            ← /develop review-cycle runs
_out/                ← quality-gates long output (cross-cutting)
  YYYY/MM/
tasks/_plans/        ← todo_*.md, plan_*.md (tracked)
  active/
  closed/
tasks/_working/      ← lessons.md, diary, guides (tracked)
```

All `_<skill>/` and `_out/` dirs are gitignored — they are ephemeral and TTL-managed.

## Run directory naming

Every skill creates a timestamped subdirectory:

```bash
RUN_DIR="_<skill>/$(date -u +%Y-%m-%dT%H-%M-%SZ)"
mkdir -p "$RUN_DIR"
```

Format: `YYYY-MM-DDTHH-MM-SSZ` (UTC, dashes throughout, filesystem-safe). Example: `_calibrate/2026-03-27T20-06-22Z/`.

A completed run always contains `result.jsonl`. Incomplete runs (crashed, timed out) lack it — the TTL hook skips them (intentional: keeps them for debugging).

## TTL policy

| Location                         | TTL     | Condition                                      |
| -------------------------------- | ------- | ---------------------------------------------- |
| `_<skill>/YYYY-MM-DDTHH-MM-SSZ/` | 30 days | only dirs containing `result.jsonl`            |
| `_out/`                          | 30 days | keyed on file mtime                            |
| `tasks/_plans/`                  | manual  | move to `closed/` when done; never auto-delete |
| `tasks/_working/`                | manual  | human-maintained                               |
| `.claude/logs/`                  | forever | rotate at 10 MB                                |

## Cleanup hook (SessionEnd)

The `SessionEnd` hook runs this cleanup automatically:

```bash
# Delete completed skill runs older than 30 days
find _calibrate _resolve _audit _review _optimize _develop \
  -maxdepth 2 -name "result.jsonl" -mtime +30 2>/dev/null \
  | xargs -r dirname | xargs -r rm -rf

# Delete stale temp outputs older than 30 days
find _out -type f -mtime +30 2>/dev/null | xargs -r rm -f

# Prune empty year/month dirs in _out
find _out -mindepth 1 -maxdepth 2 -type d -empty 2>/dev/null | xargs -r rmdir
```

## Settings.json allow entries

The deterministic `_*/` paths allow precise allow rules:

```json
"Bash(mkdir -p _calibrate/*)",
"Bash(mkdir -p _resolve/*)",
"Bash(mkdir -p _audit/*)",
"Bash(mkdir -p _review/*)",
"Bash(mkdir -p _optimize/*)",
"Bash(mkdir -p _develop/*)",
"Bash(mkdir -p _out/*/*)",
"Bash(find _calibrate*)",
"Bash(find _resolve*)",
"Bash(find _audit*)",
"Bash(find _review*)",
"Bash(find _optimize*)",
"Bash(find _develop*)",
"Bash(find _out*)"
```

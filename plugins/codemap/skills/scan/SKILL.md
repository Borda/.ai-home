---
name: scan
description: Scan the Python codebase and build a structural JSON index (import graph + blast-radius metrics).
argument-hint: '[--root <path>] [--incremental]'
effort: medium
allowed-tools: Bash
---

<objective>

**Python only** — uses `ast.parse` to extract import graph and symbol metadata across all `.py` files; non-Python files not indexed. Writes `.cache/scan/<project>.json`. No external deps required.

Index captures per module: import graph, blast-radius metrics, and **symbol list** (classes, functions, methods with line ranges). Symbol data enables `scan-query symbol` / `find-symbol` to return just the target function source instead of full file reads.

Agents and develop skills query index via `scan-query` to understand module dependencies, blast radius, coupling, and individual symbol source before editing code.

NOT for: querying existing index (use `/codemap:query`).

</objective>

<workflow>

## Step 1: Run the scanner

Parse `$ARGUMENTS` to build the invocation. Pass `--root <path>` if provided; pass `--incremental` if provided. Then run once:

```bash
# timeout: 360000
# Example with both flags: ${CLAUDE_PLUGIN_ROOT}/bin/scan-index --root /path/to/project --incremental
# scan-index handles v2→v3 fallback internally — exits 0 on either path
${CLAUDE_PLUGIN_ROOT}/bin/scan-index [--root <path>] [--incremental]
```

Scanner writes to `<root>/.cache/scan/<project>.json` and prints summary line:

```text
[codemap] ✓ .cache/scan/<project>.json
[codemap]   N modules indexed, M degraded
```

## Step 2: Report

After scan completes, read index and report compact summary:

```bash
# IMPORTANT: pass $ARGUMENTS via env var — never interpolate into script path or args.
# CLAUDE_PLUGIN_ROOT is set automatically by Claude Code when plugin is active.
# timeout: 15000
SCAN_ARGS="$ARGUMENTS" python3 "${CLAUDE_PLUGIN_ROOT}/bin/scan-stats.py"
```

Degraded files exist: list with reason. Not failure — index still useful.

## Step 3: Suggest next step

```text
Index ready. Query it with:
  /codemap:query central --top 10
  /codemap:query deps <module>
  /codemap:query rdeps <module>
  /codemap:query coupled --top 10
  # see /codemap:query for full list of subcommands
```

</workflow>

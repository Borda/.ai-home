---
name: scan
description: Scan the Python codebase and build a structural JSON index (import graph + blast-radius metrics).
argument-hint: [--root <path>]
effort: medium
allowed-tools: Bash
disable-model-invocation: false
---

<objective>

Build a structural index of the Python codebase. Uses `ast.parse` to extract the import graph across all Python files, writes `.cache/scan/<project>.json`. No external dependencies required.

Agents and develop skills query this index via `scan-query` to understand module dependencies, blast radius, and coupling before editing code.

NOT for: querying an existing index (use `/codemap:query`).

</objective>

<workflow>

## Step 1: Run the scanner

`scan-index` is on PATH via the plugin's `bin/` directory — invoke it directly:

```bash
# timeout: 360000
scan-index
```

If `--root` was passed as an argument, forward it:

```bash
# timeout: 360000
scan-index --root <path>
```

The scanner writes to `.cache/scan/<project>.json` and prints a summary line:

```
[codemap] ✓ .cache/scan/<project>.json
[codemap]   N modules indexed, M degraded
```

## Step 2: Report

After the scan completes, read the index and report a compact summary:

```bash
python3 -c "
import json, sys
with open('.cache/scan/$(basename $(git rev-parse --show-toplevel)).json') as f:
    d = json.load(f)
ok = [m for m in d['modules'] if m.get('status') == 'ok']
deg = [m for m in d['modules'] if m.get('status') == 'degraded']
top = sorted(ok, key=lambda m: m.get('rdep_count', 0), reverse=True)[:5]
print(f\"Modules: {len(ok)} indexed, {len(deg)} degraded\")
print(f\"Most central (by rdep_count):\")
for m in top:
    print(f\"  {m.get('rdep_count', 0):>3}  {m['name']}\")
"
```

Output format:

```
✓ codemap index built: .cache/scan/<project>.json
  Modules:  N indexed, M degraded

  Most central (rdep_count):
    42  mypackage.models
    28  mypackage.config
    ...

  Degraded files (if any):
    ⚠ src/generated/proto.py — SyntaxError: ...
```

If degraded files exist: list them with their reason. Do not treat degraded files as a failure — the index is still useful.

## Step 3: Suggest next step

```
Index ready. Query it with:
  /codemap:query central --top 10
  scan-query deps <module>
  scan-query rdeps <module>
  scan-query coupled --top 10

develop:feature, develop:fix, develop:plan, and develop:refactor pick this up automatically.
```

</workflow>

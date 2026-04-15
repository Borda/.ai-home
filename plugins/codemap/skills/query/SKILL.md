---
name: query
description: Query the codemap structural index — central, coupled, deps, rdeps, or import path between modules.
argument-hint: <central [--top N] | coupled [--top N] | deps <module> | rdeps <module> | path <from> <to>>
effort: low
allowed-tools: Bash
disable-model-invocation: false
---

<objective>

Query the codemap structural index. Delegates to `scan-query` and returns JSON results. Checks staleness on every call — warns if Python files were committed after the index was built.

Queries:

- `central [--top N]` — most-imported modules (highest blast radius, default top 10)
- `coupled [--top N]` — modules with most imports (highest coupling, default top 10)
- `deps <module>` — what does this module import?
- `rdeps <module>` — what imports this module?
- `path <from> <to>` — shortest import path between two modules

NOT for: building or rebuilding the index (use `/codemap:scan`).

</objective>

<workflow>

## Step 1: Check index exists

```bash
INDEX=".cache/scan/$(basename $(git rev-parse --show-toplevel)).json"
[ -f "$INDEX" ] || { echo "[codemap] No index found. Run /codemap:scan first."; exit 1; }
```

## Step 2: Run the query

Pass the argument directly to scan-query. All output is JSON.

**central** (most-imported modules):

```bash
# timeout: 15000
scan-query central --top 10
```

**coupled** (modules with most imports):

```bash
# timeout: 15000
scan-query coupled --top 10
```

**deps**:

```bash
# timeout: 15000
scan-query deps <module>
```

**rdeps**:

```bash
# timeout: 15000
scan-query rdeps <module>
```

**path**:

```bash
# timeout: 15000
scan-query path <from> <to>
```

If `scan-query` prints a staleness warning to stderr, surface it to the user before the results.

## Step 3: Format and return

Parse the JSON output and present it clearly.

For `central`: list top modules by rdep_count — "N modules import this; changing it has wide blast radius."

```
Top 10 most-imported modules (blast radius):

  rdep_count  module
  ----------  ------
          42  mypackage.models
          28  mypackage.config
          15  mypackage.core.dispatcher
  ...
```

For `coupled`: list top modules by dep_count — "imports N modules; tightly coupled."

```
Top 10 most-coupled modules:

  dep_count  module
  ---------  ------
         18  mypackage.pipeline.runner
         14  mypackage.auth
         11  mypackage.api
  ...
```

For `deps` / `rdeps`: list the modules, one per line.

For `path`: show the import chain as `A → B → C → D`.

If the result contains `{"error": "..."}`: surface the error and suggest corrective action (re-scan, check module name spelling).

</workflow>

---
name: integration
description: Manage codemap integration — 'check' audits installation health (scan-query reachable, index fresh, injection present), 'init' onboards codemap by discovering skills/agents, recommending injection sites, and wiring them in.
argument-hint: check | init [--approve]
effort: medium
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion
model: opus
---

<objective>

Two modes in one skill — run sequentially: `init` to set up, `check` to verify.

- **`check`** — fast diagnostic: finds `scan-query`, verifies the index exists and is fresh, runs a smoke test, and audits which skill files have the injection block. Prints `✓`/`✗`/`⚠` per check with one-line remediation hints. Pure bash — no model reasoning needed for the happy path.
- **`init`** — interactive onboarding: builds the index if missing, discovers all installed skills and agents, scores them by how much codemap would help, presents a recommendation table, asks which to wire in, and inserts the correct injection block into each selected file.

NOT for: building or rebuilding the index (use `/codemap:scan`); running a structural query (use `/codemap:query`).

</objective>

<inputs>

- **`check`** — audit current installation. No other arguments.
- **`init`** — onboard codemap to this project.
  - **`--approve`** — non-interactive; auto-apply all starred (★) recommendations without prompting.

</inputs>

<workflow>

## Mode detection

Parse `$ARGUMENTS` (case-insensitive):

- Starts with `check` or is empty → run **check mode** (Steps C1–C5)
- Starts with `init` → run **init mode** (Steps I0–I6)
- Anything else → print: `Usage: /codemap:integration check | init [--approve]` and stop.

______________________________________________________________________

## CHECK MODE (Steps C1–C5)

### C1 — Locate scan-query

Three-tier fallback: PATH → plugin root → cache glob.

```bash
# timeout: 5000
GRN='\033[0;32m'; RED='\033[1;31m'; YEL='\033[1;33m'; NC='\033[0m'
if command -v scan-query >/dev/null 2>&1; then
    SQ=$(command -v scan-query); SRC="PATH"
elif [ -x "${CLAUDE_PLUGIN_ROOT}/bin/scan-query" ]; then
    SQ="${CLAUDE_PLUGIN_ROOT}/bin/scan-query"; SRC="CLAUDE_PLUGIN_ROOT"
else
    SQ=$(ls "$HOME/.claude/plugins/cache/borda-ai-home/codemap"/*/bin/scan-query 2>/dev/null | sort -V | tail -1)
    SRC="cache glob"
fi
if [ -n "$SQ" ] && [ -x "$SQ" ]; then
    printf "${GRN}✓${NC} scan-query: %s (via %s)\n" "$SQ" "$SRC"
else
    printf "${RED}✗${NC} scan-query: not found\n"
    printf "  → Install: claude plugin install codemap@borda-ai-home\n"
    exit 1
fi
```

### C2 — PROJ and index existence

```bash
# timeout: 5000
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
PROJ=${GIT_ROOT:+$(basename "$GIT_ROOT")}; PROJ=${PROJ:-$(basename "$PWD")}
INDEX=".cache/scan/${PROJ}.json"
printf "  project: %s\n  index:   %s\n" "$PROJ" "$INDEX"
if [ -f "$INDEX" ]; then
    printf "${GRN}✓${NC} index: exists\n"
else
    printf "${RED}✗${NC} index: not found\n"
    printf "  → Run /codemap:scan to build the index\n"
    exit 1
fi
```

### C3 — Index freshness (calendar age)

```bash
# timeout: 10000
python3 -c "
import json, sys
from datetime import datetime, timezone
d = json.load(open('$INDEX'))
sa = d.get('scanned_at', '')
if not sa:
    print('WARN|scanned_at missing — index may be corrupted|Re-run /codemap:scan')
    sys.exit()
age = (datetime.now(timezone.utc) - datetime.fromisoformat(sa)).days
s = 'WARN' if age > 7 else 'OK'
print(f'{s}|{age} day{\"s\" if age != 1 else \"\"} ago ({sa[:10]})|Run /codemap:scan to refresh')
" | while IFS='|' read s d h; do
    case $s in
        OK)   printf "${GRN}✓${NC} freshness: %s\n" "$d" ;;
        WARN) printf "${YEL}⚠${NC} freshness: %s\n  → %s\n" "$d" "$h" ;;
    esac
done
```

### C4 — Smoke test and git-staleness check

```bash
# timeout: 15000
OUT=$("$SQ" central --top 3 2>/tmp/cmc_err); RC=$?
if [ $RC -ne 0 ]; then
    printf "${RED}✗${NC} smoke test: exit %s\n" "$RC"
    [ -s /tmp/cmc_err ] && printf "  stderr: %s\n" "$(cat /tmp/cmc_err)"
    printf "  → Check index with: %s list\n" "$SQ"
else
    STALE=$(python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('index',{}).get('stale','?'))" <<< "$OUT" 2>/dev/null)
    printf "${GRN}✓${NC} smoke test: central query OK (git-stale=%s)\n" "$STALE"
    if [ "$STALE" = "True" ]; then
        printf "  ${YEL}⚠${NC} Python files changed since scan — run /codemap:scan to update\n"
    fi
fi
rm -f /tmp/cmc_err
```

### C5 — Skill injection audit

```bash
# timeout: 20000
CACHE=$(dirname "$(dirname "$CLAUDE_PLUGIN_ROOT")")
printf "\n--- Skill injection audit (cache: %s) ---\n" "$CACHE"
FILES=$(find "$CACHE" -name "SKILL.md" -exec grep -l "command -v scan-query" {} \; 2>/dev/null | sort)
COUNT=$(echo "$FILES" | grep -c . 2>/dev/null || echo 0)
printf "${GRN}✓${NC} %s SKILL.md file(s) have the injection block:\n" "$COUNT"
echo "$FILES" | while read -r f; do
    [ -n "$f" ] && printf "  • %s\n" "${f#$CACHE/}"
done
for exp in "develop/*/skills/fix" "develop/*/skills/feature" "develop/*/skills/refactor" "develop/*/skills/plan" "develop/*/skills/review" "oss/*/skills/review"; do
    echo "$FILES" | grep -q "$exp" \
        || printf "  ${YEL}⚠${NC} missing injection in: %s/SKILL.md\n" "$exp"
done
printf "\n--- check complete ---\n"
printf "If any check failed:\n"
printf "  • /codemap:scan    — build or refresh the index\n"
printf "  • /codemap:integration init — add injection to more skills/agents\n"
printf "  • /codemap:integration check — re-run after fixes\n"
```

______________________________________________________________________

## INIT MODE (Steps I0–I6)

### I0 — Detect --approve

Parse `$ARGUMENTS` for `--approve` (case-insensitive). If found, set `APPROVE_ALL=true` — every `AskUserQuestion` below is skipped and the ★ recommended option is applied automatically. Print `[--approve] applying recommended options` in place of each question.

### I1 — Verify or build the index

```bash
# timeout: 5000
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
PROJ=${GIT_ROOT:+$(basename "$GIT_ROOT")}; PROJ=${PROJ:-$(basename "$PWD")}
INDEX=".cache/scan/${PROJ}.json"
```

If index exists: report it and proceed. If missing:

Use `AskUserQuestion` to present (unless `APPROVE_ALL=true`, then auto-select a):

```
No codemap index found for project: $PROJ

a) Build now ★ — scans all .py files via ast.parse (Python only), <60s on most projects
b) Skip — I'll run /codemap:scan later (recommendations will be generic, no module-count weighting)
```

If **a** (or auto-approved): run the scanner:

```bash
# timeout: 360000
${CLAUDE_PLUGIN_ROOT}/bin/scan-index
```

Report the result (module count, degraded count). If **b**: note "Proceeding without index — recommendations are based on skill purpose only, not module count."

### I2 — Discover installed skills and agents

Read `~/.claude/plugins/installed_plugins.json` to find all installed plugins. For each plugin's `installPath`, glob for:

- `skills/*/SKILL.md` — skill files
- `agents/*.md` — agent files

For each file: extract from frontmatter: `name`, `description`, `allowed-tools` (skills) or `description` body (agents). Extract the first sentence of the `<objective>` section.

Flag which files already have the injection block:

```bash
# timeout: 10000
find "$CACHE" -name "SKILL.md" -exec grep -l "command -v scan-query" {} \; 2>/dev/null
```

Build two lists: `ALREADY_INJECTED` and `CANDIDATES` (not yet injected).

### I3 — Score and rank candidates

For each candidate skill/agent, classify by value tier using its `<objective>` text and `allowed-tools`:

| Tier       | Signal                                                                                                                              | Recommendation                                                    |
| ---------- | ----------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------- |
| **High**   | `allowed-tools` includes `Edit` or `Write`; `<objective>` mentions spawning `sw-engineer` or `qa-specialist`; performs code changes | "Strongly recommend — agent starts with blast-radius context"     |
| **Medium** | analysis or planning skills; spawns read-only agents; multi-file review without edits                                               | "Moderate value — centrality context speeds structural decisions" |
| **Low**    | documentation, release, communication; no code traversal                                                                            | "Low value — structural context unlikely to help"                 |
| **Skip**   | config-only, single-file, non-Python purpose (e.g. shell, YAML, JS)                                                                 | "Skip — not applicable for Python import graphs"                  |

If index was built and `total_modules < 20`: downgrade all tiers by one level (small project = less value from structural context).

### I4 — Present recommendations and ask user

Print a candidate table:

```
Codemap injection candidates for: $PROJ

  Status  Skill/Agent          Tier    Notes
  ──────────────────────────────────────────────────────────────────
  ✓       develop:fix          HIGH    spawns sw-engineer — already integrated
  ✓       develop:feature      HIGH    spawns sw-engineer — already integrated
  a)      research:plan        MEDIUM  plans experiments; reads code structure
  b)      foundry:calibrate    MEDIUM  runs test agents against the codebase
  —       foundry:doc-scribe   LOW     writes docstrings; skip
  —       oss:release          SKIP    release/comms; skip
```

Use `AskUserQuestion` to ask (unless `APPROVE_ALL=true`, then auto-select all HIGH+MEDIUM):

```
Which skills/agents should I add codemap injection to?

Reply with letters (e.g. "a b"), "all" (all High+Medium), or "none".
```

### I5 — Wire in the injection block

For each selected file, determine the insertion point and content:

**For SKILL.md files** — find the step that first spawns an agent. Insert the hardened soft-check block immediately before it, with a blank line before and after:

```bash
# Structural context (codemap — Python projects only, silent skip if absent)
PROJ=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null) || PROJ=$(basename "$PWD")
if command -v scan-query >/dev/null 2>&1 && [ -f ".cache/scan/${PROJ}.json" ]; then
    scan-query central --top 5  # timeout: 5000
fi
# If results returned: prepend a ## Structural Context (codemap) block to the agent spawn prompt.
```

For skills where a target module can be derived from `$ARGUMENTS` (refactor, fix with module path, review), also add after `central`:

```bash
scan-query rdeps "$TARGET_MODULE" 2>/dev/null  # timeout: 5000
scan-query deps  "$TARGET_MODULE" 2>/dev/null  # timeout: 5000
```

**For agent `.md` files** — append to the last workflow instruction paragraph, before any closing section or final notes:

```markdown
**Structural context (codemap — Python projects only)**: if `.cache/scan/<project>.json` exists, run `scan-query central --top 5` (and `scan-query rdeps <target_module>` when a target is known) **before** any Glob/Grep exploration for structural information. Skip silently if the index is absent.
```

Report each edit: `✓ injected: <plugin>/<skill-or-agent> at line N`

### I6 — Summary report

Print:

```
--- init complete ---

Injected codemap into N skill(s)/agent(s):
  ✓ research:plan    → <path>
  ✓ ...

Already integrated (no change):
  • develop:fix, develop:feature, ...

Skipped:
  • foundry:doc-scribe — LOW value
  • oss:release — SKIP

Next: run /codemap:integration check to verify all injection blocks are wired correctly.
```

</workflow>

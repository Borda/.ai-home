---
name: analyse
description: Analyze GitHub issues, Pull Requests (PRs), Discussions, and repo health for an Open Source Software (OSS) project. For any specific item, casts a wide net — finds and lists all related open and closed issues/PRs/discussions, explicitly flags duplicates. Also summarizes long threads, assesses PR readiness, extracts reproduction steps, and generates repo health stats. Uses gh Command Line Interface (CLI) for GitHub Application Programming Interface (API) access. Complements shepherd agent.
argument-hint: <N|health|ecosystem|path/to/report.md> [--reply]
allowed-tools: Read, Bash, Write, Agent, AskUserQuestion
context: fork
model: opus
effort: high
---

<objective>

Analyze GitHub threads + repo health. Help maintainers triage, respond, decide fast. Output actionable + structured — not just summaries.

</objective>

<inputs>

- **$ARGUMENTS**: one of:
  - `N` (number, plain `123` or `#123`) — any GitHub thread: issue, PR, or discussion; auto-detects type
  - `health` — repo issue/PR/discussion health overview with duplicate detection
  - `ecosystem` — downstream consumer impact analysis for library maintainers
  - `--reply` — only valid with `N`; spawns shepherd to draft contributor-facing reply after thread analysis. Silently ignored for `health` and `ecosystem`.
  - `path/to/report.md` — path to existing report file; only valid combined with `--reply`; skips all analysis, spawns shepherd directly using provided file

</inputs>

<constants>
<!-- Background agent health monitoring (CLAUDE.md §8) — applies to Step 7 shepherd spawn -->
MONITOR_INTERVAL=300   # 5 minutes between polls
HARD_CUTOFF=900        # 15 minutes of no file activity → declare timed out
EXTENSION=300          # one +5 min extension if output file explains delay
</constants>

<workflow>

<!-- Agent Resolution: canonical table at plugins/oss/skills/_shared/agent-resolution.md -->

## Agent Resolution

```bash
# Locate oss plugin shared dir — installed first, local workspace fallback
_OSS_SHARED=$(ls -td ~/.claude/plugins/cache/borda-ai-rig/oss/*/skills/_shared 2>/dev/null | head -1)
# If glob expands to zero matches, ls exits non-zero but head exits 0 — pipe exit code is head's.
# Correctness is preserved by the fallback guard below (not by $?).
[ -z "$_OSS_SHARED" ] && _OSS_SHARED="plugins/oss/skills/_shared"

FOUNDRY_SHARED=$(ls -td ~/.claude/plugins/cache/borda-ai-rig/foundry/*/skills/_shared 2>/dev/null | head -1)
[ -z "$FOUNDRY_SHARED" ] && FOUNDRY_SHARED=".claude/skills/_shared"
```

## Step 1: Flag parsing

```bash
REPLY_MODE=false
CLEAN_ARGS=$ARGUMENTS
if [[ "$ARGUMENTS" == *"--reply"* ]]; then
    REPLY_MODE=true
    CLEAN_ARGS="${ARGUMENTS//--reply/}"
    CLEAN_ARGS="${CLEAN_ARGS#"${CLEAN_ARGS%%[![:space:]]*}"}"
fi # timeout: 5000
```

```bash
# Strip leading '#' so both '123' and '#123' work
CLEAN_ARGS="${CLEAN_ARGS#\#}"
```

`REPLY_MODE` only meaningful when `$CLEAN_ARGS` is number — silently ignored for `health` and `ecosystem`.

```bash
DIRECT_PATH_MODE=false
if [[ "$CLEAN_ARGS" == *.md ]]; then
    DIRECT_PATH_MODE=true
    REPORT_FILE="$CLEAN_ARGS"
fi # timeout: 5000
TODAY=$(date +%Y-%m-%d)
```

`DIRECT_PATH_MODE=true` only valid when `REPLY_MODE=true` — if combined without `--reply`, Step 2 prints error and stops.

## Step 2: Reply-mode fast-path (only when `REPLY_MODE=true`)

Skip when `REPLY_MODE=false` and `DIRECT_PATH_MODE=false`.

**Direct report path** (`DIRECT_PATH_MODE=true` — checked first):

- `REPLY_MODE=false` → use `AskUserQuestion`: "A report path was passed without `--reply`. Did you mean `/analyse <path.md> --reply`?" Options: (a) "Yes — continue with `--reply` mode" → set `REPLY_MODE=true` and proceed; (b) "No — analyse a thread instead" → print usage hint (`/analyse <N> | health | ecosystem`) and stop.
- `REPLY_MODE=true` and file missing (`[ ! -f "$REPORT_FILE" ]`) → print `Error: report not found: $REPORT_FILE` and stop.
- `REPLY_MODE=true` and file exists → print `[direct] using $REPORT_FILE` → skip to Step 7. Don't run auto-detection fast-path below.

Remaining fast-path logic (TODAY, REPORT_FILE auto-construction, drift check) only runs when `DIRECT_PATH_MODE=false`.

When `REPLY_MODE=true`, check if fresh report already exists before any API calls:

```bash
REPORT_FILE=".reports/analyse/thread/output-analyse-thread-$CLEAN_ARGS-$TODAY.md"
DRIFT=false
FAST_PATH=false
FAST_PATH_TENTATIVE=false

if [ -f "$REPORT_FILE" ]; then
    REPORT_MTIME=$(stat -f %m "$REPORT_FILE" 2>/dev/null || stat -c %Y "$REPORT_FILE")  # timeout: 5000
    FAST_PATH_TENTATIVE=true  # drift check deferred to Step 4 — type must be known first
fi
```

- `FAST_PATH_TENTATIVE=true` → continue to Steps 3–4 for type detection and type-aware drift check. If no new activity confirmed there: `FAST_PATH=true` → print `[resume] reusing existing report for #$CLEAN_ARGS` → jump to Step 7.
- `FAST_PATH_TENTATIVE=false` (report missing) → continue to Step 3.

## Step 3: Cache layer (numeric arguments only)

Check local cache before API calls — prevents redundant fetches, avoids GitHub rate limits when re-analysing same item same day.

```bash
CACHE_DIR=".cache/gh"
CACHE_FILE="$CACHE_DIR/$CLEAN_ARGS-$TODAY.json"
mkdir -p "$CACHE_DIR" # timeout: 5000
```

**Cache hit** — if `$CACHE_FILE` exists:

- Read `type`, `item`, `comments` fields from JSON; `TYPE` is now known
- Skip all primary `gh` item fetches in `modes/thread.md`
- Print `[cache] #$CLEAN_ARGS ($TODAY)` as one-line status note
- Still run wide-net searches (dynamic — never cached)
- `FAST_PATH_TENTATIVE=true`: run lightweight drift check now that `TYPE` is known, then skip Step 4 type-detection API calls:

```bash
# Cache hit + FAST_PATH_TENTATIVE: check current GitHub state (cache data is stale)
if [ "$TYPE" = "discussion" ]; then
    UPDATED_AT=$(gh api graphql \
        -f query='query($owner:String!,$repo:String!,$number:Int!){repository(owner:$owner,name:$repo){discussion(number:$number){updatedAt}}}' \
        -f owner='{owner}' -f repo='{repo}' -F number=$CLEAN_ARGS \
        --jq '.data.repository.discussion.updatedAt' 2>/dev/null)  # timeout: 6000
else
    UPDATED_AT=$(gh api "repos/{owner}/{repo}/issues/$CLEAN_ARGS" --jq '.updated_at' 2>/dev/null)  # timeout: 6000
fi
UPDATED_TS=$(date -d "$UPDATED_AT" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$UPDATED_AT" +%s 2>/dev/null)  # timeout: 5000 — macOS/Linux portable
[ "$UPDATED_TS" -gt "$REPORT_MTIME" ] && DRIFT=true
[ "$DRIFT" = "false" ] && FAST_PATH=true && echo "[resume] reusing existing report for #$CLEAN_ARGS"
```

`FAST_PATH=true` → skip to Step 7. `DRIFT=true` → continue (full re-analysis from cached data).

**Cache miss** — after fetching in `modes/thread.md`, write:

```bash
jq -n \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg type "$TYPE" \
    --argjson number "$CLEAN_ARGS" \
    --argjson item "$ITEM" \
    --arg comments "$COMMENTS" \
    '{"ts":$ts,"type":$type,"number":$number,"item":$item,"comments":$comments}' \
    >"$CACHE_FILE" # timeout: 5000
```

**Stale cache** — file for same number but earlier date ignored. Old files left in place — small, provide audit history. Prune files older than 30 days: `find .cache/gh -mtime +30 -delete` # safe to delete — cache is regenerable; no confirmation needed

Cache applies to: issue/PR/discussion primary fetch and comments. Cache does NOT apply to: `gh issue list`, `gh pr list`, `gh pr checks`, `gh pr diff`, discussion list queries, health/ecosystem modes.

## Step 4: Auto-Detection (numeric arguments only)

Issues, PRs, discussions share unified running index — given number is exactly one type. Cache hit: read `TYPE` and `ITEM` from `$CACHE_FILE` — skip `gh` calls below.

Cache miss:

```bash
# 4a: try the issues API (covers both issues and PRs)
ITEM=$(gh api "repos/{owner}/{repo}/issues/$CLEAN_ARGS" 2>/dev/null) # timeout: 6000

if [ -n "$ITEM" ]; then
    TYPE=$(echo "$ITEM" | jq -r 'if .pull_request then "pr" else "issue" end')  # timeout: 5000
    # Drift check — updated_at already in $ITEM; no extra API call
    if [ "$FAST_PATH_TENTATIVE" = "true" ]; then
        UPDATED_AT=$(echo "$ITEM" | jq -r '.updated_at' 2>/dev/null)
        UPDATED_TS=$(date -d "$UPDATED_AT" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$UPDATED_AT" +%s 2>/dev/null)  # timeout: 5000 — macOS/Linux portable
        [ "$UPDATED_TS" -gt "$REPORT_MTIME" ] && DRIFT=true
        [ "$DRIFT" = "false" ] && FAST_PATH=true && echo "[resume] reusing existing report for #$CLEAN_ARGS"
    fi
else
    # 4b: try discussions via GraphQL — fetch updatedAt in same query; no extra call for drift check
    DISC_JSON=$(gh api graphql -f query='
    query($owner:String!,$repo:String!,$number:Int!){
      repository(owner:$owner,name:$repo){
        discussion(number:$number){ title updatedAt }
      }
    }' -f owner='{owner}' -f repo='{repo}' -F number=$CLEAN_ARGS 2>/dev/null)  # timeout: 6000
    DISC_TITLE=$(echo "$DISC_JSON" | jq -r '.data.repository.discussion.title // empty' 2>/dev/null)
    if [ -n "$DISC_TITLE" ]; then
        TYPE="discussion"
        # Drift check — updatedAt from same GraphQL response; no extra API call
        if [ "$FAST_PATH_TENTATIVE" = "true" ]; then
            UPDATED_AT=$(echo "$DISC_JSON" | jq -r '.data.repository.discussion.updatedAt' 2>/dev/null)
            UPDATED_TS=$(date -d "$UPDATED_AT" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$UPDATED_AT" +%s 2>/dev/null)  # timeout: 5000 — macOS/Linux portable
            [ "$UPDATED_TS" -gt "$REPORT_MTIME" ] && DRIFT=true
            [ "$DRIFT" = "false" ] && FAST_PATH=true && echo "[resume] reusing existing report for #$CLEAN_ARGS"
        fi
    else
        TYPE="unknown"
    fi
fi
# unknown → use AskUserQuestion: "Item #$CLEAN_ARGS was not found on GitHub. What did you want to analyse?" Options: (a) "A different issue or PR number" → ask for the correct number, (b) "Repo health overview" → re-run as `health` mode, (c) "Stop" → print usage hint and stop

# FAST_PATH=true (set above): jump to Step 7. FAST_PATH=false: continue to Step 5.
```

## Step 5: Mode dispatch

Read `plugins/oss/skills/analyse/modes/<mode>.md` and execute all steps defined there.

| Argument | Mode file |
| --- | --- |
| number (any type) | `modes/thread.md` |
| `health` | `modes/health.md` |
| `ecosystem` | `modes/ecosystem.md` |

## Step 6: Reply gate — STOP CHECK

**Run this step before Confidence block regardless of `--reply` mode.**

`REPLY_MODE=true`: response incomplete until Step 7 done and reply file written. No Confidence block here — proceed to Step 7.

`REPLY_MODE=false` — do NOT proceed to Step 7. Execute both sub-steps below:

### 6a — Follow-up gate

Call `AskUserQuestion` tool — do NOT write options as plain text first. Options depend on mode:

**Thread mode** (`$CLEAN_ARGS` is a number):
- question: "What next?"
- (a) label: `/develop:fix` — description: diagnose and fix the reported issue
- (b) label: `/develop:feature` — description: implement as new feature
- (c) label: `draft reply` — description: run `/oss:analyse $CLEAN_ARGS --reply` to shepherd a contributor-facing reply
- (d) label: `skip` — description: no action

**Health / ecosystem mode** (`$CLEAN_ARGS` is `health` or `ecosystem`):
- question: "What next?"
- (a) label: `/oss:analyse <N> --reply` — description: draft a reply for a specific thread
- (b) label: `/oss:review <N>` — description: full code review for a specific PR
- (c) label: `skip` — description: no action

### 6b — Confidence block

End with `## Confidence` block per CLAUDE.md output standards.

## Step 7: Draft contributor reply (only when --reply, thread mode only)

Report at `$REPORT_FILE` guaranteed to exist — either reused via fast-path (Step 2, `FAST_PATH=true`) or freshly written by Step 5.

Read `$_OSS_SHARED/shepherd-reply-protocol.md` — apply invocation pattern and terminal summary format.

Spawn with:
- Report path: `$REPORT_FILE`
- Item number: `$CLEAN_ARGS`
- Thread context: also fetch `gh issue view $CLEAN_ARGS --comments` (or equivalent GraphQL for discussions) if not already in report
- Output path: `.reports/analyse/thread/output-reply-thread-$CLEAN_ARGS-$(date +%Y-%m-%d).md`
- Note: shepherd runs in forked context — all required context must be self-contained in prompt

If `DRIFT=true`: append `[analysis refreshed — new activity since last report]` to terminal summary.

**Health monitoring** (CLAUDE.md §8): Agent spawns synchronous — Claude awaits natively. On timeout (`$HARD_CUTOFF` seconds): read `tail -100` of expected reply path; if none, use `{"verdict":"timed_out"}`; surface with ⏱. Never silently omit.

End response with `## Confidence` block per CLAUDE.md — always **absolute last thing**.

</workflow>

<notes>

- Mode files live in `plugins/oss/skills/analyse/modes/` — one file per mode, fully self-contained
- `modes/thread.md` handles all three thread types (issue, PR, discussion) via internal branching
- Always use `gh` CLI — never hardcode repo URLs
- Run `gh auth status` first if commands fail; user may need to authenticate
- For closed items, note resolution so history is useful
- Don't post responses without explicit user instruction — only draft them
- **Forked context**: skill runs with `context: fork` — no access to current conversation history. All required context must be in skill argument or prompt.
- **`--reply` drafts only** — shepherd produces a draft file; it does NOT auto-post to GitHub. User posts manually. Write access to the repo is not required to use `--reply`; it is required only if user subsequently posts the draft via `gh issue comment` or `gh pr comment`.
- Follow-up chains:
  - Issue with confirmed bug → `/develop:fix` to diagnose, reproduce with test, apply targeted fix
  - Issue is feature request → `/develop:feature` for TDD-first implementation
  - PR with quality concerns → `/oss:review` for comprehensive multi-agent code review
  - Draft responses → use `--reply` to auto-draft via shepherd; or invoke shepherd manually

</notes>

---
name: review
description: Multi-agent code review of local files, directories, or the current git diff covering architecture, tests, performance, docs, lint, security, and API design.
argument-hint: '[file|dir]'
allowed-tools: Read, Write, Bash, Grep, Agent, TaskCreate, TaskUpdate
context: fork
model: opus
effort: high
---

<objective>

Perform a comprehensive code review of local files or the current working-tree diff by spawning specialized sub-agents in parallel and consolidating their findings into structured feedback with severity levels.

</objective>

<inputs>

- **$ARGUMENTS**: optional file path or directory to review.
  - If a path is given: review those files
  - If omitted: review the current git diff (`git diff HEAD` — staged + unstaged changes vs HEAD)
  - **Scope**: this skill reviews Python source code only. If the input is a non-Python file (YAML, JSON, shell script, etc.), state that it is out of scope and suggest the appropriate tool — do not produce findings.

</inputs>

<constants>
<!-- Background agent health monitoring (CLAUDE.md §8) — applies to Step 3 parallel agent spawns -->
MONITOR_INTERVAL=300   # 5 minutes between polls
HARD_CUTOFF=900        # 15 minutes of no file activity → declare timed out
EXTENSION=300          # one +5 min extension if output file explains delay
</constants>

<workflow>

**Task hygiene**: Before creating tasks, call `TaskList`. For each found task:

- status `completed` if the work is clearly done
- status `deleted` if orphaned / no longer relevant
- keep `in_progress` only if genuinely continuing

**Task tracking**: per CLAUDE.md, create tasks (TaskCreate) for each major phase. Mark in_progress/completed throughout. On loop retry or scope change, create a new task.

## Step 1: Identify scope

```bash
if [ -n "$ARGUMENTS" ]; then
    # Path given directly — collect Python files under it
    TARGET="$ARGUMENTS"
    echo "Reviewing: $TARGET"
else
    # No argument — review current working-tree diff vs HEAD
    git diff HEAD --name-only  # timeout: 3000
fi
```

Filter to Python files only. If no Python files are found in the target, report "no Python files to review" and stop.

### Scope pre-check

Before spawning agents, classify the diff:

- Count files changed, lines added/removed, new classes/modules introduced
- Classify as: **FIX** (\<3 files, \<50 lines), **REFACTOR** (no new public API), **FEATURE** (new public API or module), or **MIXED**
- **Complexity smell**: if 8+ files changed, note in the report header

Use classification to skip optional agents:

- FIX scope → skip Agent 3 (perf-optimizer) and Agent 6 (solution-architect)
- REFACTOR scope → skip Agent 6 (solution-architect)
- FEATURE/MIXED → spawn all agents

### Structural context (codemap, if installed)

```bash
PROJ=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null) || PROJ=$(basename "$PWD")
if command -v scan-query >/dev/null 2>&1 && [ -f ".cache/scan/${PROJ}.json" ]; then
    CHANGED_MODS=$(git diff HEAD --name-only | grep '\.py$' | sed 's|^src/||;s|\.py$||;s|/|.|g' | grep -v '__init__$')  # timeout: 3000
    scan-query central --top 5 2>/dev/null  # timeout: 5000
    for mod in $CHANGED_MODS; do scan-query rdeps "$mod" 2>/dev/null; done  # timeout: 5000
fi
```

If codemap returns results: prepend a `## Structural Context (codemap)` block to the **Agent 1 (foundry:sw-engineer)** spawn prompt. Include:

- Each changed module's `rdep_count` — label as **high risk** (>20), **moderate** (5–20), or **low** (<5)
- `central --top 5` for project-wide blast-radius reference

Agent 1 uses this to prioritize: modules with high `rdep_count` warrant deeper scrutiny on API compatibility, error handling, and behavioural correctness — downstream callers outside the diff are not otherwise visible to the reviewer. If codemap is not installed or index absent, skip silently.

## Step 2: Codex co-review

Set up the run directory:

```bash
TIMESTAMP=$(date -u +%Y-%m-%dT%H-%M-%SZ)
RUN_DIR=".reports/review/$TIMESTAMP"
mkdir -p "$RUN_DIR"  # timeout: 5000
```

Check availability:

```bash
claude plugin list 2>/dev/null | grep -q 'codex@openai-codex' && echo "codex (openai-codex) available" || echo "⚠ codex (openai-codex) not found — skipping co-review"  # timeout: 15000
```

If Codex is available:

```bash
CODEX_OUT="$RUN_DIR/codex.md"
Agent(subagent_type="codex:codex-rescue", prompt="Adversarial review of $TARGET: look for bugs, missed edge cases, incorrect logic, and inconsistencies with existing code patterns. Read-only: do not apply fixes. Write findings to $RUN_DIR/codex.md.")
```

After Codex writes `$RUN_DIR/codex.md`, extract a compact seed list (≤10 items, `[{"loc":"file:line","note":"..."}]`) to inject into agent prompts in Step 3 as pre-flagged issues to verify or dismiss. If Codex was skipped or found nothing, proceed with an empty seed.

## Step 3: Spawn sub-agents in parallel

**File-based handoff**: read `.claude/skills/_shared/file-handoff-protocol.md`. The run directory was created in Step 2 (`$RUN_DIR`).

<!-- Note: $RUN_DIR must be pre-expanded before inserting into spawn prompts — replace with the literal path string computed in Step 2 setup. -->

Replace `$RUN_DIR` in the spawn prompt below with the actual path from Step 2.

Resolve the oss:review checklist path (version-agnostic):

```bash
OSS_ROOT=$(jq -r 'to_entries[] | select(.key | test("oss@")) | .value.installPath' ~/.claude/plugins/installed_plugins.json 2>/dev/null | head -1)  # timeout: 5000
REVIEW_CHECKLIST="${OSS_ROOT}/skills/review/checklist.md"
[ -f "$REVIEW_CHECKLIST" ] && echo "Checklist: $REVIEW_CHECKLIST" || echo "⚠ oss:review checklist not found — Agent 1 will skip checklist patterns"  # timeout: 5000
```

Replace `$REVIEW_CHECKLIST` in the Agent 1 and consolidator spawn prompts below with the resolved path.

Launch agents simultaneously with the Agent tool (security augmentation is folded into Agent 1 — not a separate spawn; Agent 6 is optional). Every agent prompt must end with:

> "Write your FULL findings (all sections, Confidence block) to `$RUN_DIR/<agent-name>.md` using the Write tool — where `<agent-name>` is e.g. `foundry:sw-engineer`, `foundry:qa-specialist`, `foundry:perf-optimizer`, `foundry:doc-scribe`, `foundry:linting-expert`, `foundry:solution-architect`. Then return to the caller ONLY a compact JSON envelope on your final line — nothing else after it: `{\"status\":\"done\",\"findings\":N,\"severity\":{\"critical\":0,\"high\":1,\"medium\":2},\"file\":\"$RUN_DIR/<agent-name>.md\",\"confidence\":0.88}`"

**Agent 1 — foundry:sw-engineer**: Review architecture, SOLID adherence, type safety, error handling, and code structure. Check for Python anti-patterns (bare `except:`, `import *`, mutable defaults). Flag blocking issues vs suggestions.

**Error path analysis** (for new/changed code in the diff): For each error-handling path introduced or modified, produce a table:

| Location | Exception/Error | Caught? | Action if caught | User-visible? |
| -------- | --------------- | ------- | ---------------- | ------------- |

Flag rules:

- Caught=No + User-visible=Silent → **HIGH** (unhandled error path)
- Caught=Yes + Action=`pass` or bare `except` → **MEDIUM** (swallowed error)
- Cap at 15 rows. Focus on new/changed paths only, not the entire codebase.

Read the review checklist (use the Read tool to read `$REVIEW_CHECKLIST`) — apply CRITICAL/HIGH patterns as severity anchors. Respect the suppressions list.

**Agent 2 — foundry:qa-specialist**: Audit test coverage. Identify untested code paths, missing edge cases, and test quality issues. Check for ML-specific issues (non-deterministic tests, missing seed pinning). List the top 5 tests that should be added. Also check explicitly for missing tests in these patterns (these are GT-level findings, not afterthoughts):

- Concurrent access to shared state (when locks or shared variables are present)
- Error paths: calling methods in wrong order (e.g., `log()` before `start()`)
- Resource cleanup on exception (file handles, database connections)
- Boundary conditions for division, empty collections, and zero-count inputs
- Type-coercion boundary inputs: for functions that parse or convert strings to typed values (`int()`, `float()`, `datetime`), test with inputs that are near-valid (float strings for int parsers, empty strings, very large values, `None`) — these are common omissions.

**Consolidation rule**: Report each test gap as one finding with a concise list of test scenarios, not as separate findings per scenario. Format: "Missing tests for `parse_numeric()`: empty string, None, very large integers, float-string for int parser." This keeps the test coverage section actionable and prevents the section from exceeding 5 items.

**Agent 3 — foundry:perf-optimizer**: Analyze code for performance issues. Look for algorithmic complexity issues, Python loops that should be NumPy/torch ops, repeated computation, unnecessary I/O. For ML code: check DataLoader config, mixed precision usage. Prioritize by impact.

**Agent 4 — foundry:doc-scribe**: Check documentation completeness. Find public APIs without docstrings, missing Google style sections, outdated README sections, and CHANGELOG gaps. Verify examples actually run.

- **Algorithmic accuracy check**: For functions that compute mathematical results (moving averages, statistics, transforms, distances), verify that the docstring's behavioral claims match what the implementation actually computes. If the implementation deviates from the conventional definition, flag as MEDIUM — the docstring must document the deviation, not just state the standard definition. **Deprecation check**: Always check whether datetime, os.path, or other stdlib functions used in the code have been deprecated in Python 3.10+ (e.g., `datetime.utcnow()` deprecated in 3.12, `os.path` vs `pathlib`). Flag deprecated stdlib usage as MEDIUM with the replacement.

**Agent 5 — foundry:linting-expert**: Static analysis audit. Check ruff and mypy would pass. Identify type annotation gaps on public APIs, suppressed violations without explanation, and any missing pre-commit hooks. Flag mismatched target Python version.

**Security augmentation (conditional — fold into Agent 1 prompt, not a separate spawn)**: If the target touches authentication, user input handling, dependency updates, or serialization — add to the foundry:sw-engineer agent prompt (Agent 1 above): check for SQL injection, XSS, insecure deserialization, hardcoded secrets, and missing input validation. Run `pip-audit` if dependency files changed. Skip if the change is purely internal refactoring.

**Agent 6 — foundry:solution-architect (optional, for changes touching public API boundaries)**: If the target touches `__init__.py` exports, adds/modifies Protocols or ABCs, changes module structure, or introduces new public classes — evaluate API design quality, coupling impact, and backward compatibility. Skip if changes are internal implementation only.

**Health monitoring** (CLAUDE.md §8): Agent calls are synchronous — Claude awaits each response natively; no Bash checkpoint polling is available. If any agent does not return within `$HARD_CUTOFF` seconds, use the Read tool to surface any partial results already written to `$RUN_DIR` and continue with what was found; mark timed-out agents with ⏱ in the final report. Grant one `$EXTENSION` extension if the output file tail explains the delay. Never silently omit timed-out agents.

## Step 4: Cross-validate critical/blocking findings

Read and follow the cross-validation protocol from `.claude/skills/_shared/cross-validation-protocol.md`. If that file is not present, skip Step 4.

**Skill-specific**: use the **same agent type** that raised the finding as the verifier (e.g., foundry:sw-engineer verifies foundry:sw-engineer's critical finding).

## Step 5: Consolidate findings

Before constructing the output path, extract the current branch and date: `BRANCH=$(git branch --show-current 2>/dev/null | tr '/' '-' || echo 'main')` `DATE=$(date +%Y-%m-%d)`

Spawn a **foundry:sw-engineer** consolidator agent with this prompt:

> "Read all finding files in `$RUN_DIR/` (agent files: `sw-engineer.md`, `qa-specialist.md`, `perf-optimizer.md`, `doc-scribe.md`, `linting-expert.md`, `solution-architect.md`, and `codex.md` if present — skip any that are missing). Read `.claude/skills/review/checklist.md` using the Read tool and apply the consolidation rules (signal-to-noise filter, annotation completeness, section caps). Apply the precision gate: only include findings with a concrete, actionable location (function, line range, or variable name). Apply the finding density rule: for modules under 100 lines, aim for ≤10 total findings. Rank findings within each section by impact (blocking > critical > high > medium > low). For `codex.md`: include its unique findings under a `### Codex Co-Review` section; deduplicate against agent findings (same file:line raised by both → keep the agent version, mark as 'also flagged by Codex'). Parse each agent's `confidence` from its envelope; assign `codex` a fixed confidence of 0.75. Write the consolidated report to `.temp/output-review-$BRANCH-$DATE.md` using the Write tool. Return ONLY a one-line summary: `verdict=<APPROVE|REQUEST_CHANGES|NEEDS_WORK> | findings=N | critical=N | high=N | file=.temp/output-review-$BRANCH-$DATE.md`"

Main context receives only the one-liner verdict.

```
## Code Review: [target]

### [blocking] Critical (must fix before merge)
- [bugs, security issues, data corruption risks]
- Severity: CRITICAL / HIGH

### Architecture & Quality
- [sw-engineer findings]
- [blocking] issues marked explicitly
- [nit] suggestions marked explicitly

### Test Coverage Gaps
- [qa-specialist findings — top 5 missing tests]
- For ML code: non-determinism or missing seed issues

### Performance Concerns
- [perf-optimizer findings — ranked by impact]
- Include: current behavior vs expected improvement

### Documentation Gaps
- [doc-scribe findings]
- Public API without docstrings listed explicitly

### Static Analysis
- [linting-expert findings — ruff violations, mypy errors, annotation gaps]

### API Design (if applicable)
- [solution-architect findings — coupling, API surface, backward compat]
- Public API changes: [intentional / accidental leak]
- Deprecation path: [provided / missing]

### Codex Co-Review
(omit section if Codex was unavailable or found no unique issues)
- [unique findings from codex.md not already captured by agents above]
- Duplicate findings (same location as agent finding): omitted — see agent section

### Recommended Next Steps
1. [most important action]
2. [second most important]
3. [third]

### Review Confidence
| Agent | Score | Label | Gaps |
|-------|-------|-------|------|
<!-- Replace with actual agent scores for this review -->

**Aggregate**: min 0.N / median 0.N
```

After parsing confidence scores: if any agent scored < 0.7, prepend **⚠ LOW CONFIDENCE** to that agent's findings section and explicitly state the gap. Do not silently drop uncertain findings.

<!-- Extended Fields live in .claude/skills/_shared/terminal-summaries.md — if that file is absent, omit the extended fields block -->

Read the compact terminal summary template from `.claude/skills/_shared/terminal-summaries.md` — use the **PR Summary** template. Replace `[entity-line]` with `Review — [target]` and replace `[skill-specific path]` with `.temp/output-review-$BRANCH-$DATE.md`. Print this block to the terminal.

After printing to the terminal, also prepend the same compact block to the top of the report file using the Edit tool.

## Step 6: Delegate implementation follow-up (optional)

After consolidating findings, identify tasks from the review that Codex can implement directly — not style violations (those are handled by pre-commit hooks), but work that requires writing meaningful code or documentation grounded in the actual implementation.

**Delegate to Codex when you can write an accurate, specific brief:**

- Public functions with no docstrings — read the implementation first, then describe what each one does so Codex can write a real 6-section docstring, not a placeholder
- Missing test coverage for a concrete, well-defined behaviour — describe the exact scenario to test
- A consistent rename identified across multiple files — name both the old and new symbol and why it was flagged

**Do not delegate — these require human judgment:**

- Architectural issues, logic errors, security vulnerabilities, or behavioural changes
- Any task where you cannot write a precise description without guessing

Read `.claude/skills/_shared/codex-delegation.md` and apply the delegation criteria defined there.

Only print a `### Codex Delegation` section to the terminal when tasks were actually delegated — omit entirely if nothing was delegated.

End your response with a `## Confidence` block per CLAUDE.md output standards.

</workflow>

<notes>

- Critical issues are always surfaced regardless of scope
- Skip sections where no issues were found — don't pad with "looks good". When reviewing isolated code without git context, skip Performance Concerns sections unless the code itself contains evidence of performance issues.
- **Signal-to-noise gate**: When a function or class has ≤50 lines and only 1–2 ground-level issues (critical/high), do not add more than 2 medium/low findings beyond them. Surface the remainder as `[nit]` in a dedicated "Minor Observations" section rather than elevating them to the same tier as high-severity findings.
- **Follow-up chains**:
  - `[blocking]` bugs or regressions → `/develop:fix` to reproduce with test and apply targeted fix
  - Structural or quality issues → `/develop:refactor` for test-first improvements
  - Security findings in auth/input/deps → run `pip-audit` for dependency CVEs; address OWASP issues inline via `/develop:fix`
  - Mechanical issues beyond what Step 5 flagged → `/codex:codex-rescue <task>` to delegate
  - For contributor-facing review of a GitHub PR → use `/oss:review <PR#>` instead

</notes>

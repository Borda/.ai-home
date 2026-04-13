# Plan Mode

Analysis-only mode that produces a structured plan without writing any code. Use this to understand scope, risks, and effort before committing to a full `/develop feature|fix|refactor`.

## Step 1: Classify and scope

Determine the task type and affected surface.

Spawn a **sw-engineer** agent with the full goal text from `$ARGUMENTS`. The agent should:

- Classify the task as `feature`, `fix`, or `refactor`
- Identify affected files and modules (search the codebase — do not guess)
- Assess complexity: small (1–3 files, self-contained), medium (4–8 files or 1–2 modules), large (cross-module, API changes, or 3+ modules)
- List risks: breaking changes, missing tests, unclear requirements, external dependencies
- Note any complexity smells: ambiguous goal, scope creep risk, missing reproduction case, directory-wide refactor without explicit goal

The agent returns its findings inline (no file handoff needed — output is short).

## Step 2: Structured plan

Derive a filename slug from the goal: take the first 4–5 meaningful words, lowercase, hyphen-separated (e.g. `"improve caching in data loader"` → `plan_improve-caching-data-loader.md`). Write the plan to `.plans/active/<slug>` (create or overwrite). Store the full path as `PLAN_FILE` — used in Steps 3 and Final output.

```markdown
# Plan: <goal>

## Brief

*[Generated after agent review — see below]*

---

## Full Plan

**Classification**: feature | fix | refactor
**Complexity**: small | medium | large
**Date**: <YYYY-MM-DD>

### Goal

<One-paragraph restatement of the goal in concrete terms — what changes, what doesn't.>

### Affected files

- `path/to/file.py` — reason
- `path/to/other.py` — reason

### Risks

- <risk 1>
- <risk 2>

### Suggested approach

1. <Step 1>
2. <Step 2>
3. <Step 3>
...

### Follow-up command

/develop <classification> <original goal text>
```

## Step 3: Agent feasibility review

Spawn the execution agents for this classification in parallel. Each reads `<PLAN_FILE>` and returns **only** a compact JSON — no prose, no analysis:

- **feature**: sw-engineer, qa-specialist, linting-expert
- **fix**: sw-engineer, qa-specialist
- **refactor**: sw-engineer, linting-expert, qa-specialist

Each agent receives only the plan file path and their role — no conversation history, no unrelated context. Prompt (substitute `<ROLE>` and `<PLAN_FILE>`):

> "Read `<PLAN_FILE>`. Review the plan from your perspective as `<ROLE>`. Flag any domain-specific concerns, risks, or blockers you see. Can you execute your part autonomously without further user input? Return only: `{\"a\":\"<ROLE>\",\"ok\":true|false,\"blockers\":[\"...\"],\"q\":[\"...\"],\"concerns\":[\"...\"]}`"

Agents return inline (verdicts are ~150 bytes — no file handoff needed). Collect all results:

- All `ok: true`, empty `blockers`, `q`, and `concerns` → note `✓ agents ready` in final output and proceed
- Any `ok: false`, non-empty `blockers` or `q` → enter the **internal resolution loop** below before surfacing anything to the user
- Non-empty `concerns` with `ok: true` → surface as advisory notes in the final output (not blockers, but domain-specific flags the user should know before starting)

### Internal resolution loop (max 3 iterations)

For each blocker or open question:

1. **Attempt autonomous resolution** — search the codebase, read relevant files, re-read the goal. Also search the web for similar issues and established patterns (e.g. known library constraints, common implementation trade-offs) — use WebSearch for this. If the answer can be determined from any of these sources, update `<PLAN_FILE>` and mark the item resolved.
2. **Re-query the raising agent** — send only the resolved item: `{"a":"<ROLE>","resolved":"<item>","answer":"<resolution>"}`. If the agent returns `ok: true` → resolved; remove from the blockers list.
3. After all resolvable items are cleared, re-check: if all agents are now `ok: true` → `✓ agents ready`.

**Escalate to user only what cannot be resolved autonomously** — a blocker requires user input when: it depends on a business decision, an undocumented external constraint, a missing credential/secret, or a genuine ambiguity in the goal that has two equally valid interpretations.

For each escalated item, present:

- **Issue**: one sentence — what is blocking or unclear
- **Alternatives**: 2–3 concrete options with trade-offs
- **Recommendation**: which option to pick and why

Do not escalate: items resolvable by reading the codebase, items that are risks (not blockers), or items already addressed in the plan.

## Final output

Compose the brief — this is the compact human-readable summary of the plan after all agent input has been incorporated:

```
<One-sentence summary of what the plan achieves and the main approach.>

Classification : <feature|fix|refactor>
Complexity     : <small|medium|large>
Affected files : N files across M modules
Key risks      : <one-liner or "none">
Agent review   : ✓ agents ready (<N> corrections incorporated)  |  ⚠ see below

<Steps table — use the format that best fits the complexity:>
- Simple: | # | Step |
- Staged/large: | # | Stage | What changes | Stop condition |
- Fix: | # | Action | Target | Verification |

Advisory notes from agents (omit table if none):

| Agent | Note |
|-------|------|
| <role> | <concern> |

Co-review corrections applied (<N> agents, omit table if none):

| Agent | Location | Change |
|-------|----------|--------|
| <agent> | <file or step> | <what changed> |
```

**Write the brief into `<PLAN_FILE>`**: replace the `*[Generated after agent review — see below]*` placeholder in `## Brief` with the composed brief content. The file now contains both the brief and the full plan.

**Print to terminal**:

```
Plan → <PLAN_FILE>

<brief content exactly as written to the file>

→ /develop <classification> <goal> when ready
```

If unresolved items were escalated, print each after the brief:

```
⚠ Issue: <one sentence>
  Alternatives: (a) ... (b) ... (c) ...
  Recommendation: <option> — <reason>
```

Wait for user input before printing `→ /develop ...`.

No quality stack, no Codex pre-pass, no review loop. Exit after printing the summary.

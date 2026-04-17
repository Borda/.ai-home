# 🛠️ develop — Claude Code Plugin

Development workflow plugin: six slash-command skills for scope planning, feature development, bug fixing, refactoring, debugging, and code review — all built on a validate-first principle that proves the problem exists before writing a single line of solution.

> [!NOTE] Requires the `foundry` plugin for base agents. Install order does not matter.

## 🎯 Why

Most development mistakes happen before the first keystroke: implementing a feature nobody verified is needed, fixing a bug by guessing rather than reproducing it, refactoring without a safety net that catches regressions. The cost is not the wrong code — it's the downstream review, the revert, the second PR.

`develop` enforces a validation gate before every code change:

- **Plan mode** scopes the work before committing to it — analyses the codebase, estimates complexity, surfaces hidden dependencies, produces a structured plan
- **Feature mode** writes a failing demo test first — a TDD contract that pins the expected behaviour before any implementation begins; if you cannot write the test, the feature is underspecified
- **Fix mode** reproduces the bug with a failing regression test first — if you cannot reproduce it, you cannot verify the fix; the test becomes permanent protection against the same regression
- **Refactor mode** builds a characterization test suite first — tests that document what the code already does, creating a safety net that catches any behaviour change during restructuring
- **Debug mode** investigates before proposing — reads logs, traces call paths, ranks hypotheses by evidence; no blind guesses
- **Review mode** runs six specialist agents across architecture, tests, performance, docs, lint, and security — against local files or the current git diff; no GitHub PR required

> [!IMPORTANT] Every code-changing mode (feature, fix, refactor) closes with the same quality stack: `linting-expert` → `qa-specialist` → Codex pre-pass. `/develop:review` is the quality gate itself — use it to review the current diff before committing.

## 💡 Key Principles

- **Validate before implementing** — demo test (feature), regression test (fix), characterization test (refactor); no production code before the validation artifact exists
- **Reproduce before fixing** — a fix without a failing test is a guess; the test is the proof the fix is correct and stays correct
- **Minimal change** — fix mode applies the smallest change that makes the regression test pass; no opportunistic cleanup, no adjacent improvements
- **No adjacent bug fixing** — if a different bug is discovered during a fix, it is documented as an observation and handled in a separate session; one fix per session prevents conflated history
- **Quality stack is non-negotiable** — linting-expert → qa-specialist → Codex pre-pass runs on every mode completion; it cannot be skipped

## ⚡ Quick start

```bash
# Run from the directory that CONTAINS your Borda-AI-Home clone
claude plugin marketplace add ./Borda-AI-Home
claude plugin install develop@borda-ai-home
```

<details>
<summary>Install the full suite</summary>

```bash
claude plugin install foundry@borda-ai-home   # base agents — required first
claude plugin install oss@borda-ai-home
claude plugin install develop@borda-ai-home
claude plugin install research@borda-ai-home
```

</details>

> [!NOTE] Skills are always invoked with the `develop:` prefix: `/develop:plan`, `/develop:feature`, `/develop:fix`, `/develop:refactor`, `/develop:debug`, `/develop:review`.

## 🔁 How to Use

### Scope a large change before committing

```bash
/develop:plan "migrate auth from session tokens to JWTs"
```

### Implement a new feature

```bash
/develop:plan "add CSV export to the results API"   # scope it first
/develop:feature "add CSV export to the results API"
```

### Fix a reported bug

```bash
/develop:fix "KeyError in transform pipeline when input has null values"
/develop:fix 88                    # fix by GitHub issue number
```

### Refactor safely

```bash
/develop:refactor "extract data loading into a dedicated DataLoader class"
```

### Investigate a mystery failure

```bash
/develop:debug "intermittent timeout on /api/predict under load"
```

### Review current changes

```bash
/develop:review                          # review current git diff (staged + unstaged)
/develop:review src/mypackage/module.py  # review a specific file
/develop:review src/mypackage/           # review all Python files in a directory
```

### Team mode (parallel agents on the same task)

```bash
/develop:feature "add streaming response support" --team
/develop:fix "memory leak in batch inference" --team
```

> [!NOTE] `--team` spawns multiple `sw-engineer` + `qa-specialist` instances exploring the implementation space in parallel. Expect ~7× the token cost of plan mode; use for genuinely complex or ambiguous tasks.

## 🗺️ Overview

### 6 Development Modes

| Mode         | What It Solves                                                                               |
| ------------ | -------------------------------------------------------------------------------------------- |
| **plan**     | Scope analysis — codebase mapping, complexity estimate, hidden dependencies, structured plan |
| **feature**  | TDD-first implementation with review+fix loop — builds demo test before any production code  |
| **fix**      | Reproduce-first bug fixing — regression test must fail before the fix is written             |
| **refactor** | Test-first restructuring — characterization tests locked in before any production code moves |
| **debug**    | Investigation-first diagnosis — root cause confirmed before any fix is attempted             |
| **review**   | Six-agent parallel review of local files or current git diff; no GitHub PR needed            |

### Orchestration Flows

> [!NOTE] These flows document the skill implementations. If any divergence exists between this section and the skill files, the skill files are authoritative.

<details>
<summary><strong>`/develop:plan`</strong> — scope before commit</summary>

```
Step 1: sw-engineer (codebase analysis — read relevant files, map dependencies)
Step 2: solution-architect (scope assessment — complexity, hidden coupling, risk)
→ Structured plan with phases, estimated effort, and identified blockers
```

</details>

<details>
<summary><strong>`/develop:feature`</strong> — TDD contract first</summary>

```
Step 1: sw-engineer (codebase analysis — understand existing patterns and constraints)
Step 2: sw-engineer (demo test — failing test that defines the feature contract)
Step 2 review: in-context validation gate — test must be runnable and meaningful
Step 3: sw-engineer (implementation) + qa-specialist (parallel review)
Step 4: review+fix loop (max 3 cycles): sw-engineer → qa-specialist → linting-expert
Step 5: doc-scribe (docs update — docstrings, API references)
Quality stack: linting-expert → qa-specialist → Codex pre-pass
```

</details>

<details>
<summary><strong>`/develop:fix`</strong> — reproduce before fixing</summary>

```
Step 1: sw-engineer (root cause analysis — read logs, trace the failure path)
Step 2: sw-engineer (regression test that fails on the unfixed code)
Step 2 review: in-context validation gate — test must actually fail
Step 3: sw-engineer (minimal fix — smallest change that makes the test pass)
Step 4: review+fix loop (max 3 cycles)
Quality stack: linting-expert → qa-specialist → Codex pre-pass
```

</details>

<details>
<summary><strong>`/develop:refactor`</strong> — safety net first</summary>

```
Step 1: sw-engineer + linting-expert (coverage audit, parallel — find gaps before adding tests)
Step 2: qa-specialist (characterization tests — document existing behaviour)
Step 2 review: in-context validation gate — tests must pass on unmodified code
Step 3: sw-engineer (refactor — all characterization tests must remain green)
Step 4: review+fix loop (max 3 cycles)
Quality stack: linting-expert → qa-specialist → Codex pre-pass
```

</details>

<details>
<summary><strong>`/develop:debug`</strong> — investigation before prescription</summary>

```
Step 1: sw-engineer (gather signals — logs, tracebacks, failing tests, recent git changes)
Step 2: sw-engineer (rank hypotheses by evidence — eliminate before proposing)
Step 3: sw-engineer (targeted probe per hypothesis — confirm/rule-out each)
→ Confirmed root cause → hand off to /develop:fix or surface manual steps
```

</details>

<details>
<summary><strong>`/develop:review`</strong> — six-agent parallel review</summary>

```
Step 1: scope (path given → use it; omitted → git diff HEAD — staged + unstaged vs HEAD)
Step 2: Codex pre-pass (adversarial diff review — surfaces obvious issues first)
Step 3: 6 parallel agents — sw-engineer, qa-specialist, perf-optimizer,
         doc-scribe, solution-architect, linting-expert
→ sw-engineer consolidator reads all agent findings → ranked report
→ optional: Codex delegation for mechanical fixes (docstrings, missing tests)
```

</details>

### Quality Stack (all modes)

Every mode ends with the same three-layer gate:

1. **linting-expert** — ruff, mypy, pre-commit; zero tolerance for style violations
2. **qa-specialist** — test coverage, edge cases, OWASP Top 10 (auto-included)
3. **Codex pre-pass** — independent diff review before anything is considered done

## 📦 Plugin details

### Upgrade

```bash
cd Borda-AI-Home && git pull
claude plugin install develop@borda-ai-home
```

### Uninstall

```bash
claude plugin uninstall develop
```

### Structure

```
plugins/develop/
├── .claude-plugin/
│   └── plugin.json          ← manifest
└── skills/
    ├── plan/
    ├── feature/
    ├── fix/
    ├── refactor/
    ├── debug/
    └── review/
```

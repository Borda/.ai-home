# Fix Mode

Reproduce-first bug resolution. Capture the bug in a failing regression test, apply the minimal fix, then verify.

## Step 1: Understand the problem

Gather all available context about the bug:

```bash
# If issue number: fetch the full issue with comments
gh issue view <number> --comments
```

If an error message or pattern was provided: use the Grep tool (pattern `<error_pattern>`, path `.`) to search the codebase for the failing code path.

```bash
# If failing test: run it to capture the exact failure
python -m pytest <test_path> -v --tb=long 2>&1 | tail -40
```

Spawn a **sw-engineer** agent to analyze the failing code path and identify:

- The root cause (not just the symptom)
- The minimal code surface that needs to change
- Any related code that might be affected by the fix

## Step 2: Reproduce the bug

Create or identify a test that demonstrates the failure:

```bash
# If a failing test already exists — run it to confirm it fails
python -m pytest <test_file>::<test_name> -v --tb=short

# If no test exists — write a regression test that captures the bug
```

Spawn a **qa-specialist** agent to write the regression test if one doesn't exist:

- The test must **fail** against the current code (proving the bug exists)
- Use `pytest.mark.parametrize` if the bug affects multiple input patterns
- Keep the test minimal — exercise exactly the broken behavior
- Add a brief comment linking to the issue if applicable (e.g., `# Regression test for #123`)

**Gate**: the regression test must fail before proceeding. If it passes, the bug isn't properly captured — revisit Step 1.

## Step 3: Apply the fix

Make the minimal change to fix the root cause:

1. Edit only the code necessary to resolve the bug
2. Run the regression test to confirm it now passes:
   ```bash
   python -m pytest <test_file>::<test_name> -v --tb=short
   ```
3. Run the full test suite for the affected module:
   ```bash
   python -m pytest <test_dir> -v --tb=short
   ```
4. If any existing tests break: the fix has side effects — reconsider the approach

## Final Report

```
## Fix Report: <bug summary>

### Root Cause
[1-2 sentence explanation of what was wrong and why]

### Regression Test
- File: <test_file>
- Test: <test_name>
- Confirms: [what behavior the test locks in]

### Changes Made
| File | Change | Lines |
|------|--------|-------|
| path/to/file.py | description of fix | -N/+M |

### Test Results
- Regression test: PASS
- Full suite: PASS (N tests)
- Lint: clean

### Follow-up
- [any related issues or code that should be reviewed]

## Confidence
**Score**: [0.N]
**Gaps**: [e.g., could not reproduce locally, partial traceback only, fix not runtime-tested]
**Refinements**: N passes.
```

## Team Assignments

**When to use team mode**: root cause unclear after Step 1, OR bug spans 3+ modules.

- **Teammate 1–3 (sw-engineer x 2–3, model=opus)**: each investigates a distinct root-cause hypothesis independently

**Coordination:**

1. Lead broadcasts current evidence: `{bug: <description>, traceback: <key lines>}`
2. Each teammate investigates independently — claims a hypothesis
3. Lead facilitates cross-challenge between competing analyses
4. Lead synthesizes consensus root cause, then proceeds with Steps 2–3 (regression test, fix) alone

**Spawn prompt template:**

```
You are a sw-engineer teammate debugging: [bug description].
Read .claude/TEAM_PROTOCOL.md — use AgentSpeak v2 for inter-agent messages.
Your hypothesis: [hypothesis N]. Investigate ONLY this root cause.
Report findings to @lead using deltaT# or epsilonT# codes.
Compact Instructions: preserve file paths, errors, line numbers. Discard verbose tool output.
```

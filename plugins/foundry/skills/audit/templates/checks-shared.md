# Shared Checks (all scopes) — 17, 21, 4, 5, 9, 16, 15

______________________________________________________________________

## Check 12 — File length (context budget risk)

Thresholds: agents > 300 lines · skill SKILL.md > 600 lines · rules > 200 lines.

```bash
YEL='\033[1;33m'
GRN='\033[0;32m'
NC='\033[0m'
printf "%-52s %s\n" "FILE" "LINES"
for f in .claude/agents/*.md; do # timeout: 5000
    lines=$(wc -l <"$f" | tr -d ' ')
    [ "$lines" -gt 300 ] &&
    printf "${YEL}⚠ TOO LONG${NC}: agents/%s — %d lines (threshold: 300)\n" "$(basename "$f")" "$lines" ||
    printf "  %-50s %d\n" "agents/$(basename "$f")" "$lines"
done
for f in .claude/skills/*/SKILL.md; do
    lines=$(wc -l <"$f" | tr -d ' ')
    [ "$lines" -gt 600 ] &&
    printf "${YEL}⚠ TOO LONG${NC}: skills/%s/SKILL.md — %d lines (threshold: 600)\n" "$(basename "$(dirname "$f")")" "$lines" ||
    printf "  %-50s %d\n" "skills/$(basename "$(dirname "$f")")/SKILL.md" "$lines"
done
for f in .claude/rules/*.md; do
    lines=$(wc -l <"$f" | tr -d ' ')
    [ "$lines" -gt 200 ] &&
    printf "${YEL}⚠ TOO LONG${NC}: rules/%s — %d lines (threshold: 200)\n" "$(basename "$f")" "$lines" ||
    printf "  %-50s %d\n" "rules/$(basename "$f")" "$lines"
done
```

**Severity**: **medium** — report only, never auto-fix.

______________________________________________________________________

## Check 13 — Markdown heading hierarchy continuity

````bash
GRN='\033[0;32m'
YEL='\033[1;33m'
NC='\033[0m'
printf "=== Check 13: Heading hierarchy continuity ===\n"
violations=0
for f in .claude/agents/*.md .claude/skills/*/SKILL.md .claude/rules/*.md; do # timeout: 5000
    [ -f "$f" ] || continue
    awk -v file="$f" '
    /^```/ { in_code = !in_code; next }
    in_code { next }
    /^#+ / {
      n = 0; s = $0
      while (substr(s,1,1) == "#") { n++; s = substr(s,2) }
      if (prev > 0 && n > prev + 1) {
        printf "  \033[1;33m⚠ HEADING JUMP\033[0m: %s:%d — h%d followed by h%d (skipped h%d)\n", \
          file, NR, prev, n, prev+1
        found++
      }
      prev = n
    }
    END { exit (found > 0) ? 1 : 0 }
  ' "$f" || violations=$((violations + 1))
done
if [ "$violations" -eq 0 ]; then
    printf "${GRN}✓${NC}: Check 13 — no heading hierarchy violations found\n"
fi
````

**Severity**: **medium** — heading jumps impair navigation. Fix: insert missing intermediate heading level, or demote/promote the offending heading. **Report only** — never auto-fix.

______________________________________________________________________

## Check 14 — Orphaned follow-up references

Use Grep tool (pattern `` `/[a-z-]*` ``, glob `skills/*/SKILL.md`, path `.claude/`, output mode `content`) to find skill-name references; compare against disk inventory.

______________________________________________________________________

## Check 15 — Hardcoded user paths

Use Grep tool (pattern `/Users/|/home/`, glob `{agents/*.md,skills/*/SKILL.md}`, path `.claude/`, output mode `content`) to flag non-portable paths in agent and skill files. Then run a second Grep directly on `.claude/settings.json` with the same pattern to catch absolute hook paths in the settings file.

**Important**: run this check on every file regardless of whether critical or high findings were already found — path portability issues are orthogonal to other severity classes and must not be deprioritized due to presence of more serious findings in the same file.

______________________________________________________________________

## Check 16 — Example value vs. token cost

First, detect whether the project has local context files:

```bash
for f in AGENTS.md CONTRIBUTING.md .claude/CLAUDE.md; do # timeout: 5000
    [ -f "$f" ] && printf "✓ found: %s\n" "$f"
done
```

Then scan agent and skill files for inline examples:

````bash
for f in .claude/agents/*.md .claude/skills/*/SKILL.md; do # timeout: 5000
    count=$(grep -cE '^```|^## Example|^### Example' "$f" 2>/dev/null || true)
    lines=$(wc -l <"$f" | tr -d ' ')
    [ "$count" -gt 0 ] && printf "%s: %d example blocks, %d total lines\n" "$f" "$count" "$lines"
done
````

Using model reasoning, classify each example block:

- **High-value**: non-obvious pattern, nuanced judgment, or output-format spec that prose cannot convey → keep
- **Low-value**: restates prose, trivial, or superseded by project-local docs → **low** finding: suggest removing or replacing with a pointer to the local doc

Report per-file: `N examples total, K high-value, M low-value (est. ~X tokens wasted)`.

______________________________________________________________________

## Check 17 — Cross-file content duplication (>40% consecutive step overlap)

```bash
printf "%-30s %s\n" "FILE" "STEPS"
for f in .claude/skills/*/SKILL.md; do # timeout: 5000
    name="skills/$(basename "$(dirname "$f")")"
    steps=$(grep -c '^## Step' "$f" 2>/dev/null || echo 0)
    printf "%-30s %d\n" "$name" "$steps"
done
for f in .claude/agents/*.md; do
    name="agents/$(basename "$f" .md)"
    sections=$(grep -c '^## ' "$f" 2>/dev/null || echo 0)
    printf "%-30s %d\n" "$name" "$sections"
done
```

Using model reasoning, compare the workflow body of each file against all others in its class. For each pair:

1. Count steps in each file: N_A and N_B
2. Find the longest consecutive run of substantially similar steps: N_run
3. Compute run fraction: `max(N_run / N_A, N_run / N_B)`
4. Flag if run fraction ≥ 0.4 (40%)

Scattered similarity does **not** count — only a contiguous block triggers this check. **Severity**: **medium** — report only, never auto-fix.

For agent pairs flagged here, name the canonical owner of the duplicated content. If there is no clear canonical owner because both files are effectively describing the same role, route the pair back to Check 20 as a `merge-prune` candidate instead of leaving the duplication judgement ambiguous.

______________________________________________________________________

## Check 18 — Rules integrity and efficiency

Four sub-checks covering `.claude/rules/`. Skip if `rules/` directory does not exist or is empty.

**18a — Inventory vs MEMORY.md**:

```bash
ls .claude/rules/*.md 2>/dev/null | xargs -I{} basename {} .md | sort # timeout: 5000
```

Rules on disk but absent from MEMORY.md roster → **medium**. Rules in MEMORY.md but absent on disk → **medium**.

**18b — Frontmatter completeness**:

```bash
for f in .claude/rules/*.md; do # timeout: 5000
    desc=$(awk '/^---$/{c++; if(c==2)exit} c==1 && /^description:/{found=1} END{print found+0}' "$f")
    [ "$desc" -eq 0 ] && printf "MISSING description: %s\n" "$f"
done
```

Missing `description:` → **high**. Malformed `paths:` → **high**.

**18c — Redundancy check**: For each rule file, identify 2–3 most specific directive phrases. Grep those phrases verbatim in `.claude/CLAUDE.md` and `.claude/agents/*.md`. If exact phrase exists in ≥2 locations outside the rule file → **medium** (distillation incomplete).

```bash
grep -l "Never switch to NumPy" .claude/agents/*.md .claude/CLAUDE.md 2>/dev/null # timeout: 5000
grep -l "never git add" .claude/agents/*.md .claude/CLAUDE.md 2>/dev/null         # timeout: 5000
```

**18d — Cross-reference integrity**: Grep agent files, skill files, and CLAUDE.md for references to `.claude/rules/<name>.md` patterns. Verify each referenced filename exists on disk → missing file → **high**.

```bash
grep -rh '\.claude/rules/[a-z_-]*\.md' .claude/agents/ .claude/skills/ .claude/CLAUDE.md 2>/dev/null |
grep -o 'rules/[a-z_-]*\.md' | sort -u # timeout: 5000
```

Severity: 18b = **high**; 18a/18c/18d = **medium**.

# Skill Checks — 7, 20, 18

______________________________________________________________________

## Check 21 — Skill frontmatter conflicts

`context:fork + disable-model-invocation:true` is a broken combination.

```bash
RED='\033[1;31m'
YEL='\033[1;33m'
GRN='\033[0;32m'
CYN='\033[0;36m'
NC='\033[0m'
for f in .claude/skills/*/SKILL.md; do # timeout: 5000
    name=$(basename "$(dirname "$f")")
    if awk '/^---$/{c++} c<2' "$f" 2>/dev/null | grep -q 'context: fork' &&
    awk '/^---$/{c++} c<2' "$f" 2>/dev/null | grep -q 'disable-model-invocation: true'; then
        printf "${RED}! BREAKING${NC} skills/%s: context:fork + disable-model-invocation:true\n" "$name"
        printf "  ${RED}→${NC} forked skill has no model to coordinate agents or synthesize results\n"
        printf "  ${CYN}fix${NC}: remove disable-model-invocation:true (or remove context:fork if purely tool-only)\n"
    fi
done
```

______________________________________________________________________

## Check 22 — Calibration coverage gap

**Step 1 — Read the calibrate domain table**: Read `.claude/skills/calibrate/modes/skills.md` and extract the registered target list under `### Domain table`. Build the set of registered targets.

**Step 2 — Scan all skill modes on disk**: Use Glob (`skills/*/SKILL.md`, path `.claude/`) and Glob (`skills/*/modes/*.md`, path `.claude/`) to enumerate every skill and mode file. Extract mode names from `argument-hint:` frontmatter and `## Mode:` / `### Mode:` headings.

**Step 3 — Validate registered targets exist on disk**: For each registered target, verify the corresponding skill/mode file exists. A registered target with no matching file → **medium** (calibrate will fail at runtime).

**Step 4 — Identify unregistered calibratable candidates** (model reasoning):

A mode is calibratable when ALL three signals are present:

1. **Deterministic structured output**: findings list, completeness checklist, structured table, or machine-readable verdict
2. **Synthetic input feasible**: can be tested without external services
3. **Ground truth constructable**: known issues can be injected and scored

→ Unregistered mode matching all three signals: **low** (add to `calibrate/modes/skills.md` domain table)

______________________________________________________________________

## Check 23 — Bash command misuse / native tool substitution

```bash
YEL='\033[1;33m'
GRN='\033[0;32m'
CYN='\033[0;36m'
NC='\033[0m'
printf "=== Check 23: Bash misuse candidates ===\n"
grep -rn '\bcat \|`cat ' .claude/agents/ .claude/skills/ .claude/rules/ 2>/dev/null |
grep -v '^Binary' | grep -v '# ' &&
printf "  ${CYN}hint${NC}: replace cat with Read tool\n" || true
grep -rn '\bgrep \|\brg \b' .claude/agents/ .claude/skills/ .claude/rules/ 2>/dev/null |
grep -v '^Binary' | grep -v '# .*grep\|Grep tool\|Use Grep' &&
printf "  ${CYN}hint${NC}: replace grep/rg with Grep tool\n" || true
grep -rn '\bfind \b.*-name\|\bls \b.*\*' .claude/agents/ .claude/skills/ .claude/rules/ 2>/dev/null |
grep -v '^Binary' | grep -v '# .*Glob\|Use Glob\|Glob tool' &&
printf "  ${CYN}hint${NC}: replace find/ls with Glob tool\n" || true
grep -rn 'echo .* >\|tee ' .claude/agents/ .claude/skills/ .claude/rules/ 2>/dev/null |
grep -v '^Binary' | grep -v '# .*Write tool\|Use Write' &&
printf "  ${CYN}hint${NC}: replace echo-redirect/tee with Write tool\n" || true
grep -rn '\bsed \b\|\bawk \b' .claude/agents/ .claude/skills/ .claude/rules/ 2>/dev/null |
grep -v '^Binary' | grep -v '# .*Edit tool\|Use Edit\|awk.*{print\|awk.*BEGIN' &&
printf "  ${CYN}hint${NC}: replace sed/awk text-substitution with Edit tool\n" || true
printf "${GRN}✓${NC}: Check 23 scan complete\n"
```

After the scan, apply model reasoning to each match — exclude cases where the shell command is genuinely necessary. Flag only where the native tool is a direct drop-in replacement.

| Shell command                      | Preferred native tool | Severity |
| ---------------------------------- | --------------------- | -------- |
| `cat <file>`                       | Read tool             | medium   |
| `grep`/`rg` for content search     | Grep tool             | medium   |
| `find`/`ls` for file listing       | Glob tool             | medium   |
| `echo … >` / `tee` to write a file | Write tool            | medium   |
| `sed`/`awk` for text substitution  | Edit tool             | medium   |

**Report only** — never auto-fix; some Bash invocations in example/illustration code blocks are intentional.

---
name: release
description: 'Prepare release communication and check release readiness. Main mode: notes with optional flags --changelog, --summary, --migration; range as v1->v2. Other modes: prepare (full pipeline: audit → all artifacts), audit (pre-release readiness check: blockers, docs alignment, version consistency, CVEs). Use whenever the user says "prepare release", "write changelog", "what changed since v1.x", "prepare v2.0", "write release notes", "am I ready to release", "check release readiness", or wants to announce a version to users.'
argument-hint: [notes] [v1->v2] [--changelog] [--summary] [--migration] | prepare <version> | audit [version]
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, TaskCreate, TaskUpdate, Agent
model: opus
effort: high
---

<objective>

Prepare release communication from what changed. Output adapts to audience — user-facing notes, CHANGELOG entry, internal summary, or migration guide.

</objective>

<inputs>

Mode comes **first**; range or flags follow:

| Invocation | Arguments | Writes to disk |
| --- | --- | --- |
| `/release [notes] [range]` | optional range (default: last-tag..HEAD); use `v1->v2` for explicit range | `PUBLIC-NOTES.md` |
| `/release notes [range] --changelog` | optional range + flag | `PUBLIC-NOTES.md` + prepends `CHANGELOG.md` |
| `/release notes [range] --summary` | optional range + flag | `PUBLIC-NOTES.md` + `.temp/output-release-summary-<branch>-<date>.md` |
| `/release notes [range] --migration` | optional range + flag | `PUBLIC-NOTES.md` + `.temp/output-release-migration-<branch>-<date>.md` |
| `/release notes [range] --changelog --summary --migration` | all flags | All four outputs |
| `/release prepare <version>` | version to stamp, e.g. `v1.3.0` | All artifacts: audit → `PUBLIC-NOTES.md` + `CHANGELOG.md` + summary + migration if breaking |
| `/release audit [version]` | optional target version | Terminal readiness report |

Range notation: `v1->v2` (e.g. `v1.2->v2.0`) — converted internally to git range. No mode given → defaults to `notes`. Flags add outputs alongside notes. `prepare` = full pipeline — runs audit first, then all artifacts; use when cutting release, not drafting.

</inputs>

<workflow>

**Task hygiene**: Call `TaskList` before creating tasks. Per found task:

- `completed` if work clearly done
- `deleted` if orphaned / irrelevant
- `in_progress` only if genuinely continuing

**Task tracking**: per CLAUDE.md, TaskCreate for each major phase. Mark in_progress/completed throughout. On retry or scope change, new task.

## Mode Detection

Parse `$ARGUMENTS` by first token:

```bash
read FIRST REST <<<"$ARGUMENTS"
```

| First token | Mode | Routing |
| --- | --- | --- |
| `prepare` | prepare | Skip to **Mode: prepare** |
| `audit` | audit | Skip to **Mode: audit** |
| `notes` | notes | Parse flags and range from `$REST`; continue Steps 1–5 |
| *(none or bare range)* | notes | `RANGE="$ARGUMENTS"`, no flags; continue Steps 1–5 |

After matching `notes`, parse flags from `$REST`:

```bash
DO_CHANGELOG=false; DO_SUMMARY=false; DO_MIGRATION=false; RANGE=""
for arg in $REST; do
  case "$arg" in
    --changelog)  DO_CHANGELOG=true ;;
    --summary)    DO_SUMMARY=true ;;
    --migration)  DO_MIGRATION=true ;;
    *)            RANGE="$arg" ;;
  esac
done
# Convert v1->v2 shorthand to git range notation
RANGE="${RANGE/->/../}"
```

## Shared setup

```bash
# Resolve skill directory — used by all modes for templates and guidelines
SKILL_DIR="$(find ~/.claude/plugins -path "*/oss/skills/release" -type d 2>/dev/null | head -1)"  # timeout: 5000
[ -z "$SKILL_DIR" ] && SKILL_DIR="plugins/oss/skills/release"
```

## Step 1: Gather changes

```bash
# Use $RANGE from Mode Detection, or fall back to last-tag..HEAD
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD)
RANGE="${RANGE:-$LAST_TAG..HEAD}"
[ -z "$RANGE" ] && echo "Error: could not determine commit range" && exit 1

# No-tags guard: warn when no real release tags exist (LAST_TAG = initial commit)
git describe --tags --abbrev=0 2>/dev/null || echo "⚠ No release tags found — analyzing full history from initial commit. Consider tagging your first release."

# One-liner overview (navigation index)
git log $RANGE --oneline --no-merges # timeout: 3000

# Full commit messages — read these to catch BREAKING CHANGE footers,
# co-authors, and details omitted from the subject line
git log $RANGE --no-merges --format="--- %H%n%B" # timeout: 3000

# File-level diff stat — confirms what areas actually changed
git diff --stat $(echo "$RANGE" | sed 's/\.\./\ /') # timeout: 3000

# PR titles, bodies, and labels for merged PRs (richer context than commits)
TRUNK=$(git remote show origin 2>/dev/null | grep 'HEAD branch' | { read -r _ _ val; echo "${val:-main}"; })
# timeout: 15000
gh pr list --state merged --base "${TRUNK:-main}" --limit 100 \
    --json number,title,body,labels,mergedAt,author 2>/dev/null
```

Cross-reference commit bodies against Pull Request (PR) descriptions — canonical source of truth for *why* change was made. `BREAKING CHANGE:` footer = breaking change regardless of PR label.

## Step 2: Classify each change

Section order (fixed — never reorder): 🚀 Added → ⚠️ Breaking Changes → 🌱 Changed → 🗑️ Deprecated → ❌ Removed → 🔧 Fixed

| Category | Output section | What goes here |
| --- | --- | --- |
| **New Features** | 🚀 Added | User-visible additions |
| **Breaking Changes** | ⚠️ Breaking Changes | Existing code **stops working immediately** after upgrade — API removed, signature changed incompatibly, behavior changed with no fallback. Must be 100% certain it no longer works. |
| **Improvements** | 🚀 Added or 🌱 Changed | Enhancements to existing behavior |
| **Performance** | 🚀 Added or 🔧 Fixed | Speed or memory improvements |
| **Deprecations** | 🗑️ Deprecated | Old API **still works** this release but is scheduled for removal — emits a warning, replacement exists |
| **Removals** | ❌ Removed | Previously deprecated API now gone (this is what becomes a Breaking Change in the next cycle) |
| **Bug Fixes** | 🔧 Fixed | Correctness fixes |
| **Internal** | *(omit)* | Refactors, CI/tooling, deps, code cleanup, developer-facing housekeeping — omit unless directly user-impacting |

**Breaking vs Deprecated**: old call still works (even with warning) → Deprecated, never Breaking. Breaking = upgrade causes immediate failures, no compat period.

Filter out: merge commits, minor dep bumps, CI/tooling config, comment typos, internal refactors, code cleanup, internal-only dep bumps, developer housekeeping, no-user-impact changes. **Never include internal staff names or internal maintenance details in public-facing output.** Always include: breaking changes, behavior changes, new API surface.

## Step 3: Explore interesting changes

For top 3–5 most significant changes (features, breaking, major behavior), read actual diff or changed files:

```bash
git diff $RANGE -- <file>    # timeout: 3000
git show <commit>:<file>     # timeout: 3000
```

Goal: understand what change actually does at implementation level — new APIs, parameters, behavior — so notes describe real functionality, not just commit subjects.

Skip for trivial changes (typos, dep bumps, CI config).

## Step 4: Choose output format

Pre-flight — verify all templates present before proceeding:

```bash
# $SKILL_DIR resolved in Shared setup block above
[ -z "$SKILL_DIR" ] && echo "Error: could not locate release skill directory" && exit 1
for tmpl in PUBLIC-NOTES.tmpl.md CHANGELOG.tmpl.md SUMMARY.tmpl.md MIGRATION.tmpl.md; do # timeout: 5000
    [ -f "$SKILL_DIR/templates/$tmpl" ] || {
        echo "Missing template: $tmpl — aborting"
        exit 1
    }
done
```

Before writing, fetch last 2–3 releases to check project-specific formatting conventions:

```bash
gh release list --limit 3                                                  # timeout: 30000
LATEST_TAG=$(gh release list --limit 1 --json tagName --jq '.[0].tagName') # timeout: 30000
[ -z "$LATEST_TAG" ] || [ "$LATEST_TAG" = "null" ] && echo "No releases found — using template defaults" || gh release view "$LATEST_TAG"  # timeout: 15000
```

Existing releases deviate from templates → match their style. Templates below = default; project conventions take precedence. `gh release list` returns empty → skip style-matching step; proceed with template defaults.

### Notes — user-facing, public (`notes`)

Omit sections with no content.

For `notes` mode: first produce CHANGELOG-format classification (Step 2 output). Derive user-facing notes FROM that classification, expanding interesting features with Step 3 insights. Classification = working document — don't write to disk in `notes` mode, use as structural backbone.

Read PUBLIC-NOTES template from $SKILL_DIR/templates/PUBLIC-NOTES.tmpl.md and use as format.

### CHANGELOG Entry (`--changelog` flag)

Read CHANGELOG entry template from $SKILL_DIR/templates/CHANGELOG.tmpl.md and use as format.

### Internal Release Summary (`--summary` flag)

Read internal release summary template from $SKILL_DIR/templates/SUMMARY.tmpl.md and use as format.

### Migration Guide (`migration`)

Read migration guide template from $SKILL_DIR/templates/MIGRATION.tmpl.md and use as format.

## Step 5: Writing guidelines

Read writing guidelines from $SKILL_DIR/guidelines/writing-rules.md and follow them.

After polishing, for `notes` base output and `--migration` flag output, dispatch shepherd for public-facing voice/tone review before writing to disk:

```bash
# Pre-compute shepherd run dir (file-handoff protocol)
SHEPHERD_DIR=".temp/release-shepherd-$(git branch --show-current 2>/dev/null | tr '/' '-' || echo 'main')-$(date +%Y-%m-%d)"
mkdir -p "$SHEPHERD_DIR"
# Write the generated draft content to: $SHEPHERD_DIR/draft.md before dispatching
```

IMPORTANT: expand `$SHEPHERD_DIR` to its literal computed value before inserting into the spawn prompt — do not pass the variable name literally.

```text
Agent(subagent_type="oss:shepherd", prompt="Review the draft release content at <$SHEPHERD_DIR/draft.md> for public-facing voice and tone. Apply shepherd voice guidelines: human and direct, no internal jargon, no staff names, no internal maintenance details. Write the revised content to <$SHEPHERD_DIR/shepherd-revised.md>. Return ONLY: {\"status\":\"done\",\"changes\":N,\"file\":\"<$SHEPHERD_DIR/shepherd-revised.md>\"}")
```

Read `$SHEPHERD_DIR/shepherd-revised.md` → use as final content for disk write. For `--changelog` and `--summary` flag outputs, skip shepherd, write directly. Shepherd runs once per invocation — combine notes and `--migration` content into single draft if both present.

Write to disk:

```bash
BRANCH=$(git branch --show-current 2>/dev/null | tr '/' '-' || echo 'main')
DATE=$(date +%Y-%m-%d)
```

- **notes** (always): shepherd review → write to `PUBLIC-NOTES.md` at repo root. Notify: `→ written to PUBLIC-NOTES.md`
- **`--changelog`** (if set): no shepherd → prepend entry to `CHANGELOG.md` after `# Changelog` heading (create file with that heading if missing). Notify: `→ prepended to CHANGELOG.md`
- **`--summary`** (if set): no shepherd → save to `.temp/output-release-summary-$BRANCH-$DATE.md`. Notify: `→ saved to .temp/output-release-summary-<branch>-<date>.md`
- **`--migration`** (if set): shepherd review → save to `.temp/output-release-migration-$BRANCH-$DATE.md`. Notify: `→ saved to .temp/output-release-migration-<branch>-<date>.md`

## Step 6: Publish (after writing notes)

**Human gate** — stop and hand off to user: GitHub release must be created with project-level tooling (e.g. `gh release create`). See project's CLAUDE.md or `oss:shepherd` agent (`<release_checklist>` section) for exact command.

End response with `## Confidence` block per CLAUDE.md output standards.

## Mode: prepare

**Trigger**: `/release prepare <version>` (e.g., `prepare v1.3.0` or `prepare 1.3.0`)

**Purpose**: Full release pipeline — audit first, then generate all artifacts. Use when cutting release; use individual modes for drafting.

```bash
VERSION="${REST%% *}"
[[ "$VERSION" != v* ]] && VERSION="v$VERSION"
DATE=$(date +%Y-%m-%d)
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD)
RANGE="$LAST_TAG..HEAD"
# $SKILL_DIR resolved in Shared setup block above
```

### Phase 1: Readiness audit

Run all checks from **Mode: audit** with `$VERSION` as target. Present readiness table.

**If verdict is BLOCKED**: stop. List blockers, instruct user to resolve before re-running `/release prepare $VERSION`. Write no artifacts.

**If verdict is READY or NEEDS ATTENTION**: surface warnings, continue to Phase 2.

### Phase 2: Gather and classify changes

Run the change classification logic (see **Step 2: Classify each change** of notes mode) — git history and PR data already gathered in Phase 1; no re-gather, no Step 3 file exploration.

Note whether **Breaking Changes** classified — gates Phase 3d.

### Phase 3: Write all artifacts

```bash
RELEASE_DIR="releases/$VERSION"
mkdir -p "$RELEASE_DIR"
```

Write each artifact in sequence:

**a. `releases/$VERSION/PUBLIC-NOTES.md`** — user-facing notes (Step 3 `notes` format). Shepherd voice review applies per Step 5.

**b. `CHANGELOG.md`** — prepend entry stamped `$VERSION — $DATE` (Step 3 `changelog` format) to root `CHANGELOG.md`. Cumulative file — not versioned per release. Create with `# Changelog` header if missing. No shepherd review — write directly.

**c. `releases/$VERSION/SUMMARY.md`** — internal summary (Step 3 `summary` format).

**d. `releases/$VERSION/MIGRATION.md`** — always written. Breaking changes classified → use Step 3 `migration` format. No breaking changes → single line: `No breaking changes in this release.` Shepherd voice review applies per Step 5.

### Output

```markdown
## Release prepare: $VERSION

### Audit
[readiness table from Phase 1, condensed]
[any warnings carried forward]

### Written
- `releases/$VERSION/PUBLIC-NOTES.md` — user-facing notes (N features, N fixes, N breaking changes)
- `CHANGELOG.md` — $VERSION entry prepended (root, cumulative)
- `releases/$VERSION/SUMMARY.md` — internal summary
- `releases/$VERSION/MIGRATION.md` — migration guide (N breaking changes, or "No breaking changes")

### Next steps
1. Review all written files
2. Bump version in the project manifest
3. Commit, push, open PR
4. On merge: create GitHub release from PUBLIC-NOTES.md

## Confidence
**Score**: [computed from audit Phase 1 completeness and git history coverage]
**Gaps**: [audit blockers or low-signal areas; note if CVE scan incomplete or docs alignment partial]

**Refinements**: [N passes if self-review ran during audit or classification phases]
```

## Mode: audit

**Trigger**: `/release audit [version]`

**Purpose**: Pre-release readiness check — surfaces outstanding work, alignment gaps, and blockers before cutting release.

```bash
# $SKILL_DIR resolved in Shared setup block above
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD)
RANGE="${LAST_TAG}..HEAD"
```

### Phase A: Gather and explore changes

Run **Step 1** commands to gather full git history and PR data for `$RANGE`.

Run **Step 3** to explore top 3–5 most significant changed files (read actual diffs).

### Phase B: Readiness checks

Read and execute all checks from `$SKILL_DIR/templates/audit-checks.md`. Checks cover: version consistency across manifests, docs/CHANGELOG alignment, open blocking issues, dependency CVE scan, unreleased commits since last tag.

After readiness table, if issues found, append **Findings summary** table with one row per issue:

| # | Issue | Location | Severity |
| --- | --- | --- | --- |
| 1 | <what is wrong> | <section or file> | critical/high/medium/low |

Ensures every finding has explicit location, severity, and action — matching structured output format of `notes` and `changelog` modes.

End response with `## Confidence` block per CLAUDE.md output standards.

</workflow>

<notes>

- Filter noise (CI config, dep bumps, typos) unless user-impacting
- **Public-facing content policy**: release notes, changelogs, migration guides = user-visible changes only. Never include: internal staff names, internal maintenance, internal refactors, CI/tooling changes, internal dep bumps, code cleanup, developer housekeeping with no user impact.
- Public-facing output co-authored with `oss:shepherd` — follow its `<voice>` guidelines for human, direct tone
- Follow-up chains:
  - Readiness check → `/release prepare <version>` runs built-in audit first; use standalone `/release audit [version]` only for readiness check without cutting release
  - Release includes breaking changes → `/oss:analyse` for downstream ecosystem impact
  - Notes/changelog written → see Step 5 for release-create gate (`gh release create` must be user-run via project tooling)
  - `migration` content written → add to project docs and link from CHANGELOG entry

</notes>

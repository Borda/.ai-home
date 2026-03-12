---
name: release
description: 'Prepare release communication and check release readiness. Modes — notes (writes PUBLIC-NOTES.md), changelog (prepends CHANGELOG.md), summary (internal brief), migration (breaking-changes guide), prepare (full pipeline: audit → notes + changelog + summary + migration if breaking changes), audit (pre-release readiness check: blockers, docs alignment, version consistency, CVEs). Use whenever the user says "prepare release", "write changelog", "what changed since v1.x", "prepare v2.0", "write release notes", "am I ready to release", "check release readiness", or wants to announce a version to users.'
argument-hint: <mode> [range] | migration <from> <to> | prepare <version> | audit [version]
allowed-tools: Read, Write, Bash, Grep, Glob, Agent, TaskCreate, TaskUpdate
---

<objective>

Prepare release communication based on what changed. The output format adapts to the audience and context — user-facing release notes, a CHANGELOG entry, an internal release summary, or a migration guide for breaking changes.

</objective>

<inputs>

Mode comes **first**; range or version follows:

| Invocation                       | Arguments                                    | Writes to disk                                                                              |
| -------------------------------- | -------------------------------------------- | ------------------------------------------------------------------------------------------- |
| `/release notes [range]`         | optional git range (default: last-tag..HEAD) | `PUBLIC-NOTES.md`                                                                           |
| `/release changelog [range]`     | optional git range                           | Prepends `CHANGELOG.md`                                                                     |
| `/release summary [range]`       | optional git range                           | `tasks/output-release-<date>.md`                                                            |
| `/release migration <from> <to>` | two version tags, e.g. `v1.2 v2.0`           | Terminal only                                                                               |
| `/release prepare <version>`     | version to stamp, e.g. `v1.3.0`              | All artifacts: audit → `PUBLIC-NOTES.md` + `CHANGELOG.md` + summary + migration if breaking |
| `/release audit [version]`       | optional target version                      | Terminal readiness report                                                                   |

If no mode is given, defaults to `notes`. `prepare` is the full release pipeline — it runs audit first, then generates all artifacts for the version; use it when you are ready to cut a release rather than drafting individual documents.

</inputs>

<workflow>

**Task tracking**: per CLAUDE.md, create tasks (TaskCreate) for each major phase. Mark in_progress/completed throughout. On loop retry or scope change, create a new task.

## Mode Detection

Parse `$ARGUMENTS` by the first token:

```bash
FIRST=$(echo "$ARGUMENTS" | awk '{print $1}')
REST=$(echo "$ARGUMENTS" | cut -d' ' -f2-)
```

| First token                     | Mode      | Routing                                                                                                                                              |
| ------------------------------- | --------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| `prepare`                       | prepare   | Skip to **Mode: prepare**                                                                                                                            |
| `audit`                         | audit     | Skip to **Mode: audit**                                                                                                                              |
| `migration`                     | migration | Set `FROM=$(echo $REST \| awk '{print $1}')`, `TO=$(echo $REST \| awk '{print $2}')`, `RANGE="$FROM..$TO"`, continue Steps 1–5 with migration format |
| `notes`, `changelog`, `summary` | as named  | Set `RANGE="$REST"` (empty = default); continue Steps 1–5                                                                                            |
| *(none or bare range)*          | notes     | Set `RANGE="$ARGUMENTS"`; continue Steps 1–5                                                                                                         |

## Step 1: Gather changes

```bash
# Use $RANGE from Mode Detection, or fall back to last-tag..HEAD
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD)
RANGE="${RANGE:-$LAST_TAG..HEAD}"

# One-liner overview (navigation index)
git log $RANGE --oneline --no-merges

# Full commit messages — read these to catch BREAKING CHANGE footers,
# co-authors, and details omitted from the subject line
git log $RANGE --no-merges --format="--- %H%n%B"

# File-level diff stat — confirms what areas actually changed
git diff --stat $(echo "$RANGE" | sed 's/\.\./\ /')

# PR titles, bodies, and labels for merged PRs (richer context than commits)
gh pr list --state merged --base main --limit 100 \
  --json number,title,body,labels,mergedAt 2>/dev/null
```

Cross-reference commit bodies against PR descriptions — the canonical source of
truth for *why* a change was made. If a commit footer contains `BREAKING CHANGE:`,
it is a breaking change regardless of how it was labelled in the PR.

## Step 2: Classify each change

Section order (fixed — never reorder): 🚀 Added → ⚠️ Breaking Changes → 🌱 Changed → 🗑️ Deprecated → ❌ Removed → 🔧 Fixed

| Category             | Output section         | What goes here                                       |
| -------------------- | ---------------------- | ---------------------------------------------------- |
| **New Features**     | 🚀 Added               | User-visible additions                               |
| **Breaking Changes** | ⚠️ Breaking Changes    | Requires callers to change code, config, or behavior |
| **Improvements**     | 🚀 Added or 🌱 Changed | Enhancements to existing behavior                    |
| **Performance**      | 🚀 Added or 🔧 Fixed   | Speed or memory improvements                         |
| **Deprecations**     | 🗑️ Deprecated          | Still works, scheduled for removal                   |
| **Removals**         | ❌ Removed             | Previously deprecated API now gone                   |
| **Bug Fixes**        | 🔧 Fixed               | Correctness fixes                                    |
| **Internal**         | *(omit)*               | Refactors, CI, deps — omit unless user-impacting     |

Filter out: merge commits, minor dep bumps, CI config, comment typos.
Always include: any breaking change, any behavior change, any new API surface.

## Step 3: Choose output format

Before writing, fetch the last 2–3 releases from the repo to check for project-specific formatting conventions:

```bash
gh release list --limit 3
gh release view <latest-tag>   # read the body to match style, tone, and structure
```

If the existing releases deviate significantly from the templates below (e.g., no emoji sections, different heading levels, prose-style entries), match their style. The templates below are the default — project conventions take precedence.

### Notes — user-facing, public (`notes`)

Omit any section that has no content.

````markdown
## 🚀 Added

- **Feature Name.** One-sentence description of what it does and why it matters. (#PR)

# Minimal real-usage example showing the new surface

```python
# example usage here
```

| Option | Best for |
| ------ | -------- |
| `NAME` | ...      |

- `new_param` added to `SomeConfig`, allowing X. (#PR)

## ⚠️ Breaking Changes

- **[Area]**: [what changed and what callers must do to migrate]. (#PR)

## 🌱 Changed

- [Behaviour change]: old behaviour → new behaviour. (#PR)

## 🗑️ Deprecated

- `OLD_NAME` deprecated in favour of `NEW_NAME`. (#PR)

## ❌ Removed

- `OLD_API` removed (deprecated since vX.Y). Migrate to `NEW_API`. (#PR)

## 🔧 Fixed

- Fixed [what was broken] when [condition]. (#PR)

---

## 🏆 Contributors

A special welcome to our new contributors and a big thank you to everyone who helped with this release:

* **Full Name** (@handle) ([LinkedIn](url)) – *What they built or fixed*
* @handle – *What they built or fixed* (use this form when real name is not confirmed)

---

**Full changelog**: https://github.com/[org]/[repo]/compare/vPREV...vNEXT
````

### CHANGELOG Entry (`changelog`)

```markdown
## [version] — [date]
### Added
### Changed
### Deprecated
### Removed
### Fixed
### Security
```

### Internal Release Summary (`summary`)

```markdown
## Release [version]
**What shipped**: [2-3 sentence summary of the most important changes]
**Impact**: [who is affected and how]
**Action required**: [anything ops/support/consumers need to do]
**Rollback**: [safe to roll back? any caveats?]
```

### Migration Guide (`migration`)

```markdown
## Migrating from [old] to [new]
### [Breaking change name]
**Before**: [snippet]
**After**: [snippet]
**Why**: [reason]
```

## Step 4: Writing guidelines

Write for the reader, not the commit author.

| Element          | Rule                                                              |
| ---------------- | ----------------------------------------------------------------- |
| Feature heading  | Bold title, period, then plain-English description — no jargon    |
| PR numbers       | Always at line end: `(#N)` or `(#N, #M)` — never omit             |
| Code examples    | Real usage showing the new surface; not pseudocode                |
| Tables           | Use for option/preset comparisons; skip for single-item features  |
| Breaking changes | State exactly what breaks and the migration path                  |
| Fix items        | Say what was broken and under what condition — not just "fixed X" |
| Changed items    | Behaviour changes only — old behaviour → new behaviour            |
| Deprecated items | Name old API and its replacement; omit removal version if unknown |
| Removed items    | State deprecated-since version and migration target               |

Bad/good examples:

- Bad: `"refactor: extract UserService from monolith"` → Good: `"User management is now ~40% faster"`
- Bad: `"Fix auth bug"` → Good: `"Fixed login failure for email addresses containing special characters"`

**Contributors rules:**

- List every external contributor, even for a one-liner fix
- **NEVER guess or hallucinate a real name.** A wrong name in public release notes is a serious error. When in doubt, omit the name entirely.
- **Name lookup protocol** — run for every contributor @handle before writing their entry:
  1. `gh api /users/<handle> --jq '.name'` — if non-null and non-empty, use as the real name (high confidence)
  2. If empty: spawn `web-explorer` to search `site:linkedin.com "<handle>" developer` — use the name only if the profile clearly matches (same avatar, repos, or employer). Note the LinkedIn URL for inclusion.
  3. If still uncertain: use `@handle` only — no name field at all
- Format when name is confirmed: `* **Full Name** (@handle) ([LinkedIn](url)) – *noun phrase*`
- Format when name is not confirmed: `* @handle – *noun phrase*`
- LinkedIn is optional — include only if found via lookup; never construct a URL by guessing
- New contributors get a welcome sentence above the list
- Maintainer always listed last with infra / CI / docs scope

After applying the guidelines above to polish the output, write to disk per mode:

- **`notes`**: write to `PUBLIC-NOTES.md` at the repo root. Notify: `→ written to PUBLIC-NOTES.md`
- **`changelog`**: prepend the entry to `CHANGELOG.md` after the `# Changelog` heading (create the file with that heading if it does not exist). Notify: `→ prepended to CHANGELOG.md`
- **`summary`**: save to `tasks/output-release-$(date +%Y-%m-%d).md`. Notify: `→ saved to tasks/output-release-$(date +%Y-%m-%d).md`
- **`migration`**: print to terminal only

## Step 5: Publish (after writing notes)

Use project-level tooling to build, publish, and create the GitHub release. Refer to the project's CLAUDE.md or `oss-maintainer` agent for the specific commands.

```bash
# example only — check project CLAUDE.md or oss-maintainer agent for actual release process
gh release create v<version> --title "v<version>" \
  --notes "$(cat releases/v<version>/PUBLIC-NOTES.md)"
```

End your response with a `## Confidence` block per CLAUDE.md output standards: **Score**: 0.N (high ≥0.9 / moderate 0.7–0.9 / low \<0.7), **Gaps**: what limited thoroughness, **Refinements**: N passes.

## Mode: prepare

**Trigger**: `/release prepare <version>` (e.g., `prepare v1.3.0` or `prepare 1.3.0`)

**Purpose**: Full release preparation pipeline — audit readiness first, then generate and write all artifacts. Use this when cutting a release; use individual modes (`notes`, `changelog`, `summary`) for drafting.

```bash
VERSION=$(echo "$ARGUMENTS" | awk '{print $2}')
[[ "$VERSION" != v* ]] && VERSION="v$VERSION"
DATE=$(date +%Y-%m-%d)
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD)
RANGE="$LAST_TAG..HEAD"
```

### Phase 1: Readiness audit

Run all checks from **Mode: audit** with `$VERSION` as the target. Present the readiness table.

**If verdict is BLOCKED**: stop here. List the blockers and instruct the user to resolve them before re-running `/release prepare $VERSION`. Do not write any artifacts.

**If verdict is READY or NEEDS ATTENTION**: surface any warnings, then continue to Phase 2.

### Phase 2: Gather and classify changes

Run **Steps 1–2** to gather and classify all commits in `$RANGE`.

Note whether any **Breaking Changes** were classified — this gates Phase 3d.

### Phase 3: Write all artifacts

```bash
RELEASE_DIR="releases/$VERSION"
mkdir -p "$RELEASE_DIR"
```

Write each artifact in sequence:

**a. `releases/$VERSION/PUBLIC-NOTES.md`** — user-facing notes (Step 3 `notes` format).

**b. `CHANGELOG.md`** — prepend entry stamped `$VERSION — $DATE` (Step 3 `changelog` format) to the root `CHANGELOG.md`. This file is cumulative — it is not versioned per release. Create it with a `# Changelog` header if it does not exist.

**c. `releases/$VERSION/SUMMARY.md`** — internal summary (Step 3 `summary` format).

**d. `releases/$VERSION/MIGRATION.md`** — always written. If breaking changes were classified in Phase 2, use the Step 3 `migration` format. If no breaking changes, write a single line: `No breaking changes in this release.`

### Output

```
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
```

End your response with a `## Confidence` block per CLAUDE.md output standards.

## Mode: audit

**Trigger**: `/release audit [version]`

**Purpose**: Pre-release readiness check — surfaces outstanding work, alignment gaps, and blocking issues before cutting a release.

```bash
TARGET=$(echo "$ARGUMENTS" | awk '{print $2}')   # optional target version
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD)
RANGE="$LAST_TAG..HEAD"
```

### Check 1: Repository state

```bash
# Uncommitted changes
git status --short

# Unreleased commits
git log $RANGE --oneline --no-merges
```

### Check 2: CI health

```bash
gh run list --branch "$(git rev-parse --abbrev-ref HEAD)" --limit 5 \
  --json status,conclusion,name 2>/dev/null
```

### Check 3: Open issues and PRs

```bash
# Issues with blocker or bug labels (high-severity candidates)
gh issue list --state open --limit 30 \
  --json number,title,labels 2>/dev/null

# Open PRs targeting main — anything that should land before the release?
gh pr list --state open --base main --limit 20 \
  --json number,title,draft,reviewDecision 2>/dev/null
```

### Check 4: Documentation alignment

```bash
# What files changed since last tag?
git diff $RANGE --name-only

# Did README or any docs change? If not, flag for manual review.
git diff $RANGE --name-only | grep -iE 'readme|\.md$|docs/' || echo "no docs changed"
```

Read `README.md` and verify: install/usage examples match current API, version references are not pinned to old releases, any deprecated APIs mentioned are still present (or have deprecation notes). If `docs/` exists, spot-check recently changed public API sections against the docs.

Check `CHANGELOG.md`: does it have an `[Unreleased]` entry or a section for `$TARGET` covering commits in `$RANGE`?

### Check 5: Version consistency

```bash
grep -rn '__version__\|^version\s*=' --include="*.py" --include="*.toml" \
  --include="*.cfg" --include="*.json" . 2>/dev/null | grep -v ".git" | head -15
```

All declarations must agree. If `$TARGET` was given, verify it matches (or flag it needs bumping).

### Check 6: Critical code signals

```bash
# Release-blocking TODOs outside test files
grep -rn "TODO.*release\|FIXME\|HACK\|XXX" --include="*.py" \
  --exclude-dir=".git" --exclude-dir="tests" . 2>/dev/null | head -10

# Dependency CVE scan (if available)
command -v pip-audit &>/dev/null && pip-audit --format=json 2>/dev/null | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print(f'{len(d[\"dependencies\"])} deps, {sum(len(x[\"vulns\"]) for x in d[\"dependencies\"])} vulns')" 2>/dev/null || true
```

### Output

Print a readiness report:

```
## Release Readiness — [repo] [version or "next release"]
Date: [date] | Range: [last-tag]..HEAD ([N] commits)

| Check                 | Status | Detail |
|-----------------------|--------|--------|
| Working tree          | ✅ Clean / ⚠️ N files | [filenames if dirty] |
| CI (last 5 runs)      | ✅ Passing / ❌ N failing | [failing job names] |
| Blocking issues       | ✅ None / ❌ N open | [#N title] |
| Open PRs (main)       | ✅ None / ⚠️ N open | [PR titles] |
| README aligned        | ✅ / ⚠️ Review needed | [reason if flagged] |
| CHANGELOG entry       | ✅ Present / ❌ Missing | [section name or "add [Unreleased]"] |
| Version consistent    | ✅ / ⚠️ Mismatch | [files and values] |
| Dependency CVEs       | ✅ Clean / ⚠️ N vulns | [package names] |

### Verdict
**READY** — no blockers. Run `/release prepare <version>` to write artifacts.
— or —
**NEEDS ATTENTION** — N items before release:
- ❌ [blocking item]
- ⚠️ [recommended item]

### Next steps
[e.g., "resolve open PRs → re-run `/release audit v1.3.0` to verify → `/release prepare v1.3.0`"]
```

End your response with a `## Confidence` block per CLAUDE.md output standards.

</workflow>

<notes>

- Filter noise (CI config, dep bumps, typos) unless they are user-impacting
- Follow-up chains:
  - Before cutting a release → `/release audit [version]` to check readiness: blockers, docs alignment, version consistency, CVEs
  - Readiness confirmed → `/release prepare <version>` to run the full pipeline and write all artifacts
  - Release includes breaking changes → `/analyse` for downstream ecosystem impact assessment
  - `migration` content written → add to project docs and link from the CHANGELOG entry

</notes>

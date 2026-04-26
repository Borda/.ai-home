# Mode: Repo Health Overview

<workflow>

Run all five `gh` commands parallel — independent API calls:

```bash
# --- run these in parallel ---

# Open issues: count, age, labels (for triage stats and stale detection)
gh issue list --state open --json number,title,createdAt,updatedAt,labels --limit 200  # timeout: 30000

# Open PRs with review and CI status
gh pr list --state open --json number,title,createdAt,reviews,statusCheckRollup  # timeout: 15000

# All issues open+closed (for duplicate clustering)
gh issue list --state all --json number,title,state,labels,createdAt --limit 200  # timeout: 30000

# All PRs open+closed (for duplicate clustering — same bug may have a related PR)
gh pr list --state all --json number,title,state,createdAt --limit 100  # timeout: 30000

# All discussions open+closed (for duplicate clustering — questions/proposals may duplicate issues)
gh api graphql -f query='  # timeout: 15000
  query($owner:String!,$repo:String!){
    repository(owner:$owner,name:$repo){
      discussions(first:100,orderBy:{field:UPDATED_AT,direction:DESC}){
        nodes { number title closed createdAt }
      }
    }
  }' -f owner='{owner}' -f repo='{repo}' 2>/dev/null
```

Produce:

```markdown
## Repo Health: [repo]

### Issue Summary
- Open issues: [N]
- Stale (>90 days): [N] — [list top 5 by title]
- Needs triage (no labels): [N]
- Bugs: [N] | Enhancements: [N] | Questions: [N]

### PR Summary
- Open PRs: [N]
- Awaiting review: [N]
- CI failing: [N]
- Stale (>30 days): [N]

### Duplicates

Group all issues, PRs, and discussions (open and closed) by their shared duplication root —
the specific element that makes them the same problem: identical error message, identical
feature ask, or identical root cause even if symptoms differ. Flag as RELATED (not duplicate)
when items share a component/area but have distinct problems.

#### Group 1
**Root**: [the shared key — e.g. exact error message, exact feature request, exact failure mode]
- Issue #N: [title] ([open/closed]) — created [date]  ← CANONICAL
- Issue #N: [title] ([open/closed]) ← DUPLICATE
- PR #N: [title] ([state]) ← related fix
- Discussion #N: [title] ([open/closed]) ← DUPLICATE
  → Close duplicates with: "Closing as duplicate of #[canonical]"

_(Repeat for each group. If no duplicate groups found: "No obvious duplicates detected.")_

### Recommended Actions
1. [most urgent triage action]
2. [second]
3. [third]
```

Run `mkdir -p .reports/analyse/health` then write full report to `.reports/analyse/health/output-analyse-health-$(date +%Y-%m-%d).md` via Write tool — **do not print full analysis to terminal**.

Read compact terminal summary template from `$FOUNDRY_SHARED/terminal-summaries.md`. File absent → warn: "foundry:init required — printing plain terminal output instead." Use **Repo Health Summary** template. Replace `[skill-specific path]` with `.reports/analyse/health/output-analyse-health-$(date +%Y-%m-%d).md`. Output must begin with `---` on own line, entity line next, `→ saved to <path>` at end, close with `---` on own line. After printing, prepend same compact block to top of report via Edit tool — insert at line 1 so file begins with compact summary, blank line, then existing `## Repo Health:` content.

</workflow>

<notes>

- **--limit caps**: `--limit 200` on issue list covers most repos; repos with >200 open issues need `--paginate` — warn in report if limit hit (response length ≈ limit)
- **Duplicate clustering**: flag as DUPLICATE only when root is the same problem (identical error/feature ask/root cause); flag as RELATED when same component, distinct problems — don't conflate
- **Discussions API**: GraphQL `discussions` query returns only `first:100` — sufficient for health snapshot; full pagination not needed here

</notes>

---
description: Response style, framing, and output routing rules
---

## Re: Anchor

Start every reply with a 2-row single-column Markdown table. The renderer reflows it to terminal width automatically — no fixed widths, no padding needed.

Example (the actual template — copy this structure, replace bracketed text):

```
| [one-sentence summary of what was asked] |
|---|
| [full response here — use `<br>` for paragraph breaks] |
```

Rules:

- Top row (header): neutral factual gist of what the user asked — not a full restatement, no labels
- Bottom row: full response; use `<br>` between paragraphs for multi-line content; no text after the table
- No exceptions — apply to every response including short ones

## Progress and Transparency

- Narrate at milestones; print `[→ what and why]` before significant Bash calls
- 5+ min silence warrants a status note

## Tone

- **Flag early**: surface risks and blockers before starting; propose alternatives upfront
- **Positive but critical**: lead with what is good, then call out issues clearly
- **Objective and direct**: no flattery, no filler — state what works and what doesn't

## Output Routing

See `.claude/rules/quality-gates.md` for output routing rules, breaking-findings format, and terminal colors.

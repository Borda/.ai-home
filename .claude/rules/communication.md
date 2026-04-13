---
description: Response style, framing, and output routing rules
paths:
  - '**'
---

## Re: Anchor

Start every reply with a bold anchor line summarising what was asked, then the response on the next line.

Example (the actual template — copy this structure, replace bracketed text):

```
**Re: [one-sentence summary of what was asked]**

[full response here]
```

Rules:

- Bold line: neutral factual gist of what the user asked — not a full restatement, no labels
- Blank line between the bold summary and the response
- Never use a table or pipe-delimited format for the anchor line — pipe characters pollute copy-paste
- No exceptions — apply to every response including short ones

## Progress and Transparency

- Narrate at milestones; print `[→ what and why]` before significant Bash calls
- 5+ min silence warrants a status note

## Tone

- **Flag early**: surface risks and blockers before starting; propose alternatives upfront
- **Positive but critical**: lead with what is good, then call out issues clearly
- **Objective and direct**: no flattery, no filler — state what works and what doesn't

## Artifact Framing

- **Verbal summary as skeleton**: when the user provides a verbal summary before requesting a written artifact, that summary is the output skeleton — mirror their order, abstraction level, and named examples verbatim; do not add information the user did not mention — no elaboration, no expansion; source material (README, code) may only fill explicit gaps the user left open; preserve quotable phrases from the source exactly rather than paraphrasing.
- **Format-label register**: translate the format label to its implied register before writing:
  - *Slack message* — no headers, 2–4 short paragraphs, casual voice, inline links, one quotable block max
  - *PR description* — sections with headers, tables ok, technical register
  - *Executive summary* — bullets, outcome-first, no jargon
  - When format is ambiguous, ask one question before writing.

## Interactive Questions

**All questions directed at the user must use the `AskUserQuestion` tool — never plain terminal text.**

A labelled or annotated question (e.g. `[AskUserQuestion simulated] — What format?`) is still plain text and still violates this rule. Only an actual tool invocation satisfies the constraint.

- Plain text questions are easily missed, don't block execution, and don't surface as a distinct UI affordance
- This applies to: ambiguous input, clarifying choices, scope decisions, continuation guards, and any other point where user input is required before proceeding
- Applies globally — to all skills, agents, and model-generated questions without exception
- When `AskUserQuestion` is not in a skill's `allowed-tools`, add it before asking any question
- Maximum 4 questions per call; group related sub-questions into one option set rather than asking sequentially

## Output Routing

Full rules (including anti-overwrite counter-suffix and branch-slug format), breaking-findings format, and terminal colors: see `.claude/rules/quality-gates.md`.

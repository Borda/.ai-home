---
name: create
description: Interactive outline co-creation for developer advocacy content — collects format, audience profile, story arc (Problem→Journey→Insight→Action), and voice/tone; detects out-of-scope requests (FAQs, comparison tables); surfaces conflicts between user brief and audience needs. Writes approved outline to .plans/content/<slug>-outline.md for foundry:creator to execute. Use when starting a blog post, Marp slide deck, social thread, talk abstract, or lightning talk.
argument-hint: '[topic]'
allowed-tools: Read, Write, TaskCreate, TaskUpdate, AskUserQuestion
---

<objective>

First phase of a two-phase content system. Out-of-scope includes FAQs, comparison tables, and reference docs. Story arc is four-beat: Problem → Journey → Insight → Action.

</objective>

<inputs>

- **$ARGUMENTS**: optional — topic or goal in any form; one sentence enough. Format hints accepted ("a blog post about…", "talk abstract for…").

</inputs>

NOT for: implementation tasks, code generation, README writing (use foundry:doc-scribe), structured reference docs (FAQs, comparison tables — use foundry:doc-scribe).

<workflow>

**Task hygiene**: Call `TaskList`; mark clearly-done tasks `completed`, orphaned tasks `deleted`, genuinely-continuing tasks `in_progress`.

**Task tracking**: TaskCreate entries for all steps before any tool calls.

## Step 1 — Parse topic and out-of-scope detection

- If $ARGUMENTS provided: extract topic; note any embedded format hint.
- If no $ARGUMENTS: AskUserQuestion — "What are you trying to write about, and for whom?" (free text).
- Out-of-scope gate: if brief describes FAQs, comparison tables, feature matrices, or reference docs — stop immediately and respond: "This format doesn't fit a narrative arc — use `foundry:doc-scribe` for structured reference content." Do not proceed past this gate.

## Step 2 — Format and audience (max 2 AskUserQuestion calls)

**Format question** (AskUserQuestion):
> What content format?
> a: blog post
> b: conference / meetup talk with Marp slide deck ★
> c: social thread (Twitter/LinkedIn)
> d: talk abstract (CFP submission)
> e: lightning talk (5–10 min)

After answer: restate in one sentence ("Got it — a [format] on [topic].").

**Audience question** (AskUserQuestion):
> Who is the audience?
> a: beginners — new to the problem space ★
> b: intermediate — familiar with basics, seeking depth
> c: expert — already know the landscape, want novel insight
> d: describe your own profile

After answer: restate in one sentence, noting any implied audience needs.

## Step 3 — Arc construction and conflict check

Based on topic + audience, propose a four-beat arc:

- **Problem**: concrete opening hook — specific pain or question, not generic
- **Journey**: 3–5 key points to explore (what was tried, what failed, what the arc covers)
- **Insight**: the core "aha" framed for the stated audience level — name it directly
- **Action**: specific next step for the audience

**Editorial conflict check**: if brief implies expert audience but topic is introductory, or vice versa — surface before continuing:
> "Your brief suggests [X] but the audience profile is [Y] — recommend adjusting [Z]. Proceed as-is or adjust?"

**Arc approval** (AskUserQuestion):
> Show proposed arc. Ask: approve as-is, or which beat needs adjustment? (free text or "approve")

After approval: restate confirmed arc in two sentences.

## Step 4 — Voice and tone (1 AskUserQuestion)

**Voice question** (AskUserQuestion):
> What voice/tone?
> a: neutral developer advocate — balanced, educational ★
> b: opinionated / direct first-person — no hedging
> c: conversational / approachable — informal, relatable
> d: provide your own style brief

No default applied silently. Always ask.

## Step 5 — Write outline file

- Derive slug from topic: kebab-case, max 5 words (e.g. `tracing-python-services-otel`).
- Write creates `.plans/content/` if absent — no separate mkdir needed.
- Write `.plans/content/<slug>-outline.md` with this structure:

```md
---
topic: <topic from brief>
created: YYYY-MM-DD
---

## Audience
[who they are, experience level, what they've likely seen, what they need]

## Format
[blog post | conference talk (N min) | social thread (twitter|linkedin) | talk abstract | lightning talk (N min)]

## Voice
[tone brief: e.g., "direct and opinionated, first-person, no hedging"]

## Arc

### Problem
[concrete opening hook — the pain or question]

### Journey
[key points to explore: what was tried, what failed, what the arc covers]

### Insight
[the core "aha" — what was learned or built; name it directly]

### Action
[call to action — specific, what audience should do next]

## Constraints
[length target, things to avoid, format-specific constraints]
```

- Confirm file path to user.
- End with: "Run @foundry:creator to generate the complete [format] from this outline — foundry:creator is an agent; invoke it with `@foundry:creator` followed by the outline file path."
- End with a `## Confidence` block per quality-gates.md protocol, scoring based on how well the outline covers the user's stated topic, arc, and audience.

</workflow>

<notes>

- Maximum 5 AskUserQuestion interactions for a well-specified brief (steps 2–4 use exactly 4; step 1 adds one only when $ARGUMENTS absent).
- Each AskUserQuestion uses lettered options with one ★ recommended default.
- After each answer, restate understanding in 1–2 sentences before proceeding.
- Never silently adjust arc to match audience — always surface conflicts explicitly (Step 3).
- Refuse FAQs / comparison tables / reference docs at Step 1 gate; name `foundry:doc-scribe` as redirect.
- Write outline exactly once after approval — no second draft unless user requests.
- `foundry:creator` reads the output outline file and generates the full artifact autonomously.
- See brainstorm/create workflow design notes (blueprint files in .plans/blueprint/ are TTL-30d).

</notes>

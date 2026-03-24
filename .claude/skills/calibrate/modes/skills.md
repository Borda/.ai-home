## Mode: skills

### Domain table

Skill domains:

- `/audit` → synthetic `.claude/` config with N injected structural issues
- `/review` → synthetic Python module with N cross-domain issues (arch + tests + docs + lint)

### Step 2: Spawn skill pipeline subagents

Mark "Calibrate skills" in_progress. For each skill in the domain table, spawn one `general-purpose` pipeline subagent. Issue ALL spawns in a **single response**.

For skill targets (target name starts with `/`): spawn a `general-purpose` subagent with the skill's `SKILL.md` content prepended as context, running against the synthetic input from the problem. The pipeline template write-and-acknowledge pattern still applies.

Each subagent receives the pipeline template from `.claude/skills/calibrate/templates/pipeline-prompt.md` with these substitutions:

- `<TARGET>` = the skill name including `/` prefix (e.g., `/audit`)
- `<DOMAIN>` = the domain string from the table above for that skill
- `<N>` = 3 (fast) or 10 (full)
- `<TIMESTAMP>` = current run timestamp
- `<MODE>` = `fast` or `full`
- `<AB_MODE>` = `true` or `false`

Run dir per skill: `.claude/calibrate/runs/<TIMESTAMP>/<TARGET>/` (strip `/` from target name for the dir)

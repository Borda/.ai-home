## Local Config

`.claude/` edits stay local — no auto-propagation to `~/.claude/`.

- Edit `.claude/agents/`, `.claude/skills/`, `.claude/rules/`, `settings.json` freely
- Upstream only via `/sync apply` — never suggest or initiate mid-workflow
- Applies to all skills — no skill auto-syncs

## Memory Policy

Nothing to auto-memory (`~/.claude/projects/.../memory/`). Learnings → skills, agents, rules, plugin files (versioned, distributed with plugin).

- New rule/guideline → edit `plugins/*/skills/*/SKILL.md`, `plugins/*/agents/*.md`, or `plugins/*/rules/*.md`
- Lesson/correction → update governing skill/agent/rule
- Never write to MEMORY.md or create memory files

# foundry — Claude Code Plugin

Production-grade Claude Code configuration: 12 specialist agents, 15+ slash-command skill workflows, and event-driven hooks — packaged as an installable plugin for Python/ML OSS development.

## Install

### Requirements

- Claude Code CLI installed
- Repo cloned locally

### Steps

```bash
# Run steps 1–3 from the directory that CONTAINS your clone (not inside it)

# 1. Clone the repo (if not already done)
git clone https://github.com/Borda/.ai-home Borda-AI-Home

# 2. Register as a local marketplace  (run from the parent of Borda-AI-Home/)
claude plugin marketplace add ./Borda-AI-Home

# 3. Install the plugin
claude plugin install foundry@borda-ai-home
```

**4. One-time settings merge** — run inside Claude Code:

```
/foundry:init
```

Sets `statusLine`, merges `permissions.allow`, and enables `codex@openai-codex` in `~/.claude/settings.json`. Safe to re-run.

> [!TIP] Add `link` to also expose all commands at root namespace (`/review` instead of `/foundry:review`):
>
> ```
> /foundry:init link
> ```

## What gets installed

| Component  | What it is                                                              |
| ---------- | ----------------------------------------------------------------------- |
| **Agents** | 12 specialist roles (sw-engineer, qa-specialist, oss-shepherd, …)       |
| **Skills** | 15+ slash-command workflows (/develop, /review, /release, /audit, …)    |
| **Hooks**  | Task tracking, teammate quality gates, lint-on-save, tool preprocessing |

The plugin is self-contained — agents, skills, and hooks all live here. `.claude/agents/*.md` and `.claude/skills/*/` are symlinks pointing into the plugin, so edits in either location update the canonical source.

## Use

Once installed, all commands are available under the `foundry:` namespace:

```
/foundry:develop feature "add retry logic to the API client"
/foundry:review 42 --reply
/foundry:release prepare v1.2.0
/foundry:audit
```

> [!TIP] To make all commands available at root namespace (`/review` instead of `/foundry:review`), run `/foundry:init link` — symlinks foundry agents and skills into `~/.claude/` with conflict review before any overwrite.

See the [root README](../../README.md) for the full command reference.

## Upgrade

When the repo has updates:

```bash
cd Borda-AI-Home
git pull
claude plugin install foundry@borda-ai-home   # reinstalls from updated source
```

Re-run `/foundry:init` only if new permissions or `enabledPlugins` were added (check the git diff for `plugins/foundry/.claude-plugin/permissions.json` or `plugins/foundry/.claude-plugin/plugin.json`). If you previously ran `/foundry:init link`, re-run it — symlinks point to the versioned cache path and go stale after an upgrade.

## Develop / Debug

### Edit hooks

Hook JS files live in `plugins/foundry/hooks/`. Edit them directly — because `.claude/hooks/*.js` are symlinks pointing here, changes are reflected immediately in the source repo without any reinstall.

```bash
# Verify symlinks resolve correctly after editing
ls -la .claude/hooks/
```

### Test before installing (session-only mode)

Activate the plugin for a single session without touching `~/.claude/`:

```bash
claude --plugin-dir ./Borda-AI-Home/plugins/foundry
```

Agents, skills, and hooks from the plugin will be active. Exit and restart Claude Code to return to normal.

### Validate the manifest

```bash
claude plugin validate ./Borda-AI-Home/plugins/foundry
```

Reports missing files, broken symlinks, and manifest errors — run this after any structural change.

### Install from local path (upgrade in place)

After iterating on hooks or config locally:

```bash
claude plugin install foundry@borda-ai-home   # reinstalls from the registered marketplace path
```

No need to re-run `/foundry:init` unless `plugin.json` or `settings.json` permissions changed.

## Uninstall

```bash
claude plugin uninstall foundry
```

> [!NOTE] Settings merged by `/foundry:init` (`statusLine`, `permissions.allow` entries) remain in `~/.claude/settings.json` after uninstall — remove manually if desired. If `/foundry:init link` was run, symlinks in `~/.claude/agents/` and `~/.claude/skills/` also remain — remove with `rm ~/.claude/agents/<name>.md` and `rm -rf ~/.claude/skills/<name>` as needed.

## Structure

```
plugins/foundry/
├── .claude-plugin/
│   ├── plugin.json          ← manifest
│   └── permissions.json     ← allow-list merged into ~/.claude/settings.json by /foundry:init
├── agents/                  ← real files (canonical source)
├── skills/                  ← real files (canonical source)
└── hooks/
    ├── hooks.json           ← hook registrations (${CLAUDE_PLUGIN_ROOT} paths)
    ├── task-log.js          ← real file (canonical source)
    ├── statusline.js        ← real file
    ├── teammate-quality.js  ← real file
    ├── lint-on-save.js      ← real file
    ├── rtk-rewrite.js       ← real file
    ├── md-compress.js       ← real file
    └── stats-reader.js      ← CLI utility (not a hook; invoke directly: node stats-reader.js)
```

`.claude/hooks/*.js` are reverse symlinks pointing here (`../../plugins/foundry/hooks/xxx.js`). Edit hook JS files directly in `plugins/foundry/hooks/` — changes are live immediately in the source repo.

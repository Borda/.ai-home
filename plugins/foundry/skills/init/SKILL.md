---
name: init
description: 'Post-install setup for foundry plugin. Merges statusLine, permissions.allow, and enabledPlugins into ~/.claude/settings.json. With "link": additionally symlinks foundry agents and skills into ~/.claude/ for root-namespace invocation.'
argument-hint: '[link]'
allowed-tools: Read, Write, Bash, AskUserQuestion
effort: low
model: sonnet
---

<objective>

Set up foundry on a new machine. Two modes:

- **No argument**: merge `statusLine`, `permissions.allow`, and `enabledPlugins` into `~/.claude/settings.json`. Idempotent — safe to re-run.
- **`link`**: same as above, then create symlinks from `~/.claude/agents/` and `~/.claude/skills/` into the installed plugin cache, making all foundry agents and skills available at root namespace (`/review`, `/develop`, etc). Presents any conflicts for user approval before overwriting.

Re-run after any `claude plugin install foundry@borda-ai-home` upgrade to refresh stale symlinks.

NOT for: editing project `.claude/settings.json`; merging hooks (plugin's `hooks/hooks.json` loads automatically).

</objective>

<inputs>

- No argument — settings merge only
- `link` — settings merge + symlink creation with conflict review

</inputs>

<workflow>

## Step 1: Locate the installed plugin

Read `~/.claude/plugins/installed_plugins.json` using the Read tool. Find the entry whose key contains `foundry` (case-insensitive). Extract its `installPath`. If the file does not exist or contains no foundry entry, fall back to a filesystem scan:

```bash
PLUGIN_ROOT=$(jq -r 'to_entries[] | select(.key | ascii_downcase | contains("foundry")) | .value.installPath // empty' \
    "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null | head -1)  # timeout: 5000

# Fallback when registry entry is absent (manual cache copies, partial installs)
if [ -z "$PLUGIN_ROOT" ]; then
    PLUGIN_ROOT=$(find ~/.claude/plugins/cache -maxdepth 5 -name "plugin.json" 2>/dev/null \
            | xargs grep -l 'foundry' 2>/dev/null \
            | head -1 \
        | xargs -I{} dirname {})  # timeout: 10000
    [ -n "$PLUGIN_ROOT" ] && printf "  Note: foundry not in installed_plugins.json — using cache scan result; consider reinstalling\n"
fi
```

If `$PLUGIN_ROOT` is empty after both attempts, stop and report: "foundry plugin not found — install it first with: `claude plugin marketplace add /path/to/Borda-AI-Home && claude plugin install foundry@borda-ai-home`"

Confirm `$PLUGIN_ROOT/hooks/statusline.js` exists. If not, stop and report.

## Step 2: Back up settings.json

```bash
[ ! -f ~/.claude/settings.json ] && echo '{}' > ~/.claude/settings.json  # timeout: 5000
cp ~/.claude/settings.json ~/.claude/settings.json.bak  # timeout: 5000
```

Report: "Backed up ~/.claude/settings.json → ~/.claude/settings.json.bak"

## Step 2b: Check for stale hooks block

```bash
jq -e 'has("hooks")' ~/.claude/settings.json >/dev/null 2>&1  # timeout: 5000
```

If the `hooks` key exists, the user has a pre-plugin-migration settings block that will cause hooks to fire twice. Use `AskUserQuestion`:

- a) Remove the stale `hooks` block now ★ recommended (backup already in place from Step 2)
- b) Skip — I'll handle it manually

On **(a)**: use jq to strip the `hooks` key and write back with the Write tool, then continue. On **(b)**: warn "Double-firing risk: existing hooks block will fire alongside plugin-registered hooks." Continue.

## Step 3: Merge statusLine

Check if statusLine is already pointing to statusline.js:

```bash
jq -e '(.statusLine.command // "") | contains("statusline.js")' ~/.claude/settings.json >/dev/null 2>&1  # timeout: 5000
```

If already set: report "statusLine already set — skipping." Otherwise, use jq to set the value:

```bash
jq --arg cmd "node \"$PLUGIN_ROOT/hooks/statusline.js\"" \
    '.statusLine = {"async":true,"command":$cmd,"type":"command"}' \
    ~/.claude/settings.json > /tmp/foundry_init_tmp.json  # timeout: 5000
```

Write `/tmp/foundry_init_tmp.json` content back to `~/.claude/settings.json` using the Write tool.

## Step 4: Merge permissions.allow

Read `$PLUGIN_ROOT/.claude-plugin/permissions.json` using the Read tool. Merge into `~/.claude/settings.json` — add only entries not already present (exact string match):

```bash
jq --slurpfile perms "$PLUGIN_ROOT/.claude-plugin/permissions.json" \
    '.permissions.allow = ((.permissions.allow // []) + $perms[0] | unique)' \
    ~/.claude/settings.json > /tmp/foundry_init_tmp.json  # timeout: 5000
```

Write back with the Write tool. Report: "Added N new permissions.allow entries (M already present)."

## Step 5: Merge enabledPlugins

```bash
jq -e '.enabledPlugins["codex@openai-codex"] == true' ~/.claude/settings.json >/dev/null 2>&1  # timeout: 5000
```

If already `true`: report "enabledPlugins already set — skipping." Otherwise:

```bash
jq '.enabledPlugins["codex@openai-codex"] = true' \
    ~/.claude/settings.json > /tmp/foundry_init_tmp.json  # timeout: 5000
```

Write back with the Write tool.

## Step 6: Validate

After all writes, confirm the file parses as valid JSON:

```bash
jq empty ~/.claude/settings.json  # timeout: 5000
```

If `jq` exits non-zero: restore from backup (`cp ~/.claude/settings.json.bak ~/.claude/settings.json`), report the error, and stop. If valid: continue.

## Step 7: Final report (settings merge)

Print summary:

- statusLine: set / skipped
- permissions.allow: N entries added
- enabledPlugins: set / skipped
- Backup at: ~/.claude/settings.json.bak

If argument is not `link`: suggest "Run `/foundry:init link` to also expose foundry agents and skills at root namespace." Then stop.

## Step 8: Link — scan for conflicts (only when argument is `link`)

Enumerate what the plugin provides:

```bash
PLUGIN_AGENTS=$(ls "$PLUGIN_ROOT/agents/"*.md 2>/dev/null | xargs -I{} basename {})  # timeout: 5000
PLUGIN_SKILLS=$(ls -d "$PLUGIN_ROOT/skills/"*/ 2>/dev/null | xargs -I{} basename {})  # timeout: 5000
```

For each agent (`~/.claude/agents/<name>.md`) and skill (`~/.claude/skills/<name>`):

- Does not exist → **safe** (no conflict)
- Exists and is already a symlink pointing into this `$PLUGIN_ROOT` → **already linked** (skip)
- Exists as a real file or symlink pointing elsewhere → **conflict** (needs approval)

Build two lists: `SAFE` (will be linked silently) and `CONFLICTS` (needs approval).

## Step 9: Present conflicts and get approval

If `CONFLICTS` is empty: proceed to Step 10 silently.

If conflicts exist, print the list:

```
These existing entries in ~/.claude/ would be replaced with symlinks to the foundry plugin:

Agents:
  - <name>.md  (currently: real file / symlink to <other path>)

Skills:
  - <name>/  (currently: real file / symlink to <other path>)
```

Use `AskUserQuestion` with:

- a) Replace all listed entries ★ recommended
- b) Skip all conflicts — only link items with no existing entry
- c) Review one by one

On **c**: loop through each conflict with `AskUserQuestion` — "Replace `<name>`? (y) Yes / (n) Skip". Collect approvals.

## Step 10: Create symlinks

For each approved or safe agent (single `.md` file) — use `ln -sf` which atomically replaces any existing symlink or file without a prior `rm`:

```bash
ln -sf "$PLUGIN_ROOT/agents/<name>.md" ~/.claude/agents/<name>.md  # timeout: 5000
```

For each approved or safe skill directory — an existing directory cannot be replaced atomically; `rm -rf` is required first. Note: `rm` is intentionally absent from the plugin's allow list, so this step will prompt for approval — this is by design for a destructive directory removal:

```bash
rm -rf ~/.claude/skills/<name>  # timeout: 5000
ln -s "$PLUGIN_ROOT/skills/<name>" ~/.claude/skills/<name>  # timeout: 5000
```

## Step 11: Link report

Print summary:

- Agents linked: N (M skipped)
- Skills linked: N (M skipped)

Suggest: "Restart Claude Code to pick up the new root-namespace commands. Re-run `/foundry:init link` after any future plugin upgrade to refresh symlinks."

</workflow>

<notes>

**Testing init changes**: The init skill has no `.claude/skills/init` entry — it is only reachable as `/foundry:init` after the plugin is installed. To test changes: bump `version` in `plugins/foundry/.claude-plugin/plugin.json`, then run `claude plugin install foundry@borda-ai-home` from the repo root to refresh the cache, then invoke `/foundry:init`.

**Why `rm` is not in permissions.json**: `Bash(rm:*)` is intentionally excluded — it is too broad. Agent `.md` replacements use `ln -sf` (no rm needed). Skill directory replacements do require `rm -rf`, but only after explicit user approval in Step 9; the resulting permission prompt is a second confirmation gate, which is appropriate for a destructive directory removal.

**Upgrade path**: After `claude plugin install foundry@borda-ai-home` upgrades the version, symlinks created by `foundry:init link` will point to the old cache path and silently break. Re-run `/foundry:init link` — Step 8 detects stale-pointing symlinks as conflicts and replaces them. Use `/audit setup` to check link health via Check I3.

</notes>

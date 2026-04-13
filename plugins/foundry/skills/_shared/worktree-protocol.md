# Worktree Protocol

Conventions for any skill or agent that runs commands inside a git worktree.

## Bash command pattern — two calls, not one

Claude Code's permission matcher checks the **first token** of a Bash command. A compound command like:

```bash
# BAD — first token is "cd"; "uv run:*" permission never fires
cd /path/to/worktree && uv run python -c "..."
```

…does not match `Bash(uv run:*)` even if that pattern is in the allowlist, causing an unexpected permission prompt.

Use **two separate Bash calls** instead. The shell's working directory persists between calls:

```bash
# Call 1 — sets CWD; matches Bash(cd:*)
cd /path/to/worktree

# Call 2 — first token is now the real command; matches its own pattern
uv run python -c "..."
```

This applies to every command run "in" a worktree from the lead's context: `uv run`, `python`, `pytest`, `git`, etc.

## Running commands from inside a worktree agent

The cleanest alternative: spawn an agent with `isolation: "worktree"`. That agent's CWD is the worktree root, so all its Bash calls use clean first-token patterns with no `cd` prefix needed.

```
Agent(subagent_type="foundry:sw-engineer", isolation="worktree", prompt="...")
```

Reserve `cd /worktree && cmd` (even split across two calls) for cases where the lead must run a quick one-off check in the worktree without spawning a full agent.

## Settings in worktrees

Worktrees created via `isolation: "worktree"` land under `.claude/worktrees/<id>/`. Because the worktree contains a full project checkout (including `.claude/`), Claude Code finds the project's `settings.local.json` at `worktree/.claude/settings.local.json`. **This is a snapshot from worktree-creation time** — permissions added to the main project after the worktree was created are not automatically reflected. If a worktree agent hits unexpected permission prompts, check whether the main project's `settings.local.json` has been updated since the worktree was created.

// commit-guard.js — multi-event hook
//
// PURPOSE
//   Claude must never commit autonomously. The commit discipline rule
//   ("never commit without explicit user request in same message") lives in
//   a prompt instruction — not enforced at runtime. This hook enforces it
//   at the tool level: every `git commit` Bash call is blocked unless a
//   skill explicitly opted in via a sentinel file for that repo+branch.
//
//   Skills that legitimately commit as part of their workflow (oss:resolve,
//   research:run) create the sentinel at the start of their commit phase and
//   delete it immediately after. Ad-hoc Claude behavior — pattern-matching
//   from conversation context, "finishing a task" — never creates the sentinel,
//   so those commits are blocked and the user sees clear feedback.
//
//   Sentinel path: /tmp/claude-commit-auth-<repo-slug>-<branch-slug>
//   TTL: 15 min — auto-expires if a skill crashes before cleanup.
//
// HOW IT WORKS
//   1. PreToolUse(Bash): only fires on `git commit` calls.
//      Derives repo slug + branch slug → checks sentinel path present and fresh.
//      Sentinel valid → exit 0 (allow). Missing or expired → exit 2 (block).
//   2. SessionStart: wipes all /tmp/claude-commit-auth-<repo>-* sentinels so
//      authorizations from a previous session never carry over to a new one.
//   3. UserPromptSubmit: if the user submits `/clear`, wipes all sentinel files
//      for the current repo so the authorisation is reset mid-session.
//
// EXIT CODES
//   0  Allow (sentinel present and fresh, or non-commit event handled).
//   2  Block — no sentinel or expired; stderr shown to Claude.

"use strict";

const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");

const TTL_MS = 15 * 60 * 1000; // 15 minutes

function toSlug(s) {
  return s.replace(/[^a-zA-Z0-9]/g, "-").toLowerCase();
}

function getRepoSlug() {
  try {
    const root = execSync("git rev-parse --show-toplevel", {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
    return toSlug(path.basename(root));
  } catch {
    return null;
  }
}

function getSentinelPath() {
  try {
    const root = execSync("git rev-parse --show-toplevel", {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
    const repoSlug = toSlug(path.basename(root));
    const branch = execSync("git branch --show-current", {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
    if (!branch) return null; // detached HEAD
    const branchSlug = toSlug(branch);
    return `/tmp/claude-commit-auth-${repoSlug}-${branchSlug}`;
  } catch {
    return null;
  }
}

// Wipe all /tmp/claude-commit-auth-<prefix>-* sentinel files.
// Called on SessionStart (prefix = repo slug) and UserPromptSubmit /clear (prefix = empty = all).
function wipeCommitSentinels(prefix) {
  try {
    const files = fs.readdirSync("/tmp");
    for (const f of files) {
      if (f.startsWith(prefix ? `claude-commit-auth-${prefix}-` : "claude-commit-auth-")) {
        try {
          fs.unlinkSync(path.join("/tmp", f));
        } catch {
          // best-effort
        }
      }
    }
  } catch {
    // /tmp not readable — ignore
  }
}

let raw = "";
process.stdin.on("data", (chunk) => (raw += chunk));
process.stdin.on("end", () => {
  let data;
  try {
    data = JSON.parse(raw);
  } catch {
    process.exit(0);
  }

  const { hook_event_name, tool_name, tool_input } = data;

  // --- SessionStart: wipe leftover sentinels from prior sessions ---
  if (hook_event_name === "SessionStart") {
    const repoSlug = getRepoSlug();
    if (repoSlug) wipeCommitSentinels(repoSlug);
    process.exit(0);
  }

  // --- UserPromptSubmit: wipe sentinels when user runs /clear ---
  if (hook_event_name === "UserPromptSubmit") {
    const prompt = (data.prompt || data.user_message || "").trim();
    if (/^\/clear\b/.test(prompt)) {
      const repoSlug = getRepoSlug();
      if (repoSlug) wipeCommitSentinels(repoSlug);
    }
    process.exit(0);
  }

  // --- PreToolUse: guard git commit ---
  if (tool_name !== "Bash") process.exit(0);

  const command = (tool_input && tool_input.command) || "";
  if (!/^\s*git commit\b/.test(command)) process.exit(0);

  const sentinel = getSentinelPath();
  if (!sentinel) {
    process.stderr.write(
      "git commit blocked — could not determine repo/branch for authorization check.\n" +
        "Ensure you are inside a git repository on a named branch (not detached HEAD).\n",
    );
    process.exit(2);
  }

  let stat;
  try {
    stat = fs.statSync(sentinel);
  } catch {
    process.stderr.write(
      `git commit blocked — no commit authorization for this branch.\n` +
        `Skills like /oss:resolve and /research:run set this automatically.\n` +
        `For ad-hoc commits: invoke AskUserQuestion to confirm, ` +
        `then touch ${sentinel} before git commit, rm -f ${sentinel} after.\n`,
    );
    process.exit(2);
  }

  const ageMs = Date.now() - stat.mtimeMs;
  if (ageMs > TTL_MS) {
    try {
      fs.unlinkSync(sentinel);
    } catch {
      // best-effort cleanup
    }
    process.stderr.write(
      `git commit blocked — authorization expired (15-min TTL).\n` +
        `Re-run the skill or touch ${sentinel} after user confirmation.\n`,
    );
    process.exit(2);
  }

  process.exit(0);
});

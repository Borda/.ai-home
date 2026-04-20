/**
 * commit-guard.js — PreToolUse hook
 *
 * Blocks `git commit` unless a sentinel file exists at:
 *   /tmp/claude-commit-authorized
 *
 * Skills that legitimately commit (resolve, research:run) create this file
 * at the start of their commit phase and delete it afterwards via bash:
 *   touch /tmp/claude-commit-authorized
 *   rm -f /tmp/claude-commit-authorized
 *
 * Note: session_id is available to hooks (stdin JSON) but NOT to bash commands
 * run by skills. Fixed path is intentional — avoids session_id dependency while
 * keeping the single-user workstation assumption (no cross-session contamination).
 *
 * TTL: 15 min — auto-expires if a skill crashes without cleanup.
 *
 * Exit 0 = allow  |  Exit 2 = block (Claude Code shows stderr as feedback)
 */

"use strict";

const fs = require("fs");

const TTL_MS = 15 * 60 * 1000; // 15 minutes
const SENTINEL = "/tmp/claude-commit-authorized";

let raw = "";
process.stdin.on("data", (chunk) => (raw += chunk));
process.stdin.on("end", () => {
  let data;
  try {
    data = JSON.parse(raw);
  } catch {
    // Unparsable input — fail open, don't block Claude
    process.exit(0);
  }

  const { tool_name, tool_input } = data;

  // Only care about Bash calls
  if (tool_name !== "Bash") process.exit(0);

  const command = (tool_input && tool_input.command) || "";

  // Only intercept git commit
  if (!/^\s*git commit\b/.test(command)) process.exit(0);

  const sentinel = SENTINEL;

  // Check existence
  let stat;
  try {
    stat = fs.statSync(sentinel);
  } catch {
    // Sentinel missing — block
    process.stderr.write(
      "git commit blocked — no skill workflow has authorized commits this session.\n" +
        "Skills like /resolve and /research:run set this automatically.\n" +
        "For ad-hoc commits, include an explicit commit request in your current message.\n",
    );
    process.exit(2);
  }

  // Check TTL
  const ageMs = Date.now() - stat.mtimeMs;
  if (ageMs > TTL_MS) {
    try {
      fs.unlinkSync(sentinel);
    } catch {
      // best-effort cleanup
    }
    process.stderr.write(
      "git commit blocked — commit authorization expired (15-min TTL).\n" +
        "Re-run the skill or include an explicit commit request in your current message.\n",
    );
    process.exit(2);
  }

  // Sentinel valid — allow
  process.exit(0);
});

#!/usr/bin/env node
// md-compress.js — PreToolUse hook
//
// PURPOSE
//   Intercepts Read tool calls on .md/.markdown files and compresses
//   token-wasteful whitespace before Claude sees the content. Three
//   compressions are applied (all outside fenced code blocks):
//     1. Table column padding: collapses 2+ spaces on pipe-table lines to 1.
//     2. Multiple consecutive blank lines: collapses runs of 2+ blank lines
//        to a single blank line (identical rendering in all markdown parsers).
//     3. Trailing whitespace: strips trailing spaces on every non-fence line
//        (double-space <br> markers are not used in .claude/ config files).
//   Compressed content is written to a stable temp file keyed by a SHA-256
//   hash of the source path. The temp file is reused when its mtime is newer
//   than the source, avoiding redundant I/O for repeated reads in a session.
//
// HOW IT WORKS
//   1. Parse stdin JSON for tool_name and tool_input.
//   2. Skip non-Read tools or files that are not .md/.markdown (exit 0).
//   3. Read the source file synchronously; skip on any error (exit 0).
//   4. Walk lines, tracking fenced code block state (``` / ~~~).
//   5. Outside a fence: strip trailing whitespace, compress table padding,
//      and track consecutive blank lines — flush only one blank per run.
//   6. Derive stable temp path: /tmp/cc-md-compact-<sha256[:12]>.md
//   7. Reuse cached temp file if newer than source (mtime check).
//   8. Write compressed content and emit hookSpecificOutput with
//      permissionDecision:"allow" and updatedInput (temp path replaces
//      file_path; offset/limit/pages preserved verbatim).
//
// EXIT CODES
//   0  passthrough (non-.md file, read error, or successful rewrite)

"use strict";

const fs = require("fs");
const crypto = require("crypto");
const path = require("path");
const os = require("os");

/**
 * Compress markdown content:
 *  - Outside fenced code blocks:
 *    • Strip trailing whitespace from each line
 *    • On pipe-table lines: collapse runs of 2+ spaces to 1
 *    • Collapse runs of 2+ consecutive blank lines to 1
 *
 * @param {string} content
 * @returns {string}
 */
function compressMarkdown(content) {
  const lines = content.split("\n");
  const out = [];
  let inFence = false;
  let fenceChar = "";
  let consecutiveBlanks = 0;

  for (const line of lines) {
    const trimmed = line.trimStart();

    // --- Fence tracking ---
    if (!inFence) {
      const m = trimmed.match(/^(`{3,}|~{3,})/);
      if (m) {
        inFence = true;
        fenceChar = m[1][0];
        consecutiveBlanks = 0;
        out.push(line); // preserve fence line as-is
        continue;
      }
    } else {
      const m = trimmed.match(/^(`{3,}|~{3,})/);
      if (m && m[1][0] === fenceChar) {
        inFence = false;
        fenceChar = "";
      }
      out.push(line); // preserve all content inside fence as-is
      continue;
    }

    // --- Outside fence ---

    // Strip trailing whitespace
    const stripped = line.trimEnd();

    // Blank line handling: collapse consecutive blank lines
    if (stripped === "") {
      consecutiveBlanks++;
      if (consecutiveBlanks <= 1) {
        out.push(""); // allow exactly one blank line through
      }
      // subsequent blanks in the same run are dropped
      continue;
    }

    consecutiveBlanks = 0;

    // Pipe-table lines: collapse internal padding (2+ spaces → 1)
    if (stripped.startsWith("|")) {
      out.push(stripped.replace(/ {2,}/g, " "));
    } else {
      out.push(stripped);
    }
  }

  return out.join("\n");
}

let raw = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (d) => (raw += d));
process.stdin.on("end", () => {
  try {
    const data = JSON.parse(raw);

    // Only handle Read tool calls
    if (data.tool_name !== "Read") {
      process.exit(0);
    }

    const input = data.tool_input || {};
    const filePath = input.file_path || "";

    // Only process markdown files
    if (!/\.(?:md|markdown)$/i.test(filePath)) {
      process.exit(0);
    }

    // Resolve absolute path
    const absPath = path.resolve(filePath);

    // Read source file and its mtime
    let content;
    let sourceMtime;
    try {
      content = fs.readFileSync(absPath, "utf8");
      sourceMtime = fs.statSync(absPath).mtimeMs;
    } catch (_) {
      process.exit(0); // unreadable — pass through unchanged
    }

    if (!content) {
      process.exit(0); // empty — nothing to compress
    }

    // Derive stable temp path from a hash of the absolute source path
    const hash = crypto.createHash("sha256").update(absPath).digest("hex").slice(0, 12);
    const tempPath = path.join(os.tmpdir(), `cc-md-compact-${hash}.md`);

    // Reuse cached temp file when it is newer than the source
    try {
      const tempMtime = fs.statSync(tempPath).mtimeMs;
      if (tempMtime > sourceMtime) {
        process.stdout.write(
          JSON.stringify({
            hookSpecificOutput: {
              hookEventName: "PreToolUse",
              permissionDecision: "allow",
              updatedInput: { ...input, file_path: tempPath },
            },
          }),
        );
        process.exit(0);
      }
    } catch (_) {
      // temp file absent — compress and write below
    }

    // Compress and write temp file
    const compressed = compressMarkdown(content);
    fs.writeFileSync(tempPath, compressed, "utf8");

    process.stdout.write(
      JSON.stringify({
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "allow",
          updatedInput: { ...input, file_path: tempPath },
        },
      }),
    );
    process.exit(0);
  } catch (_) {
    // Never crash or block Claude due to a hook bug
    process.exit(0);
  }
});

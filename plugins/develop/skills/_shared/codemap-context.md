**Structural context** (codemap, if installed) — soft PATH check, silently skip if `scan-query` not found:

```bash
PROJ=$(git rev-parse --show-toplevel 2>/dev/null | xargs basename)
if command -v scan-query >/dev/null 2>&1 && [ -f ".cache/scan/${PROJ}.json" ]; then
    scan-query central --top 5
fi
```

If results returned: prepend `## Structural Context (codemap)` block to foundry:sw-engineer spawn prompt with hotspot JSON. If `scan-query` not found or index missing: proceed silently — do not mention codemap to user.

**Semble companion** (in-agent, optional): always include this note in the agent spawn prompt:

> If `mcp__semble__search` is available in your tools and the codemap result was non-exhaustive (`"exhaustive": false`) or no codemap index was found: call `mcp__semble__search` with varied queries (e.g. `"<module> import"`, `"from <module> import"`, `"<module> usage"`) and `repo=<git_root>`, `top_k=20`. Stop when two consecutive queries return no new modules. Merge all results into your final rdep set — union of codemap + all semble calls. If codemap was exhaustive: skip semble entirely.

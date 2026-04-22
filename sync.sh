#!/usr/bin/env bash
# Sync local plugin changes to ~/.claude/
# Run from the project root: bash sync.sh [--clean]
#
# After this script completes, run /foundry:init inside Claude Code
# to merge settings.json and refresh symlinks.

set -e

PLUGINS=(foundry oss develop research codemap)
EXTERNAL_PLUGINS=(codex@openai-codex caveman@caveman)
MARKETPLACE=$(jq -r '.name' .claude-plugin/marketplace.json)
SETTINGS="$HOME/.claude/settings.json"
KNOWN_MARKETPLACES="$HOME/.claude/plugins/known_marketplaces.json"
INSTALLED_PLUGINS="$HOME/.claude/plugins/installed_plugins.json"
CACHE_DIR="$HOME/.claude/plugins/cache"
PROJECT_DIR="$(pwd)"

# Migrate all stale marketplace names registered for this path
# Checks known_marketplaces.json (authoritative CLI registry) for stale names
while IFS= read -r stale; do
    [[ -z "$stale" ]] && continue
    echo "Migrating marketplace '$stale' → '$MARKETPLACE'..."

    # 1. Rename cache dir (or remove stale if target already exists)
    if [[ -d "$CACHE_DIR/$stale" && ! -d "$CACHE_DIR/$MARKETPLACE" ]]; then
        mv "$CACHE_DIR/$stale" "$CACHE_DIR/$MARKETPLACE"
        echo "  ✓ cache dir renamed"
    elif [[ -d "$CACHE_DIR/$stale" ]]; then
        rm -rf "$CACHE_DIR/$stale"
        echo "  ✓ stale cache dir removed"
    fi

    # 2. known_marketplaces.json — rename marketplace key
    tmp=$(mktemp)
    jq --arg old "$stale" --arg new "$MARKETPLACE" '
      .[$new] = .[$old] | del(.[$old])
    ' "$KNOWN_MARKETPLACES" > "$tmp" && mv "$tmp" "$KNOWN_MARKETPLACES"

    # 3. installed_plugins.json — rename plugin keys + update installPath strings
    tmp=$(mktemp)
    jq --arg old "$stale" --arg new "$MARKETPLACE" '
      .plugins = (
        .plugins
        | with_entries(.key |= gsub($old; $new))
        | walk(if type == "string" then gsub($old; $new) else . end)
      )
    ' "$INSTALLED_PLUGINS" > "$tmp" && mv "$tmp" "$INSTALLED_PLUGINS"

    # 4. settings.json — remove stale entry + gsub all string occurrences
    tmp=$(mktemp)
    jq --arg old "$stale" --arg new "$MARKETPLACE" '
      del(.extraKnownMarketplaces[$old]) |
      walk(
        if type == "string" then gsub($old; $new)
        elif type == "object" then with_entries(.key |= gsub($old; $new))
        else .
        end
      )
    ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

    echo "  ✓ registries updated ($stale → $MARKETPLACE)"
done < <(jq -r --arg path "$PROJECT_DIR" --arg new "$MARKETPLACE" '
  to_entries
  | map(select(.value.source.path == $path and .key != $new))
  | .[].key
' "$KNOWN_MARKETPLACES")

if [[ "${1:-}" == "--clean" ]]; then
    echo "Uninstalling existing plugins..."
    for p in "${PLUGINS[@]}"; do
        claude plugin uninstall "${p}@${MARKETPLACE}" 2>/dev/null && echo "  ✓ uninstalled ${p}" || echo "  – ${p} not installed, skipping"
    done
fi

echo "Updating external plugins..."
for p in "${EXTERNAL_PLUGINS[@]}"; do
    claude plugin uninstall "$p" 2>/dev/null && echo "  ✓ uninstalled $p" || echo "  – $p not installed, skipping"
    claude plugin install "$p" && echo "  ✓ $p" || echo "  ✗ $p install failed"
done

echo "Registering marketplace..."
claude plugin marketplace add ./

echo "Installing plugins..."
for p in "${PLUGINS[@]}"; do
    claude plugin install "${p}@${MARKETPLACE}" && echo "  ✓ ${p}"
done

echo "Initializing Foundry (sync settings + symlinks)..."
claude "/foundry:init --approve"

echo "✓ Done"

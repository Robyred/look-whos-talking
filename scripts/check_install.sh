#!/usr/bin/env bash
# Usage: bash scripts/check_install.sh <package>
# Shows what pip WOULD install/uninstall without touching the environment.
# Flags any downgrade of torch, pyannote, or fastapi as a warning.

set -euo pipefail
PACKAGE="${1:?Usage: $0 <package>}"

echo "=== Dry-run: pip install $PACKAGE ==="
OUTPUT=$(pip install "$PACKAGE" --dry-run 2>&1)
echo "$OUTPUT"

echo ""
echo "=== Risk check ==="
UNINSTALL=$(echo "$OUTPUT" | grep -i "Would uninstall\|Uninstalling" || true)
DOWNGRADE=$(echo "$OUTPUT" | grep -i "downgrad" || true)
CRITICAL=$(echo "$OUTPUT" | grep -iE "torch|pyannote|fastapi|pydantic" | grep -iE "Would uninstall|Uninstalling|downgrad" || true)

if [ -n "$CRITICAL" ]; then
  echo "⚠️  CRITICAL PACKAGES AFFECTED:"
  echo "$CRITICAL"
  echo ""
  echo "Do NOT proceed without understanding these changes."
elif [ -n "$UNINSTALL" ]; then
  echo "⚠️  Packages would be uninstalled:"
  echo "$UNINSTALL"
  echo ""
  echo "Review before proceeding."
else
  echo "✅ No uninstalls detected — looks safe."
fi

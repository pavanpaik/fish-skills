#!/bin/bash
set -euo pipefail

# Only run in remote (Claude Code on the web) environments
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# Ensure pnpm is available
if ! command -v pnpm &>/dev/null; then
  npm install -g pnpm
fi

# Install dependencies if a pnpm-lock.yaml is present
if [ -f "$CLAUDE_PROJECT_DIR/pnpm-lock.yaml" ]; then
  cd "$CLAUDE_PROJECT_DIR"
  pnpm install
fi

echo "Session start hook complete."

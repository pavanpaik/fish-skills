#!/bin/bash
set -euo pipefail

# Manual build and release script for the skills CLI binaries.
# Requires: git, node, pnpm, gh (GitHub CLI)
#
# Usage:
#   ./scripts/release.sh              # uses upstream version from package.json
#   ./scripts/release.sh v1.5.0      # override the release tag

REPO="pavanpaik/fish-skills"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# ── Helpers ───────────────────────────────────────────────────────────────────

info()  { echo "  $*"; }
step()  { echo ""; echo "==> $*"; }
die()   { echo "ERROR: $*" >&2; exit 1; }

# ── Prerequisites ─────────────────────────────────────────────────────────────

step "Checking prerequisites"
for cmd in git node pnpm gh npx; do
  command -v "$cmd" &>/dev/null && info "$cmd ✓" || die "'$cmd' not found. Please install it first."
done

gh auth status &>/dev/null || die "Not logged in to GitHub CLI. Run: gh auth login"

# ── Clone and build ───────────────────────────────────────────────────────────

step "Cloning vercel-labs/skills"
git clone --depth 1 https://github.com/vercel-labs/skills "$WORK_DIR/skills"

step "Installing dependencies"
cd "$WORK_DIR/skills"
pnpm install

step "Building (TypeScript → JS)"
pnpm build

# ── Determine version ─────────────────────────────────────────────────────────

UPSTREAM_VERSION="$(node -p "require('./package.json').version")"
TAG="${1:-v${UPSTREAM_VERSION}}"
info "Release tag: $TAG"

# ── Bundle for pkg ────────────────────────────────────────────────────────────

step "Bundling into single CJS file (esbuild)"
npx esbuild dist/cli.mjs \
  --bundle \
  --platform=node \
  --format=cjs \
  --outfile=bundle.cjs \
  --external:fsevents

# ── Compile binaries ──────────────────────────────────────────────────────────

step "Compiling standalone binaries"
mkdir -p dist-bin
npx @yao-pkg/pkg bundle.cjs \
  --targets node20-macos-arm64,node20-macos-x64,node20-linux-x64,node20-win-x64 \
  --out-path ./dist-bin

# Rename to friendly names
cd dist-bin
mv bundle-macos-arm64  skills-macos-arm64  2>/dev/null || true
mv bundle-macos-x64    skills-macos-x64    2>/dev/null || true
mv bundle-linux-x64    skills-linux-x64    2>/dev/null || true
mv bundle-win-x64.exe  skills-win-x64.exe  2>/dev/null || true
cd ..

step "Built binaries:"
ls -lh dist-bin/

# ── Create GitHub release ─────────────────────────────────────────────────────

step "Creating GitHub release $TAG"
gh release create "$TAG" \
  --repo "$REPO" \
  --title "skills $TAG" \
  --notes "$(cat <<EOF
Standalone binaries for [vercel-labs/skills](https://github.com/vercel-labs/skills).

## Installation

\`\`\`bash
curl -fsSL https://raw.githubusercontent.com/${REPO}/main/install.sh | bash
\`\`\`

## Manual download

| Platform      | Binary               |
| ------------- | -------------------- |
| macOS (Apple) | \`skills-macos-arm64\` |
| macOS (Intel) | \`skills-macos-x64\`   |
| Linux x64     | \`skills-linux-x64\`   |
| Windows x64   | \`skills-win-x64.exe\` |
EOF
)" \
  dist-bin/*

echo ""
echo "Released: https://github.com/${REPO}/releases/tag/${TAG}"

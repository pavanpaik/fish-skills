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

# ── Bundle ────────────────────────────────────────────────────────────────────

step "Bundling into single CJS file (esbuild)"
npx --yes esbuild dist/cli.mjs \
  --bundle \
  --platform=node \
  --format=cjs \
  --outfile=bundle.cjs \
  --external:fsevents

# ── Patch bundle for binary compatibility ─────────────────────────────────────
# Three import.meta.url usages break at runtime inside a pkg snapshot:
#   1. createRequire(import_meta.url)         → createRequire(__filename)
#   2. var __dirname = dirname(fileURLToPath(import_meta2.url))
#                                             → dirname(__filename)  (CJS native)
#   3. getVersion() reads package.json via __dirname — hardcode the version instead

step "Patching bundle for pkg compatibility"
node << PATCH
const fs = require('fs');
const version = '$UPSTREAM_VERSION';
let src = fs.readFileSync('bundle.cjs', 'utf-8');

// Patch 1: fix createRequire
if (!src.includes('createRequire)(import_meta.url)')) {
  console.error('Patch 1: target not found'); process.exit(1);
}
src = src.replace('createRequire)(import_meta.url)', 'createRequire)(__filename)');
console.log('  Patch 1: createRequire(__filename) ✓');

// Patch 2: fix module-level __dirname declaration
const badDirname = /var __dirname = \(0, import_path2\.dirname\)\(\(0, import_url\.fileURLToPath\)\(import_meta2\.url\)\);/;
if (!badDirname.test(src)) { console.error('Patch 2: target not found'); process.exit(1); }
src = src.replace(badDirname, 'var __dirname = require("path").dirname(__filename);');
console.log('  Patch 2: __dirname = dirname(__filename) ✓');

// Patch 3: hardcode version (brace-counting to capture the full function)
const funcStart = src.indexOf('function getVersion()');
if (funcStart === -1) { console.error('Patch 3: getVersion not found'); process.exit(1); }
let depth = 0, i = funcStart, started = false;
while (i < src.length) {
  if (src[i] === '{') { depth++; started = true; }
  if (src[i] === '}') { depth--; if (started && depth === 0) break; }
  i++;
}
src = src.slice(0, funcStart) +
  'function getVersion() { return "' + version + '"; }' +
  src.slice(i + 1);
console.log('  Patch 3: getVersion() → "' + version + '" ✓');

// Verify no stray import_meta.url accesses remain
const remaining = (src.match(/import_meta[0-9]*\.url/g) || []);
if (remaining.length > 0) { console.error('Unpatched import_meta.url accesses:', remaining.length); process.exit(1); }

fs.writeFileSync('bundle.cjs', src);
console.log('  All patches applied successfully.');
PATCH

# ── Compile binaries ──────────────────────────────────────────────────────────

step "Compiling standalone binaries"
mkdir -p dist-bin
npx --yes @yao-pkg/pkg bundle.cjs \
  --targets node20-macos-arm64,node20-macos-x64,node20-linux-x64,node20-win-x64 \
  --out-path ./dist-bin

# Rename to friendly names
cd dist-bin
mv bundle-macos-arm64  skills-macos-arm64  2>/dev/null || true
mv bundle-macos-x64    skills-macos-x64    2>/dev/null || true
mv bundle-linux-x64    skills-linux-x64    2>/dev/null || true
mv bundle-win-x64.exe  skills-win-x64.exe  2>/dev/null || true
cd ..

# ── Code sign macOS binaries ──────────────────────────────────────────────────
#
# Set CODESIGN_IDENTITY to use a Developer ID certificate for public releases:
#
#   export CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#   ./scripts/release.sh
#
# To obtain an identity:
#   1. Enroll at developer.apple.com/programs ($99/year)
#   2. In Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application
#      OR generate a CSR with openssl, upload at developer.apple.com, install the .cer
#   3. Run: security find-identity -v -p codesigning
#      Copy the string in quotes — that is your CODESIGN_IDENTITY value.
#
# Without CODESIGN_IDENTITY the script falls back to ad-hoc signing (-).
# Ad-hoc binaries require users to run:
#   xattr -d com.apple.quarantine ./skills-macos-arm64
#
# See README.md for full notarization instructions.

step "Code signing macOS binaries"
OS="$(uname -s)"
IDENTITY="${CODESIGN_IDENTITY:--}"   # default: ad-hoc (-)

if [ "$OS" = "Darwin" ]; then
  codesign --sign "$IDENTITY" --options runtime --timestamp \
    dist-bin/skills-macos-arm64
  codesign --sign "$IDENTITY" --options runtime --timestamp \
    dist-bin/skills-macos-x64
  if [ "$IDENTITY" = "-" ]; then
    info "Signed (ad-hoc). For public releases set CODESIGN_IDENTITY. See README.md."
  else
    info "Signed with: $IDENTITY"
  fi
elif command -v ldid &>/dev/null; then
  ldid -S dist-bin/skills-macos-arm64
  ldid -S dist-bin/skills-macos-x64
  info "Signed with ldid (ad-hoc, Linux fallback)"
else
  echo ""
  echo "  ⚠ WARNING: macOS binaries are unsigned."
  echo "  They will be killed immediately on macOS unless signed."
  echo "  Options:"
  echo "    - Run this script on macOS (codesign is used automatically)"
  echo "    - Install ldid: apt install ldid"
  echo "    - See README.md for Developer ID signing instructions"
  echo ""
fi

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

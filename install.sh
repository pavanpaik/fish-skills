#!/bin/bash
set -euo pipefail

# Installer for the `skills` CLI binary
# Usage: curl -fsSL https://raw.githubusercontent.com/pavanpaik/fish-skills/main/install.sh | bash

REPO="pavanpaik/fish-skills"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/main"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"

# ── Detect OS and architecture ────────────────────────────────────────────────

OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
  Linux)
    case "$ARCH" in
      x86_64) TARGET="linux-x64" ;;
      *)      echo "Unsupported architecture: $ARCH"; exit 1 ;;
    esac
    ;;
  Darwin)
    case "$ARCH" in
      arm64)  TARGET="macos-arm64" ;;
      x86_64) TARGET="macos-x64" ;;
      *)      echo "Unsupported architecture: $ARCH"; exit 1 ;;
    esac
    ;;
  MINGW*|MSYS*|CYGWIN*|Windows_NT)
    TARGET="win-x64"
    ;;
  *)
    echo "Unsupported OS: $OS"
    exit 1
    ;;
esac

INSTALL_NAME="skills"
[ "$TARGET" = "win-x64" ] && INSTALL_NAME="skills.exe"

TMP_FILE="$(mktemp)"
trap 'rm -f "$TMP_FILE"' EXIT

# ── Install helper ────────────────────────────────────────────────────────────

do_install() {
  if [ -w "$INSTALL_DIR" ]; then
    mv "$TMP_FILE" "${INSTALL_DIR}/${INSTALL_NAME}"
    echo "Installed to ${INSTALL_DIR}/${INSTALL_NAME}"
  else
    local fallback="${HOME}/.local/bin"
    mkdir -p "$fallback"
    mv "$TMP_FILE" "${fallback}/${INSTALL_NAME}"
    echo "Installed to ${fallback}/${INSTALL_NAME}"
    if [[ ":$PATH:" != *":${fallback}:"* ]]; then
      echo ""
      echo "Note: ${fallback} is not in your PATH."
      echo "Add this to your shell profile (~/.bashrc, ~/.zshrc, etc.):"
      echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    fi
  fi
  echo ""
  echo "skills installed successfully. Run: ${INSTALL_NAME} --help"
}

# ── macOS: serve directly from repo (deprecated fallback pattern) ─────────────
#
# macOS binaries are committed to dist/mac/ in the repo so installation works
# without needing access to GitHub Releases. This grows repo history by ~45-50 MB
# per binary per release update — prefer GitHub Releases when available.

if [ "$OS" = "Darwin" ]; then
  REPO_URL="${RAW_BASE}/dist/mac/skills-${TARGET}"
  echo "Downloading skills (macOS ${ARCH})..."
  if curl -fsSL --progress-bar -o "$TMP_FILE" "$REPO_URL" 2>/dev/null; then
    chmod +x "$TMP_FILE"
    # Strip quarantine attribute macOS applies to files downloaded outside the App Store
    xattr -d com.apple.quarantine "$TMP_FILE" 2>/dev/null || true
    do_install
    exit 0
  fi
  echo "Repo binary unavailable, falling back to GitHub Releases..."
fi

# ── Linux / Windows / macOS fallback: GitHub Releases ────────────────────────

ASSET_NAME="skills-${TARGET}"
[ "$TARGET" = "win-x64" ] && ASSET_NAME="${ASSET_NAME}.exe"

echo "Fetching latest release from ${REPO}..."
RELEASE_JSON="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest")"
TAG="$(echo "$RELEASE_JSON" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')"
DOWNLOAD_URL="$(echo "$RELEASE_JSON" | grep "browser_download_url" | grep "${ASSET_NAME}" | head -1 | sed 's/.*"browser_download_url": *"\([^"]*\)".*/\1/')"

if [ -z "$DOWNLOAD_URL" ]; then
  echo "Could not find a binary for ${ASSET_NAME} in release ${TAG}."
  echo "Available assets:"
  echo "$RELEASE_JSON" | grep "browser_download_url" | sed 's/.*"browser_download_url": *"\([^"]*\)".*/  \1/'
  exit 1
fi

echo "Downloading skills ${TAG} (${TARGET})..."
curl -fsSL --progress-bar -o "$TMP_FILE" "$DOWNLOAD_URL"
chmod +x "$TMP_FILE"
do_install

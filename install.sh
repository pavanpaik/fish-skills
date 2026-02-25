#!/bin/bash
set -euo pipefail

# Installer for the `skills` CLI binary
# Usage: curl -fsSL https://raw.githubusercontent.com/pavanpaik/fish-skills/main/install.sh | bash

REPO="pavanpaik/fish-skills"
BINARY_NAME="skills"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"

# ── Detect OS and architecture ────────────────────────────────────────────────

OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
  Linux)
    case "$ARCH" in
      x86_64) TARGET="linux-x64" ;;
      *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
    esac
    ;;
  Darwin)
    case "$ARCH" in
      arm64) TARGET="macos-arm64" ;;
      x86_64) TARGET="macos-x64" ;;
      *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
    esac
    ;;
  MINGW*|MSYS*|CYGWIN*|Windows_NT)
    TARGET="win-x64"
    BINARY_NAME="skills.exe"
    ;;
  *)
    echo "Unsupported OS: $OS"
    exit 1
    ;;
esac

# ── Resolve latest release ────────────────────────────────────────────────────

RELEASE_URL="https://api.github.com/repos/${REPO}/releases/latest"
ASSET_NAME="${BINARY_NAME%-*}-${TARGET}"
[ "$OS" = "Windows_NT" ] || [[ "$OS" == MINGW* ]] && ASSET_NAME="${ASSET_NAME}.exe" || true

echo "Fetching latest release from ${REPO}..."
RELEASE_JSON="$(curl -fsSL "$RELEASE_URL")"

TAG="$(echo "$RELEASE_JSON" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')"
DOWNLOAD_URL="$(echo "$RELEASE_JSON" | grep "browser_download_url" | grep "${ASSET_NAME}" | head -1 | sed 's/.*"browser_download_url": *"\([^"]*\)".*/\1/')"

if [ -z "$DOWNLOAD_URL" ]; then
  echo "Could not find a binary for ${ASSET_NAME} in release ${TAG}."
  echo "Available assets:"
  echo "$RELEASE_JSON" | grep "browser_download_url" | sed 's/.*"browser_download_url": *"\([^"]*\)".*/  \1/'
  exit 1
fi

# ── Download and install ──────────────────────────────────────────────────────

TMP_FILE="$(mktemp)"
trap 'rm -f "$TMP_FILE"' EXIT

echo "Downloading skills ${TAG} (${TARGET})..."
curl -fsSL --progress-bar -o "$TMP_FILE" "$DOWNLOAD_URL"

chmod +x "$TMP_FILE"

# Install to INSTALL_DIR; fall back to ~/.local/bin if not writable
if [ -w "$INSTALL_DIR" ]; then
  mv "$TMP_FILE" "${INSTALL_DIR}/skills"
  echo "Installed to ${INSTALL_DIR}/skills"
else
  INSTALL_DIR="${HOME}/.local/bin"
  mkdir -p "$INSTALL_DIR"
  mv "$TMP_FILE" "${INSTALL_DIR}/skills"
  echo "Installed to ${INSTALL_DIR}/skills"
  if [[ ":$PATH:" != *":${INSTALL_DIR}:"* ]]; then
    echo ""
    echo "Note: ${INSTALL_DIR} is not in your PATH."
    echo "Add this to your shell profile (~/.bashrc, ~/.zshrc, etc.):"
    echo ""
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
  fi
fi

echo ""
echo "skills ${TAG} installed successfully."
echo "Run: skills --help"

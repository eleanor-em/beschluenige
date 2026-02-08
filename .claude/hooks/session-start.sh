#!/bin/bash
set -euo pipefail

# Only run in remote (Claude Code on the web) environments
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

SWIFTLINT_VERSION="0.63.2"
SWIFTLINT_BIN="/usr/local/bin/swiftlint"

# Install SwiftLint if not present or wrong version
if command -v swiftlint &>/dev/null && swiftlint version 2>/dev/null | grep -q "$SWIFTLINT_VERSION"; then
  echo "SwiftLint $SWIFTLINT_VERSION already installed"
else
  echo "Installing SwiftLint $SWIFTLINT_VERSION..."
  TMPDIR=$(mktemp -d)
  curl -fsSL "https://github.com/realm/SwiftLint/releases/download/${SWIFTLINT_VERSION}/swiftlint_linux_amd64.zip" \
    -o "$TMPDIR/swiftlint.zip"
  unzip -o "$TMPDIR/swiftlint.zip" -d "$TMPDIR"
  # The static binary works without any runtime dependencies
  if [ -f "$TMPDIR/swiftlint-static" ]; then
    install -m 755 "$TMPDIR/swiftlint-static" "$SWIFTLINT_BIN"
  elif [ -f "$TMPDIR/swiftlint" ]; then
    install -m 755 "$TMPDIR/swiftlint" "$SWIFTLINT_BIN"
  else
    echo "Error: swiftlint binary not found in archive"
    ls -la "$TMPDIR"
    rm -rf "$TMPDIR"
    exit 1
  fi
  rm -rf "$TMPDIR"
  echo "SwiftLint $(swiftlint version) installed"
fi

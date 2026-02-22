#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="VoiSER"
BUNDLE_ID="${BUNDLE_ID:-io.voiser.app}"
RESET_ACCESSIBILITY="${RESET_ACCESSIBILITY:-1}"
SOURCE_APP="$ROOT_DIR/dist/$APP_NAME.app"
TARGET_DIR="/Applications"

"$ROOT_DIR/scripts/package-app.sh"

pkill -x VoiSER 2>/dev/null || true

if [[ ! -w "$TARGET_DIR" ]]; then
  TARGET_DIR="$HOME/Applications"
  mkdir -p "$TARGET_DIR"
fi

TARGET_APP="$TARGET_DIR/$APP_NAME.app"
rm -rf "$TARGET_APP"
cp -R "$SOURCE_APP" "$TARGET_APP"

if command -v xattr >/dev/null 2>&1; then
  xattr -cr "$TARGET_APP" 2>/dev/null || true
  xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true
  xattr -d com.apple.FinderInfo "$TARGET_APP" 2>/dev/null || true
fi

if [[ "${SIGN_APP:-1}" == "1" ]]; then
  if ! codesign --verify --deep --strict "$TARGET_APP" >/dev/null 2>&1; then
    echo "Install failed: copied app has invalid signature. Aborting to prevent broken Accessibility permissions." >&2
    exit 1
  fi
fi

if [[ "$RESET_ACCESSIBILITY" == "1" ]]; then
  if command -v tccutil >/dev/null 2>&1; then
    tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true
    echo "Accessibility permission reset for $BUNDLE_ID (re-grant required on first paste)."
  fi
fi

open "$TARGET_APP"

echo "Installed: $TARGET_APP"

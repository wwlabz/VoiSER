#!/usr/bin/env bash
set -euo pipefail

APP_PATH="/Applications/VoiSER.app"
DOMAINS=("io.voiser.app" "VoiSER")

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found at $APP_PATH"
  exit 1
fi

echo "Killing old instances..."
pkill -x VoiSER 2>/dev/null || true

if [[ "${RESET_SETTINGS:-0}" == "1" ]]; then
  echo "Resetting saved settings..."
  for domain in "${DOMAINS[@]}"; do
    defaults delete "$domain" 2>/dev/null || true
  done
fi

echo "Clearing quarantine..."
xattr -cr "$APP_PATH" 2>/dev/null || true
xattr -dr com.apple.quarantine "$APP_PATH" 2>/dev/null || true
xattr -d com.apple.FinderInfo "$APP_PATH" 2>/dev/null || true

echo "Launching app..."
open -a "$APP_PATH"
sleep 2

if pgrep -x VoiSER >/dev/null; then
  echo "OK: VoiSER process is running."
else
  echo "FAIL: process did not start."
  exit 1
fi

echo "Tip: app now shows Dock icon + menu bar icon."

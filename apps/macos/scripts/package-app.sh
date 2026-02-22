#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="VoiSER"
BUNDLE_ID="${BUNDLE_ID:-io.voiser.app}"
VERSION="${VERSION:-1.0.0}"
BUILD_CONFIG="${BUILD_CONFIG:-release}"
SIGN_APP="${SIGN_APP:-1}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
ALLOW_UNSIGNED_FALLBACK="${ALLOW_UNSIGNED_FALLBACK:-0}"
MODEL_VARIANT="${MODEL_VARIANT:-openai_whisper-small}"
INCLUDE_BUNDLED_MODEL="${INCLUDE_BUNDLED_MODEL:-0}"

BUILD_DIR=""
BINARY_PATH=""
DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$DIST_DIR/$APP_NAME.app"
STAGE_DIR="$(mktemp -d /tmp/${APP_NAME}.package.XXXXXX)"
APP_STAGE_PATH="$STAGE_DIR/$APP_NAME.app"
trap 'rm -rf "$STAGE_DIR"' EXIT
CONTENTS_PATH="$APP_STAGE_PATH/Contents"
MACOS_PATH="$CONTENTS_PATH/MacOS"
ICON_SOURCE="$ROOT_DIR/Sources/VoiceWidget/Resources/AppIcon.icns"
MODEL_DIR="$ROOT_DIR/Sources/VoiceWidget/Resources/Models/$MODEL_VARIANT"

mkdir -p "$DIST_DIR"

if [[ "$INCLUDE_BUNDLED_MODEL" == "1" ]]; then
  if [[ ! -d "$MODEL_DIR" ]]; then
    echo "[0/6] Model '$MODEL_VARIANT' not found, downloading for bundle..."
    "$ROOT_DIR/scripts/embed-whisper-base.sh" "$MODEL_VARIANT"
  else
    echo "[0/6] Model '$MODEL_VARIANT' already present for bundling."
  fi
else
  echo "[0/6] Bundled Whisper model is disabled (default)."
  echo "      App will auto-download Whisper on first launch."
fi

echo "[1/6] Building $APP_NAME ($BUILD_CONFIG)..."
BUILD_DIR="$(swift build -c "$BUILD_CONFIG" --product "$APP_NAME" --show-bin-path)"
BINARY_PATH="$BUILD_DIR/$APP_NAME"

if [[ ! -x "$BINARY_PATH" ]]; then
  echo "Unable to find built binary at $BINARY_PATH" >&2
  exit 1
fi

echo "[2/6] Creating app bundle..."
rm -rf "$APP_STAGE_PATH"
mkdir -p "$MACOS_PATH" "$CONTENTS_PATH/Resources"
COPYFILE_DISABLE=1 cp "$BINARY_PATH" "$MACOS_PATH/$APP_NAME"
chmod +x "$MACOS_PATH/$APP_NAME"

echo "[3/6] Embedding SwiftPM resource bundles..."
shopt -s nullglob
BUNDLES=("$BUILD_DIR"/*.bundle)
if [[ "${#BUNDLES[@]}" -eq 0 ]]; then
  echo "No resource bundles found in $BUILD_DIR" >&2
  exit 1
fi
for bundle in "${BUNDLES[@]}"; do
  ditto --noextattr --noqtn "$bundle" "$CONTENTS_PATH/Resources/$(basename "$bundle")"
  echo "  - $(basename "$bundle")"
done
shopt -u nullglob

echo "[4/6] Writing Info.plist..."
cat > "$CONTENTS_PATH/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <false/>
  <key>NSMicrophoneUsageDescription</key>
  <string>VoiSER uses microphone input for speech recording and local transcription.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

echo "APPL????" > "$CONTENTS_PATH/PkgInfo"
plutil -lint "$CONTENTS_PATH/Info.plist" >/dev/null

if [[ -f "$ICON_SOURCE" ]]; then
  ditto --noextattr --noqtn "$ICON_SOURCE" "$CONTENTS_PATH/Resources/AppIcon.icns"
fi

echo "[5/6] Finishing bundle..."
if command -v xattr >/dev/null 2>&1; then
  xattr -cr "$APP_STAGE_PATH" 2>/dev/null || true
  xattr -dr com.apple.quarantine "$APP_STAGE_PATH" 2>/dev/null || true
  xattr -d com.apple.FinderInfo "$APP_STAGE_PATH" 2>/dev/null || true
fi
find "$APP_STAGE_PATH" -name ".DS_Store" -delete 2>/dev/null || true

if [[ "$SIGN_APP" == "1" ]]; then
  SIGN_ID="$CODESIGN_IDENTITY"

  if [[ -z "$SIGN_ID" ]]; then
    if command -v security >/dev/null 2>&1; then
      SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development:/{print $2; exit}')"
      if [[ -z "$SIGN_ID" ]]; then
        SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null | awk '/[0-9A-F]{40}/ {print $2; exit}')"
      fi
    fi
  fi

  if [[ -z "$SIGN_ID" ]]; then
    SIGN_ID="-"
  fi

  if [[ "$SIGN_ID" == "-" ]]; then
    echo "Attempting ad-hoc codesign (SIGN_APP=1, identity='-')..."
    echo "Warning: ad-hoc signature changes cdhash every build; Accessibility/Automation permissions may be requested again." >&2
  else
    echo "Attempting codesign with identity: $SIGN_ID"
  fi

  if ! codesign --force --deep --sign "$SIGN_ID" --timestamp=none "$APP_STAGE_PATH"; then
    if [[ "$ALLOW_UNSIGNED_FALLBACK" == "1" ]]; then
      echo "Warning: codesign failed. Continuing because ALLOW_UNSIGNED_FALLBACK=1." >&2
    else
      echo "Error: codesign failed. Refusing to produce unsigned app because this breaks macOS Accessibility trust." >&2
      echo "Fix signing (or set ALLOW_UNSIGNED_FALLBACK=1 explicitly if you know what you are doing)." >&2
      exit 1
    fi
  fi

  if ! codesign --verify --deep --strict "$APP_STAGE_PATH" >/dev/null 2>&1; then
    if [[ "$ALLOW_UNSIGNED_FALLBACK" == "1" ]]; then
      echo "Warning: signature verification failed. Continuing because ALLOW_UNSIGNED_FALLBACK=1." >&2
    else
      echo "Error: signature verification failed. Build aborted to avoid invalid TCC/Accessibility state." >&2
      exit 1
    fi
  fi
else
  echo "Warning: SIGN_APP=0. Unsinged builds can invalidate Accessibility trust after updates." >&2
fi

rm -rf "$APP_PATH"
ditto "$APP_STAGE_PATH" "$APP_PATH"

if [[ "$INCLUDE_BUNDLED_MODEL" == "1" ]]; then
  echo "[6/6] Done: $APP_PATH (with bundled model $MODEL_VARIANT)"
else
  echo "[6/6] Done: $APP_PATH (runtime Whisper auto-download enabled)"
fi

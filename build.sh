#!/usr/bin/env bash
# Build Laura.app from the SPM target and wrap it in a proper macOS bundle.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${CONFIG:-release}"
APP_NAME="Ben"
APP_DIR="$APP_NAME.app"

echo "▸ swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN_PATH=".build/$CONFIG/$APP_NAME"
if [[ ! -f "$BIN_PATH" ]]; then
  BIN_PATH=".build/arm64-apple-macosx/$CONFIG/$APP_NAME"
fi
if [[ ! -f "$BIN_PATH" ]]; then
  echo "✗ binary not found after build" >&2
  exit 1
fi

echo "▸ assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp Info.plist "$APP_DIR/Contents/Info.plist"
if [[ -f AppIcon.icns ]]; then
  cp AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
else
  echo "⚠  AppIcon.icns missing — run \`swift make-icon.swift\` to regenerate"
fi

echo "▸ ad-hoc signing (for local use; mic + speech prompts depend on a stable bundle ID)"
ENT_FILE="$(mktemp -t ben-entitlements.XXXXXX.plist)"
cat > "$ENT_FILE" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.device.audio-input</key><true/>
</dict></plist>
EOF
codesign --force --sign - --options runtime \
  --entitlements "$ENT_FILE" "$APP_DIR" >/dev/null
rm -f "$ENT_FILE"

echo "✓ built $APP_DIR"
echo "  Run with: open $(pwd)/$APP_DIR"

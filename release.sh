#!/usr/bin/env bash
# Cut a signed, notarized release of Ben.
#
# Usage:
#   ./release.sh v0.0.2
#
# Prerequisites (one-time setup):
#   1. A "Developer ID Application" cert imported into your Keychain.
#      Verify with: security find-identity -p codesigning -v
#   2. Notarization credentials stored in Keychain:
#        xcrun notarytool store-credentials ben-notary \
#          --apple-id "<your-apple-id>" \
#          --team-id  "<your-10-char-team-id>" \
#          --password "<app-specific-password>"
#      App-specific password: https://appleid.apple.com → App-Specific Passwords
#   3. `gh` CLI authenticated: `gh auth status` should be green.
#
# Per-release prep:
#   - Bump CFBundleShortVersionString in Info.plist to match $VERSION (minus 'v').
#   - Update CHANGELOG.md.
#   - Commit on main.
#
# Then run this script. It will:
#   1. Verify the version in Info.plist matches the arg.
#   2. Tag and push.
#   3. Build the .app, sign with Developer ID + hardened runtime.
#   4. Notarize the .app, wait for Accepted, staple the ticket.
#   5. Build a DMG, sign and notarize it too, staple.
#   6. SHA-256 the DMG.
#   7. Create a GitHub Release with both assets.
set -euo pipefail
cd "$(dirname "$0")"

if [[ $# -ne 1 ]]; then
    echo "usage: $0 vX.Y.Z" >&2
    exit 1
fi
VERSION="$1"
[[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+ ]] || {
    echo "✗ tag must look like vX.Y.Z (got '$VERSION')" >&2
    exit 1
}
PLIST_VERSION="${VERSION#v}"
NOTARY_PROFILE="${NOTARY_PROFILE:-ben-notary}"
DMG="Ben-${VERSION}.dmg"

step() { printf "\n▸ %s\n" "$*"; }
fail() { printf "✗ %s\n" "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 1. Sanity checks
# ---------------------------------------------------------------------------
step "Sanity checks"

ID="$(security find-identity -p codesigning -v 2>/dev/null \
        | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
[[ -n "$ID" ]] || fail "no 'Developer ID Application' identity in Keychain. \
Double-click your .p12 to import, or generate one at developer.apple.com."

xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
    || fail "notary profile '$NOTARY_PROFILE' not configured. Run: \
xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id ... --team-id ... --password ..."

gh auth status >/dev/null 2>&1 || fail "gh not authenticated. Run: gh auth login"

PLIST_VER_ACTUAL=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
[[ "$PLIST_VER_ACTUAL" == "$PLIST_VERSION" ]] || fail "Info.plist version is '$PLIST_VER_ACTUAL', expected '$PLIST_VERSION'. \
Bump it and commit before releasing."

[[ -z "$(git status --porcelain)" ]] || fail "working tree dirty. Commit or stash first."

git fetch origin
[[ "$(git rev-parse @)" == "$(git rev-parse '@{u}')" ]] || fail "local main is not in sync with origin/main."

echo "  identity:        $ID"
echo "  notary profile:  $NOTARY_PROFILE"
echo "  plist version:   $PLIST_VER_ACTUAL"

# ---------------------------------------------------------------------------
# 2. Tag
# ---------------------------------------------------------------------------
step "Tag $VERSION"
if git rev-parse "$VERSION" >/dev/null 2>&1; then
    echo "  tag $VERSION already exists locally, skipping"
else
    git tag "$VERSION" -m "Release $VERSION"
fi
git push origin "$VERSION"

# ---------------------------------------------------------------------------
# 3. Build + sign the .app
# ---------------------------------------------------------------------------
step "Build .app"
swift build -c release
rm -rf Ben.app
mkdir -p Ben.app/Contents/MacOS Ben.app/Contents/Resources
BIN_PATH=".build/release/Ben"
[[ -f "$BIN_PATH" ]] || BIN_PATH=".build/arm64-apple-macosx/release/Ben"
cp "$BIN_PATH" Ben.app/Contents/MacOS/Ben
cp Info.plist  Ben.app/Contents/Info.plist
cp AppIcon.icns Ben.app/Contents/Resources/AppIcon.icns

step "Sign .app with Developer ID + hardened runtime"
ENT_FILE="$(mktemp -t ben-entitlements.XXXXXX.plist)"
cat > "$ENT_FILE" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.device.audio-input</key><true/>
</dict></plist>
EOF
codesign --force --options runtime --timestamp \
         --sign "$ID" --entitlements "$ENT_FILE" Ben.app
rm -f "$ENT_FILE"
codesign --verify --verbose=2 Ben.app

# ---------------------------------------------------------------------------
# 4. Notarize the .app
# ---------------------------------------------------------------------------
step "Notarize .app (Apple notary, may take 1–3 min)"
APP_ZIP="Ben-${VERSION}-app.zip"
ditto -c -k --keepParent Ben.app "$APP_ZIP"
xcrun notarytool submit "$APP_ZIP" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
rm -f "$APP_ZIP"
xcrun stapler staple Ben.app
spctl --assess --verbose=2 Ben.app

# ---------------------------------------------------------------------------
# 5. Build + sign + notarize the DMG
# ---------------------------------------------------------------------------
step "Build DMG"
rm -rf dmg-staging "$DMG"
mkdir -p dmg-staging
cp -R Ben.app dmg-staging/
ln -s /Applications dmg-staging/Applications
hdiutil create -volname "Ben" -srcfolder dmg-staging -ov -format UDZO -fs HFS+ "$DMG"

step "Sign DMG"
codesign --force --sign "$ID" --timestamp "$DMG"

step "Notarize DMG"
xcrun notarytool submit "$DMG" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
xcrun stapler staple "$DMG"
spctl --assess --verbose=2 --type install "$DMG"

shasum -a 256 "$DMG" > "${DMG}.sha256"

# ---------------------------------------------------------------------------
# 6. GitHub Release
# ---------------------------------------------------------------------------
step "Publish GitHub Release"
NOTES_FILE="$(mktemp -t ben-release-notes.XXXXXX.md)"
cat > "$NOTES_FILE" <<EOF
## Install

1. Download \`$DMG\` below.
2. Open the DMG, drag **Ben.app** to **Applications**.
3. Launch normally — this build is signed with a Developer ID certificate
   and notarized by Apple, so Gatekeeper will allow it on the first try.
4. Grant **Microphone** and **Speech Recognition** permissions when prompted.
5. Make sure **Dictation** is enabled in *System Settings → Keyboard → Dictation*.

## Verify the download

\`\`\`
shasum -a 256 -c ${DMG}.sha256
\`\`\`

## Requirements

- macOS 15 (Sequoia) or later
- EN ⇄ DE translation pair (macOS prompts to download on first use)

## Changes

See [CHANGELOG.md](https://github.com/alileza/ben/blob/main/CHANGELOG.md).
EOF

if gh release view "$VERSION" >/dev/null 2>&1; then
    gh release upload "$VERSION" --clobber "$DMG" "${DMG}.sha256"
else
    gh release create "$VERSION" \
        --title "Ben $VERSION" \
        --notes-file "$NOTES_FILE" \
        --generate-notes \
        "$DMG" "${DMG}.sha256"
fi
rm -f "$NOTES_FILE"

step "Done"
echo "  → https://github.com/alileza/ben/releases/tag/$VERSION"

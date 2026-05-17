#!/usr/bin/env bash
# Cut an ad-hoc-signed release of Ben and publish to GitHub Releases.
#
# Usage:
#   ./release.sh v0.0.2
#
# Prerequisites:
#   - `gh` CLI authenticated (`gh auth status` green).
#
# Per-release prep:
#   - Bump CFBundleShortVersionString in Info.plist to match $VERSION (minus 'v').
#   - Update CHANGELOG.md.
#   - Commit on main, push.
#
# Then run this script. It will:
#   1. Verify the version in Info.plist matches the arg.
#   2. Tag and push.
#   3. Build the .app, ad-hoc sign it.
#   4. Build a DMG with a drag-to-/Applications layout.
#   5. SHA-256 the DMG.
#   6. Create a GitHub Release with both assets and install instructions.
#
# Users will need to right-click Ben.app → Open the first time because the
# bundle is ad-hoc signed (Gatekeeper doesn't trust the publisher). This is
# noted in the auto-generated release notes.
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
DMG="Ben-${VERSION}.dmg"

step() { printf "\n▸ %s\n" "$*"; }
fail() { printf "✗ %s\n" "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 1. Sanity checks
# ---------------------------------------------------------------------------
step "Sanity checks"

gh auth status >/dev/null 2>&1 || fail "gh not authenticated. Run: gh auth login"

PLIST_VER_ACTUAL=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
[[ "$PLIST_VER_ACTUAL" == "$PLIST_VERSION" ]] || fail \
    "Info.plist version is '$PLIST_VER_ACTUAL', expected '$PLIST_VERSION'. \
Bump it and commit before releasing."

[[ -z "$(git status --porcelain)" ]] || fail "working tree dirty. Commit or stash first."

git fetch origin
[[ "$(git rev-parse @)" == "$(git rev-parse '@{u}')" ]] \
    || fail "local main is not in sync with origin/main."

echo "  plist version: $PLIST_VER_ACTUAL"
echo "  tag:           $VERSION"

# ---------------------------------------------------------------------------
# 2. Tag
# ---------------------------------------------------------------------------
step "Tag $VERSION"
if git rev-parse "$VERSION" >/dev/null 2>&1; then
    echo "  tag $VERSION already exists locally, skipping create"
else
    git tag "$VERSION" -m "Release $VERSION"
fi
git push origin "$VERSION"

# ---------------------------------------------------------------------------
# 3. Build the .app (uses the existing build.sh which ad-hoc signs)
# ---------------------------------------------------------------------------
step "Build .app"
./build.sh
test -f Ben.app/Contents/MacOS/Ben || fail "build did not produce Ben.app"
codesign -dv Ben.app 2>&1 | head -5

# ---------------------------------------------------------------------------
# 4. Build the DMG
# ---------------------------------------------------------------------------
step "Build $DMG"
rm -rf dmg-staging "$DMG"
mkdir -p dmg-staging
cp -R Ben.app dmg-staging/
ln -s /Applications dmg-staging/Applications
hdiutil create \
    -volname "Ben" \
    -srcfolder dmg-staging \
    -ov \
    -format UDZO \
    -fs HFS+ \
    "$DMG"

shasum -a 256 "$DMG" > "${DMG}.sha256"
ls -lh "$DMG"

# ---------------------------------------------------------------------------
# 5. GitHub Release
# ---------------------------------------------------------------------------
step "Publish GitHub Release"
NOTES_FILE="$(mktemp -t ben-release-notes.XXXXXX.md)"
cat > "$NOTES_FILE" <<EOF
## Install

1. Download \`$DMG\` below.
2. Open the DMG and drag **Ben.app** to **Applications**.
3. **First launch:** right-click **Ben.app** → **Open** to bypass Gatekeeper. This is an ad-hoc-signed build; macOS doesn't recognize the publisher.
   One-liner alternative:
   \`\`\`
   xattr -dr com.apple.quarantine /Applications/Ben.app
   \`\`\`
4. Grant **Microphone** and **Speech Recognition** permissions when prompted.
5. Make sure **Dictation** is enabled in *System Settings → Keyboard → Dictation*, otherwise \`SFSpeechRecognizer\` won't return results.

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

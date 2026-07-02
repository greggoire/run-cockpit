#!/usr/bin/env bash
#
# release.sh — Build a distributable RunCockpit.dmg (ad-hoc signed) and print
# the Homebrew cask stanza + the manual-release checklist.
#
# No Apple Developer Program required. The DMG is NOT notarized, so users must
# strip quarantine (xattr) or install via `brew install --cask --no-quarantine`.
#
# Usage:
#   scripts/release.sh            # version read from the Xcode project
#   scripts/release.sh 1.1        # override version
#
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-$(grep -m1 'MARKETING_VERSION' RunCockpit.xcodeproj/project.pbxproj \
  | sed -E 's/.*= *([^;]+);.*/\1/' | tr -d ' ')}"
[[ -n "$VERSION" ]] || { echo "❌ Could not determine version"; exit 1; }

echo "▶︎ Releasing RunCockpit v$VERSION"
scripts/build-local.sh --dmg --adhoc

DMG="build/RunCockpit.dmg"
[[ -f "$DMG" ]] || { echo "❌ $DMG not found"; exit 1; }
SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"

# self-check: sha256 must be 64 hex chars
[[ "$SHA" =~ ^[0-9a-f]{64}$ ]] || { echo "❌ Bad sha256: $SHA"; exit 1; }

cat <<EOF

────────────────────────────────────────────────────────────
✅ $DMG built (v$VERSION), sha256: $SHA

Cask stanza for greggoire/homebrew-tap → Casks/run-cockpit.rb:

  version "$VERSION"
  sha256 "$SHA"

Manual release steps:
  1. git tag v$VERSION && git push origin v$VERSION
  2. Create the GitHub Release for tag v$VERSION and upload $DMG
       gh release create v$VERSION $DMG --title "v$VERSION"
  3. Update version+sha256 in Casks/run-cockpit.rb, copy it into the
     greggoire/homebrew-tap repo (Casks/run-cockpit.rb), commit & push.
     (First release: create the repo "homebrew-tap" once.)
────────────────────────────────────────────────────────────
EOF
